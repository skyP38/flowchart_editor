package services

import (
	"context"

	"flowchart_editor/backend/models"
	"flowchart_editor/backend/repositories"
)

type UserService struct {
	repository *repositories.UserRepository
}

func NewUserService(
	repository *repositories.UserRepository,
) *UserService {
	return &UserService{repository: repository}
}

func (s *UserService) GetByID(
	ctx context.Context,
	id int64,
) (models.User, error) {
	return s.repository.GetByID(ctx, id)
}
