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
	"github.com/skyP38/flowchart_editor/backend/internal/services"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
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
	
	userRepo := repositories.NewUserRepository(db)
        sessionRepo := repositories.NewSessionRepository(db)

	accessMgr := token.NewAccessTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)
	authSvc := auth.NewService(userRepo, sessionRepo, accessMgr, cfg.PasswordPepper, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	authMW := api.Auth(accessMgr)

	projectRepo := repositories.NewProjectRepository(db)
	projectSvc := services.NewProjectService(projectRepo)
	projectHandler := api.NewProjectHandler(projectSvc)

	flowchartRepo := repositories.NewFlowchartRepository(db)
	flowchartSvc := services.NewFlowchartService(flowchartRepo)
	flowchartHandler := api.NewFlowchartHandler(flowchartSvc)

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	api.NewAuthHandler(authSvc).RegisterRoutes(mux, authMW)
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

	handler := transport.Chain(mux,
		transport.Recover,
		transport.Logging,
		transport.CORS,
	)

	srv := &http.Server{
		Addr: ":8080",
		Handler: handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 10 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	go func() {
		log.Printf("server listening on %s", srv.Addr)
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
