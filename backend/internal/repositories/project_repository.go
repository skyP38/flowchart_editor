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

type ProjectRepository struct {
	db *pgxpool.Pool
}

func NewProjectRepository(db *pgxpool.Pool) *ProjectRepository {
	return &ProjectRepository{db: db}
}

func (r *ProjectRepository) Create(
	ctx context.Context,
	userID int64,
	name string,
) (domains.Project, error) {
	var p domains.Project

	err := r.db.QueryRow(ctx,
		`INSERT INTO projects (name_p, owner_id, created_at)
		VALUES ($1, $2, NOW())
		RETURNING id_project, name_p, owner_id, created_at, updated_at`,
		name, userID).Scan(
		&p.ID,
		&p.Name,
		&p.UserID,
		&p.DateCreate,
		&p.DateUpdate,
	)
	p.Flowcharts = []domains.Flowchart{}
	return p, err
}

func (r *ProjectRepository) ListByUser(
	ctx context.Context,
	userID int64,
) ([]domains.Project, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id_project, name_p, owner_id, created_at, updated_at
		FROM projects
		WHERE owner_id = $1
		ORDER BY updated_at DESC NULLS LAST, created_at DESC`,
		userID)
	if err != nil {
		return nil, fmt.Errorf("list projects: %w", err)
	}
	defer rows.Close()
	projects := make([]domains.Project, 0)
	for rows.Next() {
		var p domains.Project
		err := rows.Scan(
			&p.ID,
			&p.Name,
			&p.UserID,
			&p.DateCreate,
			&p.DateUpdate,
		)
		if err != nil {
			return nil, fmt.Errorf("scan project: %w", err)
		}
		p.Flowcharts = []domains.Flowchart{}
		projects = append(projects, p)
	}
	return projects, rows.Err()
}

func (r *ProjectRepository) Update(
	ctx context.Context,
	projectID int64,
	userID int64,
	name string,
) (domains.Project, error) {
	var p domains.Project
	err := r.db.QueryRow(ctx,
		`UPDATE projects
		SET name_p = $1, updated_at = NOW()
		WHERE id_project = $2 AND owner_id = $3
		RETURNING id_project, name_p, owner_id, created_at, updated_at`,
		name, projectID, userID).Scan(
		&p.ID,
		&p.Name,
		&p.UserID,
		&p.DateCreate,
		&p.DateUpdate,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domains.Project{}, domains.ErrNotFound
	}
	if err != nil {
		return domains.Project{}, fmt.Errorf("update project: %w", err)
	}
	p.Flowcharts = []domains.Flowchart{}
	return p, nil
}

func (r *ProjectRepository) Delete(
	ctx context.Context,
	projectID int64,
	userID int64,
) error {
	res, err := r.db.Exec(ctx,
		`DELETE FROM projects
		WHERE id_project = $1 AND owner_id = $2`,
		projectID, userID)
	if err != nil {
		return fmt.Errorf("delete project: %w", err)
	}
	if res.RowsAffected() == 0 {
		return domains.ErrNotFound
	}
	return nil
}

func (r *ProjectRepository) GetByID(
	ctx context.Context,
	userID int64,
	projectID int64,
) (domains.Project, error) {
	var p domains.Project
	err := r.db.QueryRow(ctx,
		`SELECT id_project, name_p, owner_id, created_at, updated_at
		FROM projects
		WHERE id_project = $1 AND owner_id = $2`,
		projectID, userID).Scan(
		&p.ID,
		&p.Name,
		&p.UserID,
		&p.DateCreate,
		&p.DateUpdate,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return domains.Project{}, domains.ErrNotFound
	}
	if err != nil {
		return domains.Project{}, fmt.Errorf("get project: %w", err)
	}
	rows, err := r.db.Query(ctx,
		`SELECT id_flowchart, name_f, data_f, created_at, updated_at
		FROM flowcharts
		WHERE id_project = $1
		ORDER BY created_at DESC`, projectID)
	if err != nil {
		return domains.Project{}, fmt.Errorf("load flowcharts: %w", err)
	}
	defer rows.Close()
	p.Flowcharts = []domains.Flowchart{}
	for rows.Next() {
		var f domains.Flowchart
		var data []byte
		if err := rows.Scan(
			&f.ID,
			&f.Name,
			&data,
			&f.DateCreate,
			&f.DateUpdate,
		); err != nil {
			return domains.Project{}, fmt.Errorf("scan flowchart: %w", err)
		}
		if len(data) > 0 {
			_ = json.Unmarshal(data, &f.Data)
		}
		p.Flowcharts = append(p.Flowcharts, f)
	}
	return p, rows.Err()
}
