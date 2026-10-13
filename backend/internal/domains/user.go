// Package domains содержит доменные модели и контракты хранилищ
package domains

import "time"


// User - зарегистрированный пользователь системы
type User struct {
	ID int64 `json:"id"`
	Login string `json:"login"`
	PwdHash string `json:"-"`
	Uname string `json:"uname"`
	Role string `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
	IsActive bool `json:"isActive"`
}

// Роли пользователей
const (
	RoleUser  = "user"
	RoleAdmin = "admin"
)
