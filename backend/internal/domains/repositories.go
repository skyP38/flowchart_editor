package domains

import (
	"context"
	"time"
)

type UserRepository interface {
	Create(ctx context.Context, u *User) error
	GetByID(ctx context.Context, id int64) (*User, error)
	GetByLogin(ctx context.Context, login string) (*User, error)
}

type SessionRepository interface {
	Create(ctx context.Context, s *Session) error
	GetByTokenHash(ctx context.Context, tokenHash string) (*Session, error)
	GetByID(ctx context.Context, id int64) (*Session, error)
	ListByUserID(ctx context.Context, userID int64) ([]*Session, error)
	Revoke(ctx context.Context, id int64, at time.Time) error
	RevokeAllExcept(ctx context.Context, userID int64, keepSessionID int64, at time.Time) error
}
