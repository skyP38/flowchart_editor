package repositories

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"

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
		VALUES ($1, $2, '{}'::jsonb, NOW())
		RETURNING id_flowchart, name_f, data_f, created_at, updated_at`,
		name, projectID).Scan(
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
	return f, nil
}

func (r *FlowchartRepository) Delete(
	ctx context.Context,
	userID int64,
	flowchartID int64,
) error {
	result, err := r.db.Exec(ctx, `DELETE FROM flowcharts f USING projects p
	WHERE f.id_flowchart = $1 AND f.id_project = p.id_project AND p.owner_id = $2`, flowchartID, userID)
	if err != nil {
		return fmt.Errorf("delete flowchart: %w", err)
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
