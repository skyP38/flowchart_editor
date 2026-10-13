package domains

import "time"

type Session struct {
	ID int64 `json:"id"`
	UserID int64 `json:"userId"`
	TokenHash string `json:"tokenHash"`
	CreatedAt time.Time `json:"createdAt"`
	ExpiresAt time.Time `json:"expiresAt"`
	RevokedAt *time.Time `json:"revokedAt,omitempty"`
}

func (s *Session) IsActive(now time.Time) bool {
	return s.RevokedAt == nil && now.Before(s.ExpiresAt)
}
