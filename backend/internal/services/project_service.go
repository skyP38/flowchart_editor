package services

import (
	"context"
	"strings"

	"flowchart_editor/backend/models"
	"flowchart_editor/backend/repositories"
)

type ProjectService struct {
	repository *repositories.ProjectRepository
}

func NewProjectService(
	repository *repositories.ProjectRepository,
) *ProjectService {
	return &ProjectService{repository: repository}
}

func (s *ProjectService) Create(
	ctx context.Context,
	userID int64,
	name string,
) (models.Project, error) {
	return s.repository.Create(ctx, userID, name)
}

func (s *ProjectService) List(
	ctx context.Context,
	userID int64,
) ([]models.Project, error) {
	return s.repository.ListByUser(ctx, userID)
}

func (s *ProjectService) Update(
	ctx context.Context,
	userID int64,
	projectID int64,
	name string,
) (models.Project, error) {
	return s.repository.Update(ctx, projectID, userID, name)
}

func (s *ProjectService) Delete(
	ctx context.Context,
	userID int64,
	projectID int64,
) error {
	return s.repository.Delete(ctx, projectID, userID)
}
