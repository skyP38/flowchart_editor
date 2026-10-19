package api

import (
	"net/http"

	"github.com/skyP38/flowchart_editor/backend/internal/service"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
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
	transport.WriteJSON(w, http.StatusOK, user)
}
