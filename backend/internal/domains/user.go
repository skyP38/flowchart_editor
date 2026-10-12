package domains

import "time"

type User struct {
	ID int64 `json:"id"`
	Login string `json:"login"`
	PwdHash string `json:"-"`
	Uname string `json:"uname"`
	Role string `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
	IsActive bool `json:"isActive"`
}

const (
	RoleUser  = "user"
	RoleAdmin = "admin"
)
