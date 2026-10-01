package domains

import "time"

type User struct {
	ID        int64
	Login     string
	PwdHash   string
	Uname     string
	Role      string
	CreatedAt time.Time
	IsActive  bool
}

const (
	RoleUser  = "user"
	RoleAdmin = "admin"
)
