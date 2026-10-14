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
	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/service/ratelimit"
	"github.com/skyP38/flowchart_editor/backend/internal/service/sessioncleanup"
	"github.com/skyP38/flowchart_editor/backend/internal/services"

	//"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

func main() {
	// загрузка конфига из переменных окружения
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	// фоновый чистильщик сессий
	janitor, err := sessioncleanup.New(sessions, cfg.SessionCleanupInterval, cfg.SessionRetention)
	if err != nil {
		log.Fatalf("session janitor :%v", err)
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL is not set")
	}
	db, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	log.Println("Connected to PostgreSQL")

	//users := memory.NewMemoryUserRepo()
	//sessions := memory.NewMemorySessionRepo()

	userRepo := repositories.NewUserRepository(db)
	sessionRepo := repositories.NewSessionRepository(db)

	/*if err := memory.SeedAdmin(context.Background(), users,
		cfg.AdminLogin, cfg.AdminPassword, cfg.PasswordPepper); err != nil {
		log.Fatalf("seed admin: %v", err)
	}*/

	// менеджер access-токенов
	accessMgr := token.NewAccessTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)
	authSvc := auth.NewService(userRepo, sessionRepo, accessMgr, cfg.PasswordPepper, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	authMW := api.Auth(accessMgr)

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

	projectRepo := repositories.NewProjectRepository(db)
	projectSvc := services.NewProjectService(projectRepo)
	projectHandler := api.NewProjectHandler(projectSvc)

	flowchartRepo := repositories.NewFlowchartRepository(db)
	flowchartSvc := services.NewFlowchartService(flowchartRepo)
	flowchartHandler := api.NewFlowchartHandler(flowchartSvc)

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

	// api.NewAuthHandler(authSvc).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)

	userHandler := api.NewUserHandler(authSvc)
	mux.Handle("GET /api/users/me", authMW(http.HandlerFunc(userHandler.GetMe)))

	mux.Handle("POST /api/projects", authMW(http.HandlerFunc(projectHandler.Create)))
	mux.Handle("GET /api/projects", authMW(http.HandlerFunc(projectHandler.List)))
	mux.Handle("GET /api/projects/{projectId}", authMW(http.HandlerFunc(projectHandler.Get)))
	mux.Handle("PATCH /api/projects/{projectId}", authMW(http.HandlerFunc(projectHandler.Update)))
	mux.Handle("DELETE /api/projects/{projectId}", authMW(http.HandlerFunc(projectHandler.Delete)))

	mux.Handle("POST /api/projects/{projectId}/flowcharts", authMW(http.HandlerFunc(flowchartHandler.Create)))
	mux.Handle("DELETE /api/projects/{projectId}/flowcharts/{flowchartId}", authMW(http.HandlerFunc(flowchartHandler.Delete)))

	staticFiles := http.FileServer(http.Dir("../frontend/build/web"))
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
