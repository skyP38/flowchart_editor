package service

import (
	"context"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
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
) ([]*domains.Session, error) {
	return s.repository.ListByUserID(ctx, userID)
}

func (s *SessionService) Close(
	ctx context.Context,
	userID int64,
	sessionID int64,
) error {
	return s.repository.Close(ctx, sessionID, userID)
}
