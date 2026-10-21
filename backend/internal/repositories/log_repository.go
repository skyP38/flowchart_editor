package repositories

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

type LogRepository struct {
	db *pgxpool.Pool
}

func NewLogRepository(db *pgxpool.Pool) *LogRepository {
	return &LogRepository{db: db}
}

func (r *LogRepository) CreateLog(
	ctx context.Context,
	entry *domains.AuditLog,
) error {
	var userID any
	if entry.UserID != nil {
		userID = *entry.UserID
	}

	var entityID any
	if entry.EntityID != nil {
		entityID = *entry.EntityID
	}

	status := entry.Status
	if status == "" {
		status = "Success"
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO logs (
			id_user,
			actor_login,
			action_log,
			created_at,
			entity,
			entity_id,
			status_log
		)
		VALUES ($1, $2, $3, NOW(), NULLIF($4, ''), $5, $6)
	`,
		userID,
		entry.Login,
		entry.Action,
		entry.Entity,
		entityID,
		status,
	)
	if err != nil {
		return fmt.Errorf("create audit log: %w", err)
	}

	return nil
}

func (r *LogRepository) ListLogs(
	ctx context.Context,
	limit int,
	offset int,
) ([]*domains.AuditLog, int, error) {
	var total int

	if err := r.db.QueryRow(ctx, `
		SELECT COUNT(*)::int
		FROM logs
	`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count audit logs: %w", err)
	}

	rows, err := r.db.Query(ctx, `
		SELECT
			l.id_log,
			l.id_user,
			COALESCE(NULLIF(l.actor_login, ''), u.login, 'system'),
			l.action_log,
			l.created_at,
			COALESCE(l.entity, ''),
			l.entity_id,
			l.status_log
		FROM logs l
		LEFT JOIN users u ON u.id_user = l.id_user
		ORDER BY l.created_at DESC, l.id_log DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("list audit logs: %w", err)
	}
	defer rows.Close()

	result := make([]*domains.AuditLog, 0, limit)

	for rows.Next() {
		entry := &domains.AuditLog{}
		var userID pgtype.Int8
		var entityID pgtype.Int8

		if err := rows.Scan(
			&entry.ID,
			&userID,
			&entry.Login,
			&entry.Action,
			&entry.CreatedAt,
			&entry.Entity,
			&entityID,
			&entry.Status,
		); err != nil {
			return nil, 0, fmt.Errorf("scan audit log: %w", err)
		}

		if userID.Valid {
			value := userID.Int64
			entry.UserID = &value
		}

		if entityID.Valid {
			value := entityID.Int64
			entry.EntityID = &value
		}

		result = append(result, entry)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate audit logs: %w", err)
	}

	return result, total, nil
}
