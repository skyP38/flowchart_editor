package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"github.com/skyP38/flowchart_editor/backend/internal/config"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/service/ratelimit"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

func main() {

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	users := memory.NewMemoryUserRepo()
	sessions := memory.NewMemorySessionRepo()

	if err := memory.SeedAdmin(context.Background(), users, cfg.AdminLogin, cfg.AdminPassword, cfg.PasswordPepper); err != nil {
		log.Fatalf("seed admin: %v", err)
	}

	accessMgr := token.NewAccessTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)
	reservedLogins := []string{cfg.AdminLogin}

	loginPolicy := ratelimit.Policy{
		MaxAttempts:   cfg.RatelimitLoginMaxAttempts,
		Window:        cfg.RatelimitLoginWindow,
		BlockDuration: cfg.RatelimitLoginBlockDuration,
		MaxBlockCount: cfg.RatelimitLoginMaxBlockCount,
		DecayWindow:   cfg.RatelimitLoginDecayWindow,
	}
	limiter, err := ratelimit.NewMemoryLimiter(
		map[string]ratelimit.Policy{"login": loginPolicy},
		cfg.RatelimitCleanupInterval,
	)
	if err != nil {
		log.Fatalf("ratelimit: %v", err)
	}

	authSvc := auth.NewService(users, sessions, accessMgr, cfg.PasswordPepper, cfg.AccessTokenTTL, cfg.RefreshTokenTTL, reservedLogins)
	authMW := api.Auth(accessMgr, sessions)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	api.NewAuthHandler(authSvc, limiter).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)

	handler := transport.Chain(mux,
		transport.Recover,
		transport.Logging,
		transport.CORS,
		transport.BodyLimit(transport.DefaultMaxBodyBytes, map[string]int64{
			"/api/editor/upload": 25 << 20, // 25 MiB - только для загрузки - нужно позже
		}),
	)

	srv := &http.Server{
		Addr:              ":" + cfg.AppPort,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
	}
	go func() {
		log.Printf("server listening on :%s", cfg.AppPort)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	_ = limiter.Close()
	log.Println("stopped")
}
