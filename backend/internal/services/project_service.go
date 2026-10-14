package services

import (
	"context"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
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
) (domains.Project, error) {
	return s.repository.Create(ctx, userID, name)
}

func (s *ProjectService) List(
	ctx context.Context,
	userID int64,
) ([]domains.Project, error) {
	return s.repository.ListByUser(ctx, userID)
}

func (s *ProjectService) Update(
	ctx context.Context,
	userID int64,
	projectID int64,
	name string,
) (domains.Project, error) {
	return s.repository.Update(ctx, projectID, userID, name)
}

func (s *ProjectService) Delete(
	ctx context.Context,
	userID int64,
	projectID int64,
) error {
	return s.repository.Delete(ctx, projectID, userID)
}

func (s *ProjectService) Get(
	ctx context.Context,
	userID int64,
	projectID int64,
) (domains.Project, error) {
	return s.repository.GetByID(ctx, userID, projectID)
}
