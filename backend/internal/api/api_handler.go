package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

type ProjectHandler struct {
	service *service.ProjectService
}

func NewProjectHandler(
	service *service.ProjectService,
) *ProjectHandler {
	return &ProjectHandler{
		service: service,
	}
}

func (h *ProjectHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.Handle("POST /api/projects", authMW(http.HandlerFunc(h.Create)))
	mux.Handle("GET /api/projects", authMW(http.HandlerFunc(h.List)))
	mux.Handle("GET /api/projects/{projectId}", authMW(http.HandlerFunc(h.Get)))
	mux.Handle("PATCH /api/projects/{projectId}", authMW(http.HandlerFunc(h.Update)))
	mux.Handle("DELETE /api/projects/{projectId}", authMW(http.HandlerFunc(h.Delete)))
}

type CreateProjectRequest struct {
	Name string `json:"name"`
}

// Create godoc
// @Summary Create project
// @Decsription Create new project for current user
// @Tags Projects
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body CreateProjectRequest true "Project name"
// @Success 201 {object} domains.Project
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects [post]
func (h *ProjectHandler) Create(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	var request CreateProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(
			w,
			"invalid JSON",
			http.StatusBadRequest,
		)
		return
	}
	if request.Name == "" {
		http.Error(
			w,
			"name is required",
			http.StatusBadRequest,
		)
		return
	}
	project, err := h.service.Create(
		r.Context(),
		userID,
		request.Name,
	)
	if err != nil {
		http.Error(
			w,
			"failed to create project",
			http.StatusInternalServerError,
		)
		return
	}
	transport.WriteJSON(w, http.StatusCreated, project)
}

// Get godoc
// @Summary Get project
// @Decsription Returns the project according to its id
// @Tags Projects
// @Produce json
// @Security BearerAuth
// @Param projectId path int true "ID Project"
// @Success 200 {object} domains.Project
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 404 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId} [get]
func (h *ProjectHandler) Get(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	projectID, err := strconv.ParseInt(
		r.PathValue("projectId"),
		10,
		64,
	)
	if err != nil {
		http.Error(
			w,
			"invalid project id",
			http.StatusBadRequest,
		)
		return
	}
	project, err := h.service.Get(
		r.Context(),
		userID,
		projectID,
	)
	if errors.Is(err, domains.ErrNotFound) {
		http.Error(
			w,
			"project not found",
			http.StatusNotFound,
		)
		return
	}
	if err != nil {
		http.Error(
			w,
			"failed to get project",
			http.StatusInternalServerError,
		)
		return
	}
	transport.WriteJSON(w, http.StatusCreated, project)
}

type UpdateProjectRequest struct {
	Name *string `json:"name"`
}

// Update godoc
// @Summary Update project
// @Decsription Changes the name of the existing project
// @Tags Projects
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param projectId path int true "ID Project"
// @Param request body UpdateProjectRequest true "New data of project"
// @Success 200 {object} domains.Project
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 404 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId} [patch]
func (h *ProjectHandler) Update(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	projectID, err := strconv.ParseInt(
		r.PathValue("projectId"),
		10,
		64,
	)
	if err != nil {
		http.Error(
			w,
			"invalid project id",
			http.StatusBadRequest,
		)
		return
	}
	var request UpdateProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(
			w,
			"invalid JSON",
			http.StatusBadRequest,
		)
		return
	}
	if request.Name == nil || *request.Name == "" {
		http.Error(
			w,
			"name is required",
			http.StatusBadRequest,
		)
		return
	}
	project, err := h.service.Update(
		r.Context(),
		userID,
		projectID,
		*request.Name,
	)
	if errors.Is(err, domains.ErrNotFound) {
		http.Error(
			w,
			"project not found",
			http.StatusNotFound,
		)
		return
	}
	if err != nil {
		http.Error(
			w,
			"failed to update project",
			http.StatusInternalServerError,
		)
		return
	}
	transport.WriteJSON(w, http.StatusCreated, project)
}

// Delete godoc
// @Summary Delete project
// @Decsription Delete project of the existing user
// @Tags Projects
// @Security BearerAuth
// @Param projectId path int true "ID Project"
// @Success 204 "Project successfully delete"
// @Failure 400 {object} transport.ErrorResponse
// @Failure 401 {object} transport.ErrorResponse
// @Failure 404 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects/{projectId} [delete]
func (h *ProjectHandler) Delete(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	projectID, err := strconv.ParseInt(
		r.PathValue("projectId"),
		10,
		64,
	)
	if err != nil {
		http.Error(
			w,
			"invalid project id",
			http.StatusBadRequest,
		)
		return
	}
	err = h.service.Delete(
		r.Context(),
		userID,
		projectID,
	)
	if errors.Is(err, domains.ErrNotFound) {
		http.Error(
			w,
			"project not found",
			http.StatusNotFound,
		)
		return
	}
	if err != nil {
		http.Error(
			w,
			"failed to delete project",
			http.StatusInternalServerError,
		)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ListProjects godoc
// @Summary User projects list
// @Decription Return projects list
// @Tags Projects
// @Produce json
// @Security BearerAuth
// Success 200 {array} domains.Project
// @Failure 401 {object} transport.ErrorResponse
// @Failure 500 {object} transport.ErrorResponse
// @Router /projects [get]
func (h *ProjectHandler) List(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := UserIDFrom(r.Context())
	projects, err := h.service.List(r.Context(), userID)
	if err != nil {
		http.Error(w, "failed to list projects", http.StatusInternalServerError)
		return
	}
	if projects == nil {
		projects = []domains.Project{}
	}
	transport.WriteJSON(w, http.StatusOK, projects)
}
