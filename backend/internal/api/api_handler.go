package handlers

import (
    "encoding/json"
    "errors"
    "net/http"
    "strconv"

    "github.com/skyP38/flowchart_editor/backend/internal/api"
    "flowchart_editor/backend/repositories"
    "flowchart_editor/backend/services"
)

type ProjectHandler struct {
    service *services.ProjectService
}

func NewProjectHandler(
    service *services.ProjectService,
) *ProjectHandler {
    return &ProjectHandler{
        service: service,
    }
}

type CreateProjectRequest struct {
    Name string `json:"name"`
}

func (h *ProjectHandler) Create(
    w http.ResponseWriter,
    r *http.Request,
) {
    userID := api.UserID(r.Context())
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
    w.Header().Set(
        "Content-Type",
        "application/json",
    )
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(project)
}

func (h *ProjectHandler) Get(
    w http.ResponseWriter,
    r *http.Request,
) {
    userID := api.UserID(r.Context())
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
    if errors.Is(err, repositories.ErrNotFound) {
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
    w.Header().Set(
        "Content-Type",
        "application/json",
    )
    json.NewEncoder(w).Encode(project)
}

type UpdateProjectRequest struct {
    Name *string `json:"name"`
}

func (h *ProjectHandler) Update(
    w http.ResponseWriter,
    r *http.Request,
) {
    userID := api.UserID(r.Context())
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
    if errors.Is(err, repositories.ErrNotFound) {
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
    w.Header().Set(
        "Content-Type",
        "application/json",
    )

    json.NewEncoder(w).Encode(project)
}

func (h *ProjectHandler) Delete(
    w http.ResponseWriter,
    r *http.Request,
) {
    userID := api.UserID(r.Context())
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
    if errors.Is(err, repositories.ErrNotFound) {
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

func (h *ProjectHandler) List(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID := api.UserID(r.Context())
	projects, err := h.service.List(r.Context(), userID)
	if err != nil {
		http.Error(w, "failed to list projects", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(projects)
}

