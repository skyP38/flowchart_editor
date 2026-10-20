package repositories

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type SessionRepository struct {
	db *pgxpool.Pool
}

func NewSessionRepository(db *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{db: db}
}

func (r *SessionRepository) AddSession(
	ctx context.Context,
	userID int64,
	expiresAt time.Time,
	tokenHash string,
) (int64, error) {
	var id int64
	err := r.db.QueryRow(ctx,
		`INSERT INTO sessions (id_user, created_at, expires_at, revoked_at, token_hash)
		VALUES ($1, NOW(), $2, NULL, $3)
		RETURNING id_sessions;`, userID, expiresAt, tokenHash).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("add session: %w", err)
	}
	return id, nil
}

func (r *SessionRepository) ListByUserID(
	ctx context.Context,
	userID int64,
) ([]*domains.Session, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id_sessions, id_user, token_hash, created_at, expires_at, revoked_at
		FROM sessions
		WHERE id_user = $1
		ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("list sessions: %w", err)
	}
	defer rows.Close()

	var sessions []*domains.Session
	for rows.Next() {
		var s domains.Session
		if err := rows.Scan(
			&s.ID,
			&s.UserID,
			&s.TokenHash,
			&s.CreatedAt,
			&s.ExpiresAt,
			&s.RevokedAt,
		); err != nil {
			return nil, fmt.Errorf("scan session: %w", err)
		}
		sessions = append(sessions, &s)
	}
	return sessions, rows.Err()
}

func (r *SessionRepository) Close(
	ctx context.Context,
	sessionID int64,
	userID int64,
) error {
	result, err := r.db.Exec(ctx,
		`UPDATE sessions
		SET revoked_at = NOW()
		WHERE id_sessions = $1 AND id_user = $2 AND revoked_at IS NULL`,
		sessionID, userID)
	if err != nil {
		return fmt.Errorf("close session: %w", err)
	}
	if result.RowsAffected() == 0 {
		return domains.ErrNotFound
	}
	return nil
}

func (r *SessionRepository) Create(ctx context.Context, s *domains.Session) error {
	err := r.db.QueryRow(ctx,
		`INSERT INTO sessions (id_user, created_at, expires_at, revoked_at, token_hash)
		VALUES ($1, $2, $3, NULL, $4)
		RETURNING id_sessions`,
		s.UserID, s.CreatedAt, s.ExpiresAt, s.TokenHash).Scan(&s.ID)
	if err != nil {
		return fmt.Errorf("create session: %w", err)
	}
	return nil
}

func (r *SessionRepository) GetByTokenHash(ctx context.Context, hash string) (*domains.Session, error) {
	var s domains.Session
	err := r.db.QueryRow(ctx,
		`SELECT id_sessions, id_user, token_hash, created_at, expires_at, revoked_at
		FROM sessions WHERE token_hash = $1`, hash).Scan(
		&s.ID, &s.UserID, &s.TokenHash, &s.CreatedAt, &s.ExpiresAt, &s.RevokedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domains.ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get session by hash: %w", err)
	}
	return &s, nil
}

func (r *SessionRepository) GetByID(ctx context.Context, id int64) (*domains.Session, error) {
	var s domains.Session
	err := r.db.QueryRow(ctx,
		`SELECT id_sessions, id_user, token_hash, created_at, expires_at, revoked_at
		FROM sessions WHERE id_sessions = $1`, id).Scan(
		&s.ID, &s.UserID, &s.TokenHash, &s.CreatedAt, &s.ExpiresAt, &s.RevokedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domains.ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get session: %w", err)
	}
	return &s, nil
}

func (r *SessionRepository) Revoke(ctx context.Context, id int64, now time.Time) error {
	var idOut int64
	err := r.db.QueryRow(ctx,
		`UPDATE sessions SET revoked_at = COALESCE(revoked_at, $1)
		WHERE id_sessions = $2 RETURNING id_sessions`,
		now, id).Scan(&idOut)
	if errors.Is(err, pgx.ErrNoRows) {
		return domains.ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("revoke session: %w", err)
	}
	return nil
}

func (r *SessionRepository) RevokeAllExcept(ctx context.Context, userID, keepID int64, now time.Time) error {
	_, err := r.db.Exec(ctx,
		`UPDATE sessions SET revoked_at = $1
		WHERE id_user = $2 AND id_sessions != $3 AND revoked_at IS NULL`,
		now, userID, keepID)
	if err != nil {
		return fmt.Errorf("revoke all except: %w", err)
	}
	return nil
}

func (r *SessionRepository) RemoveExpired(ctx context.Context, retention time.Duration) (int, error) {
	cutoff := time.Now().UTC().Add(-retention)
	res, err := r.db.Exec(ctx,
		`DELETE FROM sessions
         WHERE (expires_at < $1) OR (revoked_at IS NOT NULL AND revoked_at < $1)`,
		cutoff)
	if err != nil {
		return 0, err
	}
	return int(res.RowsAffected()), nil
}

func (r *SessionRepository) Stats(ctx context.Context) (domains.SessionStats, error) {
	var stats domains.SessionStats
	err := r.db.QueryRow(ctx, `
		SELECT
			COUNT(*)::int,
			COUNT(*) FILTER (WHERE revoked_at IS NULL AND expires_at > NOW())::int,
			COUNT(*) FILTER (WHERE revoked_at IS NOT NULL)::int,
			COUNT(*) FILTER (WHERE revoked_at IS NULL AND expires_at <= NOW())::int
		FROM sessions`).Scan(&stats.Total, &stats.Active, &stats.Revoked, &stats.Expired)
	if err != nil {
		return domains.SessionStats{}, fmt.Errorf("session stats: %w", err)
	}
	return stats, nil
}
