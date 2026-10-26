package domains

import "time"

// RevokeAllSessions для отзыва всех сессий
const RevokeAllSessions int64 = 0

// Session - сессия пользователя по refresh-токену
// Пользователь может иметь несколько активных сессий одновременно
type Session struct {
	ID        int64      `json:"id"`
	UserID    int64      `json:"userId"`
	TokenHash string     `json:"tokenHash"`
	CreatedAt time.Time  `json:"createdAt"`
	ExpiresAt time.Time  `json:"expiresAt"`
	RevokedAt *time.Time `json:"revokedAt,omitempty"`
	DeviceName string    `json:"deviceName"`
	Location string      `json:"location"`
}

type SessionMetadata struct {
    DeviceName string
    Location   string
}

// IsActive сообщает активна ли сессия на момент now
func (s *Session) IsActive(now time.Time) bool {
	return s.RevokedAt == nil && now.Before(s.ExpiresAt)
}

// SessionStats - статистика по всем сессиям в хранилище
type SessionStats struct {
	Total   int `json:"total"`
	Active  int `json:"active"`
	Revoked int `json:"revoked"`
	Expired int `json:"expired"`
}
