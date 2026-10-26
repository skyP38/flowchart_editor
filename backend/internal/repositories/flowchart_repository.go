package repositories

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type FlowchartRepository struct {
	db *pgxpool.Pool
}

func NewFlowchartRepository(db *pgxpool.Pool) *FlowchartRepository {
	return &FlowchartRepository{db: db}
}

func (r *FlowchartRepository) Create(
	ctx context.Context,
	userID int64,
	projectID int64,
	name string,
) (domains.Flowchart, error) {
	var f domains.Flowchart
	var data []byte
	err := r.db.QueryRow(ctx,
		`INSERT INTO flowcharts (name_f, id_project, data_f, created_at)
		SELECT $1, id_project, '{}'::jsonb, NOW()
    FROM projects
    WHERE id_project = $2 AND owner_id = $3
    RETURNING id_flowchart, name_f, data_f, created_at, updated_at`,
		name, projectID, userID).Scan(
		&f.ID,
		&f.Name,
		&data,
		&f.DateCreate,
		&f.DateUpdate,
	)
	if err != nil {
		return domains.Flowchart{}, fmt.Errorf("create flowchart: %w", err)
	}
	if len(data) > 0 {
		_ = json.Unmarshal(data, &f.Data)
	}
	_, err = r.db.Exec(
		ctx,
		`UPDATE projects
		SET updated_at = NOW()
		WHERE id_project = $1`,
		projectID,
	)
	if err != nil {
		return f, err
	}	
	return f, nil
}

func (r *FlowchartRepository) Delete(
	ctx context.Context,
	userID int64,
	flowchartID int64,
) error {
	result, err := r.db.Exec(
		ctx,
		`WITH deleted AS (
			DELETE FROM flowcharts f
			USING projects p
			WHERE f.id_flowchart = $1
			AND f.id_project = p.id_project
			AND p.owner_id = $2
			RETURNING f.id_project
		)
		UPDATE projects p
		SET updated_at = NOW()
		FROM deleted d
		WHERE p.id_project = d.id_project`,
		flowchartID,
		userID,
	)
	if err != nil {
		return fmt.Errorf("delete flowchart: %w", err)
	}
	if result.RowsAffected() == 0 {
		return domains.ErrNotFound
	}
	return nil
}

func (r *FlowchartRepository) GetContent(
	ctx context.Context, userID, projectID, flowchartID int64,
) ([]byte, error) {
	var data []byte
	err := r.db.QueryRow(ctx,
		`SELECT f.data_f
           FROM flowcharts f
           JOIN projects p ON p.id_project = f.id_project
          WHERE f.id_flowchart = $1
            AND f.id_project   = $2
            AND p.owner_id     = $3`,
		flowchartID, projectID, userID).Scan(&data)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domains.ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get flowchart content: %w", err)
	}
	if len(data) == 0 {
		data = []byte("{}")
	}
	return data, nil
}

func (r *FlowchartRepository) UpdateContent(
	ctx context.Context, userID, projectID, flowchartID int64, data []byte,
) error {
	res, err := r.db.Exec(ctx,
		`WITH updated_flowchart AS (
			UPDATE flowcharts f
			SET data_f = $1::jsonb,
			updated_at = NOW()
			FROM projects p
			WHERE f.id_flowchart = $2
			AND f.id_project = $3
			AND p.id_project = f.id_project
			AND p.owner_id = $4
			RETURNING f.id_project
		)
		UPDATE projects p
		SET updated_at = NOW()
		FROM updated_flowchart uf
		WHERE p.id_project = uf.id_project`,
		data,
		flowchartID,
		projectID,
		userID,
	)
	if err != nil {
		return fmt.Errorf("update flowchart content: %w", err)
	}
	if res.RowsAffected() == 0 {
		return domains.ErrNotFound
	}
	return nil
}
