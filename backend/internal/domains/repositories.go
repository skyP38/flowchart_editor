package domains

import (
	"context"
	"time"
)

// UserRepository описывает хранилище пользователей
type UserRepository interface {
	// Create создает нового пользователя, если логин занят - ErrUserAlreadyExists
	Create(ctx context.Context, u *User) error
	// GetByID возвращает пользователя по ID или ErrNotFound
	GetByID(ctx context.Context, id int64) (*User, error)
	// GetByLogin возвращает пользователя по логину или ErrNotFound
	GetByLogin(ctx context.Context, login string) (*User, error)
}

// SessionRepository описывает хранилище сессий
type SessionRepository interface {
	// Create создает новую сессию, если сессия с таким TokenHash уже есть - ErrSessionAlreadyExist
	Create(ctx context.Context, s *Session) error
	// GetByTokenHash возвращает сессию по хешу refresh-токена или ErrSessionNotFound
	GetByTokenHash(ctx context.Context, tokenHash string) (*Session, error)
	// GetByID возвращает сессию по ID или ErrSessionNotFound
	GetByID(ctx context.Context, id int64) (*Session, error)
	// ListByUserID возвращает все сессии пользователя, включая отозванные и истекшие
	ListByUserID(ctx context.Context, userID int64) ([]*Session, error)
	// Revoke помечает сессию отозванной в момент at
	// Если сессия уже отозвана, ничего не делает, если не найдена - ErrSessionNotFound
	Revoke(ctx context.Context, id int64, at time.Time) error
	// RevokeAllExcept отзывает все сессии пользователя, кроме keepSessionID
	// Значение domains.RevokeAllSessions означает отозвать все сессии
	RevokeAllExcept(ctx context.Context, userID int64, keepSessionID int64, at time.Time) error
}

// SessionCleaner - интерфейс для фоновой очистки просроченных сессий
// Отделен от SessionRepository, потому что нужен только janitor-процессу
type SessionCleaner interface {
	// RemoveExpired удаляет сессии, срок действия или отзыва которых истек более чем retention назад
	// Возвращает количество удаленных
	RemoveExpired(ctx context.Context, retention time.Duration) (int, error)
}
