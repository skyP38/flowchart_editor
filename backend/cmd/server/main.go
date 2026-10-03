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
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"github.com/skyP38/flowchart_editor/backend/internal/config"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

func main() {

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	db_url := os.Getenv("DATABASE_URL")
	if db_url == "" {
		log.Fatal("DATABASE_URL is not set")
	}
	db, err := pgxpool.New(context.Background(), db_url,)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	log.Println("Connected to PostgreSQL")

	users := memory.NewMemoryUserRepo()
	sessions := memory.NewMemorySessionRepo()

	if err := memory.SeedAdmin(context.Background(), users, cfg.AdminLogin, cfg.AdminPassword, cfg.PasswordPepper); err != nil {
		log.Fatalf("seed admin: %v", err)
	}

	accessMgr := token.NewAccessTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)
	authSvc := auth.NewService(users, sessions, accessMgr, cfg.PasswordPepper, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	authMW := api.Auth(accessMgr)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	api.NewAuthHandler(authSvc).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)

	handler := transport.Chain(mux,
		transport.Recover,
		transport.Logging,
		transport.CORS,
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
	log.Println("stopped")
}
