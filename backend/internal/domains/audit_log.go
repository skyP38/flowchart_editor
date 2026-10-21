package domains

import "time"

type AuditLog struct {
	ID        int64      `json:"id"`
	UserID    *int64     `json:"userId,omitempty"`
	Login     string     `json:"login"`
	Action    string     `json:"action"`
	CreatedAt time.Time  `json:"createdAt"`
	Entity    string     `json:"entity"`
	EntityID  *int64     `json:"entityId,omitempty"`
	Status    string     `json:"status"`
}
