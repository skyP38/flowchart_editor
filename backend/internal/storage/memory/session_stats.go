// Package memory in-memory реализации хранилищ домена:
// пользователей, сессий и статистики по ним
package memory

import (
	"context"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

// Stats возвращает сводку по всем сессиям: количество активных, отозванных и истекших
// Используется GET /api/admin/stats
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
		switch {
		case v.RevokedAt != nil:
			revoked++
		case v.ExpiresAt.After(now):
			active++
		default:
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
