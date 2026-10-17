package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"github.com/skyP38/flowchart_editor/backend/internal/config"
	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
	"github.com/skyP38/flowchart_editor/backend/internal/service"

	// "github.com/skyP38/flowchart_editor/backend/internal/service"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/service/ratelimit"
	"github.com/skyP38/flowchart_editor/backend/internal/service/seed"
	"github.com/skyP38/flowchart_editor/backend/internal/service/sessioncleanup"

	//"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

func main() {
	// загрузка конфига из переменных окружения
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	// dbURL := os.Getenv("DATABASE_URL")
	// if dbURL == "" {
	// 	log.Fatal("DATABASE_URL is not set")
	// }
	db, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	log.Println("Connected to PostgreSQL")

	// репозитории
	userRepo := repositories.NewUserRepository(db)
	sessionRepo := repositories.NewSessionRepository(db)
	projectRepo := repositories.NewProjectRepository(db)
	flowchartRepo := repositories.NewFlowchartRepository(db)

	if err := seed.Admin(context.Background(), userRepo,
		cfg.AdminLogin, cfg.AdminPassword, cfg.PasswordPepper); err != nil {
		log.Fatalf("seed admin: %v", err)
	}

	// фоновый чистильщик сессий
	janitor, err := sessioncleanup.New(sessionRepo, cfg.SessionCleanupInterval, cfg.SessionRetention)
	if err != nil {
		log.Fatalf("session janitor :%v", err)
	}

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

	// менеджер access-токенов
	accessMgr := token.NewAccessTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)
	// сервис аутентификации
	authSvc := auth.NewService(userRepo, sessionRepo, accessMgr, cfg.PasswordPepper, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)

	// сервисы
	projectSvc := service.NewProjectService(projectRepo)
	flowchartSvc := service.NewFlowchartService(flowchartRepo)

	// обработчики
	projectHandler := api.NewProjectHandler(projectSvc)
	flowchartHandler := api.NewFlowchartHandler(flowchartSvc)

	// middleware аутентификации
	authMW := api.Auth(accessMgr, sessionRepo)

	mux := http.NewServeMux()

	// health-check
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// регистрация маршрутов обработчиков
	api.NewAuthHandler(authSvc, limiter).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)

	projectHandler.RegisterRoutes(mux, authMW)
	flowchartHandler.RegisterRoutes(mux, authMW)

	staticFiles := http.FileServer(http.Dir(cfg.StaticDir))
	mux.Handle("/", staticFiles)

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
		ReadHeaderTimeout: cfg.ReadHeaderTimeout,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
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
	ctx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("shutdown: %v", err)
	}

	_ = janitor.Close()
	_ = limiter.Close()

	log.Println("stopped")
}
