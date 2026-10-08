// Package seed создаёт начальные данные приложения при запуске
package seed

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
)

// Admin создает администратора при инициализации
func Admin(
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
			return nil // админ уже есть
		}
		return fmt.Errorf(
			"seed admin: login %q is taken by non-admin user (id=%d, role=%q)",
			login, existing.ID, existing.Role,
		)
	}
	if err != nil && !errors.Is(err, domains.ErrNotFound) {
		return fmt.Errorf("seed admin: lookup: %w", err)
	}
	hash, err := password.HashPassword(plainPassword, pepper)
	if err != nil {
		return fmt.Errorf("seed admin: hash password: %w", err)
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
		if errors.Is(err, domains.ErrUserAlreadyExists) {
			return nil
		}
		return fmt.Errorf("seed admin: create: %w", err)
	}
	return nil
}
