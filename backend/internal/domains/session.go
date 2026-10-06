package domains

import "time"

type Session struct {
	ID        int64
	UserID    int64
	TokenHash string
	CreatedAt time.Time
	ExpiresAt time.Time
	RevokedAt *time.Time
}

func (s *Session) IsActive(now time.Time) bool {
	return s.RevokedAt == nil && now.Before(s.ExpiresAt)
}

type SessionStats struct {
	Total   int `json:"total"`
	Active  int `json:"active"`
	Revoked int `json:"revoked"`
	Expired int `json:"expired"`
}
