package repositories

import (
	"context"
	"errors"
	"fmt"

	"flowchart_editor/backend/models"

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
) (models.User, error) {
	var u models.User
	err := r.db.QueryRow(ctx, 
		`SELECT id_user, fio, login, status, date_create
		FROM users
		WHERE id_user = $1`, 
		id).Scan(
		&u.ID,
		&u.FIO,
		&u.Login,
		&u.Status,
		&u.DateCreate,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return models.User{}, ErrNotFound
	}
	if err != nil {
		return models.User{}, fmt.Errorf("get user: %w", err)
	}
	return u, nil
}
