package memory

import (
	"context"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

func (r *MemorySessionRepo) Stats(ctx context.Context) (domains.SessionStats, error) {
	select {
	case <-ctx.Done():
		return domains.SessionStats{}, ctx.Err()
	default:
	}
	now := time.Now().UTC()
	r.mu.RLock()
	defer r.mu.RUnlock()
	revoked, active, expired := 0, 0, 0
	for _, v := range r.byID {
		if v.RevokedAt != nil {
			revoked++
		} else if now.Before(v.ExpiresAt) {
			active++
		} else {
			expired++
		}
	}
	return domains.SessionStats{
		Total:   len(r.byID),
		Active:  active,
		Revoked: revoked,
		Expired: expired,
	}, nil
}
