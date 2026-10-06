package repositories

import (
	"context"
	"fmt"

	"flowchart_editor/backend/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SessionRepository struct {
	db *pgxpool.Pool
}

func NewSessionRepository(db *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{db: db}
}

func (r *SessionRepository) ListByUser(
	ctx context.Context,
	userID int64,
) ([]models.Session, error) {
	rows, err := r.db.Query(ctx,
		`SELECT	id_sessions, id_user, date_create, is_active, closing_date
		FROM sessions
		WHERE id_user = $1
		ORDER BY date_create DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("list sessions: %w", err)
	}
	defer rows.Close()
	sessions := make([]models.Session, 0)
	for rows.Next() {
		var s models.Session
		if err := rows.Scan(
			&s.ID,
			&s.UserID,
			&s.DateCreate,
			&s.IsActive,
			&s.ClosingDate,
		); err != nil {
			return nil, fmt.Errorf("scan session: %w", err)
		}
		sessions = append(sessions, s)
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
		SET is_active = false, closing_date = NOW()
		WHERE id_sessions = $1 AND id_user = $2 AND is_active = true`, 
		sessionID, userID)
	if err != nil {
		return fmt.Errorf("close session: %w", err)
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}

	return nil
}
