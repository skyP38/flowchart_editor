package repositories

import (
	"context"
	"errors"
	"fmt"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) GetByID(
	ctx context.Context,
	id int64,
) (*domains.User, error) {
	var u domains.User
	err := r.db.QueryRow(ctx,
		`SELECT id_user, login, hash_password, uname, role, created_at, is_active
		FROM users
		WHERE id_user = $1`,
		id).Scan(
		&u.ID,
		&u.Login,
		&u.PwdHash,
		&u.Uname,
		&u.Role,
		&u.CreatedAt,
		&u.IsActive,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domains.ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return &u, nil
}

func (r *UserRepository) Create(ctx context.Context, u *domains.User) error {
	err := r.db.QueryRow(ctx,
		`INSERT INTO users (login, hash_password, uname, role, created_at, is_active)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id_user`,
		u.Login, u.PwdHash, u.Uname, u.Role, u.CreatedAt, u.IsActive).Scan(&u.ID)
	if err != nil {
		return fmt.Errorf("create user: %w", err)
	}
	return nil
}

func (r *UserRepository) GetByLogin(ctx context.Context, login string) (*domains.User, error) {
	var u domains.User
	err := r.db.QueryRow(ctx,
		`SELECT id_user, login, hash_password, uname, role, created_at, is_active
		FROM users WHERE login = $1`, login).Scan(
		&u.ID, &u.Login, &u.PwdHash, &u.Uname, &u.Role, &u.CreatedAt, &u.IsActive,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domains.ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get user by login: %w", err)
	}
	return &u, nil
}
