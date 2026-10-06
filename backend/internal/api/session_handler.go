package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"flowchart_editor/backend/middleware"
	"flowchart_editor/backend/repositories"
	"flowchart_editor/backend/services"
)

type SessionHandler struct {
	service *services.SessionService
}

func NewSessionHandler(
	service *services.SessionService,
) *SessionHandler {
	return &SessionHandler{service: service}
}

func (h *SessionHandler) List(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := api.UserID(r.Context())
	sessions, err := h.service.List(r.Context(), userID)
	if err != nil {
		http.Error(w, "failed to list sessions", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

func (h *SessionHandler) Close(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := api.UserID(r.Context())
	sessionID, err := strconv.ParseInt(r.PathValue("sessionId"), 10, 64)
	if err != nil {
		http.Error(w, "invalid session id", http.StatusBadRequest)
		return
	}
	err = h.service.Close(r.Context(), userID, sessionID)
	if errors.Is(err, repositories.ErrNotFound) {
		http.Error(w, "session not found or already closed", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "failed to close session", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
