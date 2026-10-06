package repositories

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"flowchart_editor/backend/models"

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
	projectID int64,
	name string,
) (models.Flowchart, error) {
	var f models.Flowchart
	var data []byte
	err := r.db.QueryRow(ctx, 
		`INSERT INTO flowcharts (name_f, id_project, data_f, date_create)
		VALUES ($1, $2, '{}'::jsonb, NOW())
		RETURNING id_flowchart, name_f, data_f, date_create,date_update`, 
		name, projectID).Scan(
		&f.ID,
		&f.Name,
		&data,
		&f.DateCreate,
		&f.DateUpdate,
	)
	if err != nil {
		return models.Flowchart{}, fmt.Errorf("create flowchart: %w", err)
	}
	if len(data) > 0 {
		_ = json.Unmarshal(data, &f.Data)
	}
	return f, nil
}

func (r *FlowchartRepository) Delete(
	ctx context.Context,
	flowchartID int64,
) error {
	result, err := r.db.Exec(ctx, `DELETE FROM flowcharts WHERE id_flowchart = $1`, flowchartID)
	if err != nil {
		return fmt.Errorf("delete flowchart: %w", err)
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

