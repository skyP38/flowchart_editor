package service

import (
	"context"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
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
) (*domains.User, error) {
	return s.repository.GetByID(ctx, id)
}
