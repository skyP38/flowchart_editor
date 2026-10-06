package services

import (
	"context"
	"strings"

	"flowchart_editor/backend/models"
	"flowchart_editor/backend/repositories"
)

type FlowchartService struct {
	repository *repositories.FlowchartRepository
}

func NewFlowchartService(
	repository *repositories.FlowchartRepository,
) *FlowchartService {
	return &FlowchartService{repository: repository}
}

func (s *FlowchartService) Create(
	ctx context.Context,
	projectID int64,
	name string,
) (models.Flowchart, error) {
	return s.repository.Create(ctx, projectID, strings.TrimSpace(name))
}

func (s *FlowchartService) Delete(
	ctx context.Context,
	flowchartID int64,
) error {
	return s.repository.Delete(ctx, flowchartID)
}
