package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"log"

	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
	//"github.com/skyP38/flowchart_editor/backend/internal/repositories"
	"github.com/skyP38/flowchart_editor/backend/internal/services"
	//"github.com/skyP38/flowchart_editor/backend/internal/services"

	//"github.com/skyP38/flowchart_editor/backend/internal/api"
)

type FlowchartHandler struct {
	service *services.FlowchartService
}

func NewFlowchartHandler(
	service *services.FlowchartService,
) *FlowchartHandler {
	return &FlowchartHandler{service: service}
}

func (h *FlowchartHandler) Create(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	projectID, err := strconv.ParseInt(r.PathValue("projectId"), 10, 64)
	if err != nil {
		http.Error(w, "invalid project id", http.StatusBadRequest)
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}

	flowchart, err := h.service.Create(r.Context(), userID, projectID, req.Name)
	if err != nil {
		log.Printf("create flowchart: %v", err)
		http.Error(w, "failed to create flowchart", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(flowchart)
}

func (h *FlowchartHandler) Delete(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	flowchartID, err := strconv.ParseInt(r.PathValue("flowchartId"), 10, 64)
	if err != nil {
		http.Error(w, "invalid flowchart id", http.StatusBadRequest)
		return
	}
	err = h.service.Delete(r.Context(), userID, flowchartID)
	if errors.Is(err, repositories.ErrNotFound) {
		http.Error(w, "flowchart not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "failed to delete flowchart", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
