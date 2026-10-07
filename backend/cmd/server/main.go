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
	"github.com/skyP38/flowchart_editor/backend/internal/service/seed"
	"github.com/skyP38/flowchart_editor/backend/internal/service/sessioncleanup"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

func main() {
	// загрузка конфига из переменных окружения
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	// in-memory реализация хранилищ
	users := memory.NewMemoryUserRepo()
	sessions := memory.NewMemorySessionRepo()

	// фоновый чистильщик сессий
	janitor, err := sessioncleanup.New(sessions, cfg.SessionCleanupInterval, cfg.SessionRetention)
	if err != nil {
		log.Fatalf("session janitor :%v", err)
	}

	// создание админа при первом запуске
	if err := seed.Admin(context.Background(), users, cfg.AdminLogin, cfg.AdminPassword, cfg.PasswordPepper); err != nil {
		log.Fatalf("seed admin: %v", err)
	}

	// менеджер access-токенов
	accessMgr := token.NewAccessTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)

	// политика rate limit
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

	// сервис аутентификации
	authSvc := auth.NewService(users, sessions, accessMgr, cfg.PasswordPepper, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	authMW := api.Auth(accessMgr, sessions)

	// middlewera аутентификации
	mux := http.NewServeMux()

	// health-check
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// регистрация маршрутов обработчиков
	api.NewAuthHandler(authSvc, limiter).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)
	api.NewAdminHandler(sessions).RegisterRoutes(mux, authMW)

	// сборка middleware
	handler := transport.Chain(mux,
		transport.Recover,
		transport.Logging,
		transport.CORS,
		transport.BodyLimit(transport.DefaultMaxBodyBytes, map[string]int64{
			"/api/editor/upload": 25 << 20, // 25 MiB - только для загрузки - TODO: нужно позже
		}),
	)

	// http-сервер
	srv := &http.Server{
		Addr:    ":" + cfg.AppPort,
		Handler: handler,
		// ограничение времени чтения заголовка запроса
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

	// SIGINT || SIGTERM
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	_ = janitor.Close()
	_ = limiter.Close()

	log.Println("stopped")
}
