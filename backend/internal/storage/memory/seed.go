package memory

import (
	"context"
	"errors"
	"fmt"
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

	existing, err := users.GetByLogin(ctx, login)
	if err == nil && existing != nil {
		if existing.Role == domains.RoleAdmin {
			return nil // всё хорошо, админ уже есть
		}
		return fmt.Errorf(
			"seed admin: login %q is taken by non-admin user (id=%d, role=%q)",
			login, existing.ID, existing.Role,
		)
	}
	if err != nil && !errors.Is(err, ErrNotFound) {
		return fmt.Errorf("seed admin: lookup: %w", err)
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
