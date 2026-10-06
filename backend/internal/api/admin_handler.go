package api

import (
	"context"
	"log"
	"net/http"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

type SessionStatsProvider interface {
	Stats(ctx context.Context) (domains.SessionStats, error)
}

type AdminHandler struct {
	sessions *memory.MemorySessionRepo
}

func NewAdminHandler(m *memory.MemorySessionRepo) *AdminHandler {
	return &AdminHandler{sessions: m}
}

func (h *AdminHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.Handle("GET /api/admin/stats", authMW(RequireRole(domains.RoleAdmin)(http.HandlerFunc(h.Stats))))
}

func (h *AdminHandler) Stats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.sessions.Stats(r.Context())
	if err != nil {
		log.Printf("admin stats: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, "internal", "internal server error")
		return
	}
	transport.WriteJSON(w, http.StatusOK, map[string]any{"sessions": stats})

}
