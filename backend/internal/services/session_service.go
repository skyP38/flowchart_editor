package services

import (
	"context"

	"flowchart_editor/backend/models"
	"flowchart_editor/backend/repositories"
)

type SessionService struct {
	repository *repositories.SessionRepository
}

func NewSessionService(
	repository *repositories.SessionRepository,
) *SessionService {
	return &SessionService{repository: repository}
}

func (s *SessionService) List(
	ctx context.Context,
	userID int64,
) ([]models.Session, error) {
	return s.repository.ListByUser(ctx, userID)
}

func (s *SessionService) Close(
	ctx context.Context,
	userID int64,
	sessionID int64,
) error {
	return s.repository.Close(ctx, sessionID, userID)
}
