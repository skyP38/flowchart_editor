package api

import (
	"net/http"
	"strconv"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

type SessionHandler struct {
	svc *auth.Service
}

func NewSessionHandler(svc *auth.Service) *SessionHandler {
	return &SessionHandler{svc: svc}
}

func (h *SessionHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.Handle("GET /api/sessions", authMW(http.HandlerFunc(h.List)))
	mux.Handle("DELETE /api/sessions/{id}", authMW(http.HandlerFunc(h.RevokeOne)))
	mux.Handle("DELETE /api/sessions", authMW(http.HandlerFunc(h.RevokeAll)))
}

type sessionDTO struct {
	ID        int64      `json:"id"`
	CreatedAt time.Time  `json:"created_at"`
	ExpiresAt time.Time  `json:"expires_at"`
	RevokedAt *time.Time `json:"revoked_at,omitempty"`
	Active    bool       `json:"active"`
	Current   bool       `json:"current"`
}

// List - GET /api/sessions
func (h *SessionHandler) List(w http.ResponseWriter, r *http.Request) {
	uid := UserIDFrom(r.Context())
	cur := SessionIDFrom(r.Context())

	sessions, err := h.svc.ListSessions(r.Context(), uid)
	if err != nil {
		transport.WriteError(w, http.StatusInternalServerError, "internal", "internal server error")
		return
	}
	now := time.Now().UTC()
	out := make([]sessionDTO, 0, len(sessions))
	for _, s := range sessions {
		out = append(out, toSessionDTO(s, cur, now))
	}
	transport.WriteJSON(w, http.StatusOK, map[string]any{"sessions": out})
}

// RevokeOne - DELETE /api/sessions/{id}
func (h *SessionHandler) RevokeOne(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", "invalid session id")
		return
	}
	if err := h.svc.RevokeSession(r.Context(), UserIDFrom(r.Context()), id); err != nil {
		transport.WriteError(w, http.StatusNotFound, "session_not_found", "session not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RevokeAll - DELETE /api/sessions
// Закрывает все сессии пользователя, кроме текущей
func (h *SessionHandler) RevokeAll(w http.ResponseWriter, r *http.Request) {
	uid := UserIDFrom(r.Context())
	cur := SessionIDFrom(r.Context())
	if err := h.svc.RevokeAllSessions(r.Context(), uid, cur); err != nil {
		transport.WriteError(w, http.StatusInternalServerError, "internal", "internal server error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func toSessionDTO(s *domains.Session, currentID int64, now time.Time) sessionDTO {
	return sessionDTO{
		ID:        s.ID,
		CreatedAt: s.CreatedAt,
		ExpiresAt: s.ExpiresAt,
		RevokedAt: s.RevokedAt,
		Active:    s.IsActive(now),
		Current:   s.ID == currentID,
	}
}
