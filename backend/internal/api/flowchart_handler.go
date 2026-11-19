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

// Create godoc
// @Summary Create flowchart
// @Decsription Create new flowchart
// @Tags Flowcharts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param projectId path int true "ID Project"
// @Param request body object true "Data of flowcharts"
// @Success 201 {object} domains.Flowchart
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId}/flowcharts [post]
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
	transport.WriteJSON(w, http.StatusCreated, flowchart)
}

// Delete godoc
// @Summary Delete flowchart
// @Decsription Delete flowchart
// @Tags Flowcharts
// @Security BearerAuth
// @Param projectId path int true "ID Project"
// @Param flowchartId path int true  "ID flowchart"
// @Success 204 "Flowchart successfully delete"
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 404 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId}/flowcharts/{flowchartId} [delete]
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

// GetContent godoc
// @Summary Get the contents of flowchart
// @Decsription Return JSON-content of flowchart
// @Tags Flowcharts
// @Produce json
// @Security BearerAuth
// @Param projectId path int true "ID Project"
// @Param flowchartId path int true "ID Flowchart"
// @Success 200 {object} domains.Flowchart
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 404 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId}/flowcharts/{flowchartId}/content [get]
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

// UpdateContent godoc
// @Summary Uodate content of flowchart
// @Description Save new JSON-content flowchart
// @Tags Flowcharts
// @Accept json
// @Security BearerAuth
// @Param projectId path int true "ID project"
// @Param flowchartId path int true "ID flowchart"
// @Param request body object true "New content of flowchart"
// @Success 204 "Content update successful"
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 404 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId}/flowcharts/{flowchartId}/content [put]
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
