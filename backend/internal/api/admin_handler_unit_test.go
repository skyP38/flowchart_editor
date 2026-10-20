// internal/api/admin_handler_unit_test.go
package api

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

type failingStatsProvider struct{ err error }

func (f *failingStatsProvider) Stats(_ context.Context) (domains.SessionStats, error) {
	return domains.SessionStats{}, f.err
}

func TestAdminHandler_StatsInternalError(t *testing.T) {
	h := NewAdminHandler(&failingStatsProvider{err: errors.New("boom")})
	req := httptest.NewRequest(http.MethodGet, "/api/admin/stats", nil)
	rec := httptest.NewRecorder()
	h.Stats(rec, req)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status %d, want 500", rec.Code)
	}
}
