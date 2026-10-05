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

var ErrNotFound = errors.New("not found")

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
) (models.Project, error) {

	var p models.Project

	err := r.db.QueryRow(ctx, 
		`INSERT INTO projects (name_p, id_user, date_create)
		VALUES ($1, $2, NOW())
		RETURNING id_project, name_p, id_user, date_create, date_update`, 
		name, userID,).Scan(
		&p.ID,
		&p.Name,
		&p.UserID,
		&p.DateCreate,
		&p.DateUpdate,
	)
	p.Flowcharts = []models.Flowchart{}
	return p, err
}

func (r *ProjectRepository) ListByUser(
	ctx context.Context,
	userID int64,
) ([]models.Project, error) {
	rows, err := r.db.Query(ctx, 
		`SELECT id_project, name_p, id_user, date_create, date_update
		FROM projects
		WHERE id_user = $1
		ORDER BY date_update DESC NULLS LAST, date_create DESC`, 
		userID,)
	if err != nil {
		return nil, fmt.Errorf("list projects: %w", err)
	}
	defer rows.Close()
	projects := make([]models.Project, 0)
	for rows.Next() {
		var p models.Project
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
		p.Flowcharts = []models.Flowchart{}
		projects = append(projects, p)
	}
	return projects, rows.Err()
}

func (r *ProjectRepository) Update(
	ctx context.Context,
	projectID int64,
	userID int64,
	name string,
) (models.Project, error) {
	var p models.Project
	err := r.db.QueryRow(ctx,
		`UPDATE projects
		SET name_p = $1, date_update = NOW()
		WHERE id_project = $2 AND id_user = $3
		RETURNING id_project, name_p, id_user, date_create, date_update`, 
		name, projectID, userID,).Scan(
		&p.ID,
		&p.Name,
		&p.UserID,
		&p.DateCreate,
		&p.DateUpdate,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return models.Project{}, ErrNotFound
	}
	if err != nil {
		return models.Project{}, fmt.Errorf("update project: %w", err)
	}
	p.Flowcharts = []models.Flowchart{}
	return p, nil
}

func (r *ProjectRepository) Delete(
	ctx context.Context,
	projectID int64,
	userID int64,
) error {
	res, err := r.db.Exec(ctx,
		`DELETE FROM projects
		WHERE id_project = $1 AND id_user = $2`, 
		projectID, userID,)
	if err != nil {
		return fmt.Errorf("delete project: %w", err)
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

