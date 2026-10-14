package memory

import (
	"context"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
)

// SeedAdmin создает администратора при инициализации
func SeedAdmin(
	ctx context.Context,
	users domains.UserRepository,
	login, plainPassword, pepper string,
) error {
	if login == "" || plainPassword == "" {
		return nil
	}

	if existing, err := users.GetByLogin(ctx, login); err == nil && existing != nil {
		return nil
	}

	hash, err := password.HashPassword(plainPassword, pepper)
	if err != nil {
		return err
	}

	u := &domains.User{
		Login:     login,
		PwdHash:   hash,
		Uname:     login,
		Role:      domains.RoleAdmin,
		CreatedAt: time.Now().UTC(),
		IsActive:  true,
	}
	if err := users.Create(ctx, u); err != nil {
		if err == ErrUserAlreadyExists {
			return nil
		}
		return err
	}
	return nil
}
