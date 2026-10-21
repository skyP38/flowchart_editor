package repositories

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
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

func (r *UserRepository) ListAll(ctx context.Context) ([]*domains.User, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id_user, login, uname, role, created_at, last_login, is_active
		 FROM users ORDER BY created_at DESC, id_user DESC`)
	if err != nil {
		return nil, fmt.Errorf("list users: %w", err)
	}
	defer rows.Close()

	users := make([]*domains.User, 0)
	for rows.Next() {
		var u domains.User
		var lastLogin pgtype.Timestamptz
		if err := rows.Scan(&u.ID, &u.Login, &u.Uname, &u.Role, &u.CreatedAt, &lastLogin, &u.IsActive); err != nil {
			return nil, fmt.Errorf("scan user: %w", err)
		}
		if lastLogin.Valid {
			value := lastLogin.Time
			u.LastLogin = &value
		}
		users = append(users, &u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate users: %w", err)
	}
	return users, nil
}

func (r *UserRepository) UpdateLastLogin(ctx context.Context, userID int64, at time.Time) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET last_login = GREATEST(created_at, $2) WHERE id_user = $1`,
		userID, at)
	if err != nil {
		return fmt.Errorf("update last login: %w", err)
	}
	return nil
}

func (r *UserRepository) DeleteWithData(
    ctx context.Context,
    id int64,
) error {
    tx, err := r.db.Begin(ctx)
    if err != nil {
        return fmt.Errorf("begin delete user transaction: %w", err)
    }
    defer func() {
        _ = tx.Rollback(ctx)
    }()

    var role string
    err = tx.QueryRow(ctx,
        `SELECT role FROM users WHERE id_user = $1 FOR UPDATE`,
        id,
    ).Scan(&role)

    if errors.Is(err, pgx.ErrNoRows) {
        return domains.ErrNotFound
    }
    if err != nil {
        return fmt.Errorf("get user for deletion: %w", err)
    }

    if role == domains.RoleAdmin {
        var adminCount int

        err = tx.QueryRow(ctx,
            `SELECT COUNT(*) FROM users WHERE role = $1`,
            domains.RoleAdmin,
        ).Scan(&adminCount)

        if err != nil {
            return fmt.Errorf("count administrators: %w", err)
        }

        if adminCount <= 1 {
            return domains.ErrLastAdmin
        }
    }

    if _, err := tx.Exec(ctx,
        `DELETE FROM projects WHERE owner_id = $1`,
        id,
    ); err != nil {
        return fmt.Errorf("delete user projects: %w", err)
    }

    result, err := tx.Exec(ctx,
        `DELETE FROM users WHERE id_user = $1`,
        id,
    )
    if err != nil {
        return fmt.Errorf("delete user: %w", err)
    }

    if result.RowsAffected() == 0 {
        return domains.ErrNotFound
    }

    if err := tx.Commit(ctx); err != nil {
        return fmt.Errorf("delete user: %w", err)
    }

    return nil
}
