package api

import (
	"context"
	"log"
	"net/http"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

// SessionStatsProvider предоставляет сводную статистику по сессиям
// Реализуется хранилищем сессий
type SessionStatsProvider interface {
	Stats(ctx context.Context) (domains.SessionStats, error)
}

// AdminHandler обслуживает административные маршруты
type AdminHandler struct {
	sessions SessionStatsProvider
}

func NewAdminHandler(s SessionStatsProvider) *AdminHandler {
	return &AdminHandler{sessions: s}
}

// RegisterRoutes регистрирует административные маршруты
func (h *AdminHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.Handle("GET /api/admin/stats", authMW(RequireRole(domains.RoleAdmin)(http.HandlerFunc(h.Stats))))
}

// Stats обрабатывает GET /api/admin/stats
func (h *AdminHandler) Stats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.sessions.Stats(r.Context())
	if err != nil {
		log.Printf("admin stats: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	transport.WriteJSON(w, http.StatusOK, map[string]any{"sessions": stats})
}
