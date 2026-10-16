package api

import (
	"encoding/json"
	"net/http"

	"github.com/skyP38/flowchart_editor/backend/internal/service"
)

type UserHandler struct {
	service *service.UserService
}

func NewUserHandler(service *service.UserService) *UserHandler {
	return &UserHandler{service: service}
}

func (h *UserHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	userID := UserIDFrom(r.Context())
	user, err := h.service.GetByID(r.Context(), userID)
	if err != nil {
		http.Error(w, "failed to get user", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}
