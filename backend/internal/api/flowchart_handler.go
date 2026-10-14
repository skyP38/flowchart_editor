package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

type FlowchartHandler struct {
	service *service.FlowchartService
}

func NewFlowchartHandler(
	service *service.FlowchartService,
) *FlowchartHandler {
	return &FlowchartHandler{service: service}
}

func (h *FlowchartHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.Handle("POST /api/projects/{projectId}/flowcharts", authMW(http.HandlerFunc(h.Create)))
	mux.Handle("DELETE /api/projects/{projectId}/flowcharts/{flowchartId}", authMW(http.HandlerFunc(h.Delete)))

	mux.Handle("GET /api/projects/{projectId}/flowcharts/{flowchartId}/content",
		authMW(http.HandlerFunc(h.GetContent)))
	mux.Handle("PUT /api/projects/{projectId}/flowcharts/{flowchartId}/content",
		authMW(http.HandlerFunc(h.UpdateContent)))
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
	if errors.Is(err, domains.ErrNotFound) {
		http.Error(w, "flowchart not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "failed to delete flowchart", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *FlowchartHandler) GetContent(w http.ResponseWriter, r *http.Request) {
	userID := UserIDFrom(r.Context())

	projectID, err := strconv.ParseInt(r.PathValue("projectId"), 10, 64)
	if err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "invalid project id")
		return
	}
	flowchartID, err := strconv.ParseInt(r.PathValue("flowchartId"), 10, 64)
	if err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "invalid flowchart id")
		return
	}

	data, err := h.service.GetContent(r.Context(), userID, projectID, flowchartID)
	if errors.Is(err, domains.ErrNotFound) {
		transport.WriteError(w, http.StatusNotFound, transport.CodeNotFound, "flowchart not found")
		return
	}
	if err != nil {
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}

	// data уже валидный jsonb, отдаём как есть
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func (h *FlowchartHandler) UpdateContent(w http.ResponseWriter, r *http.Request) {
	userID := UserIDFrom(r.Context())

	projectID, err := strconv.ParseInt(r.PathValue("projectId"), 10, 64)
	if err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "invalid project id")
		return
	}
	flowchartID, err := strconv.ParseInt(r.PathValue("flowchartId"), 10, 64)
	if err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "invalid flowchart id")
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "cannot read body")
		return
	}
	if !json.Valid(body) {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "invalid JSON body")
		return
	}

	err = h.service.UpdateContent(r.Context(), userID, projectID, flowchartID, body)
	if errors.Is(err, domains.ErrNotFound) {
		transport.WriteError(w, http.StatusNotFound, transport.CodeNotFound, "flowchart not found")
		return
	}
	if err != nil {
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
