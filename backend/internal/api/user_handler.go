package api

import (
	"encoding/json"
	"net/http"

	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
)

type UserHandler struct {
	service *auth.Service
}

func NewUserHandler(service *auth.Service) *UserHandler {
	return &UserHandler{service: service}
}

func (h *UserHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	userID := UserIDFrom(r.Context())
	user, err := h.service.GetUser(r.Context(), userID)
	if err != nil {
		http.Error(w, "failed to get user", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

/*package api

import (
	"encoding/json"
	"net/http"
	
	"github.com/skyP38/flowchart_editor/backend/internal/services"
	//"github.com/skyP38/flowchart_editor/backend/internal/services"

	//"github.com/skyP38/flowchart_editor/backend/internal/api"
)

type UserHandler struct {
	service *services.UserService
}

func NewUserHandler(service *services.UserService) *UserHandler {
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
}*/
