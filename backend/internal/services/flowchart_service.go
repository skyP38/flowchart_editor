package services

import (
	"context"
	"strings"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/repositories"
	//"github.com/skyP38/flowchart_editor/backend/internal/models"
	//"github.com/skyP38/flowchart_editor/backend/internal/repositories"
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
	userID int64,
	projectID int64,
	name string,
) (domains.Flowchart, error) {
	return s.repository.Create(ctx, userID, projectID, strings.TrimSpace(name))
}

func (s *FlowchartService) Delete(
	ctx context.Context,
	userID int64,
	flowchartID int64,
) error {
	return s.repository.Delete(ctx, userID, flowchartID)
}
