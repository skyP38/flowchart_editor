// Package domains содержит доменные модели и контракты хранилищ
package domains

import "time"

// User - зарегистрированный пользователь системы
type User struct {
	ID int64
	// Login хранится в нормализованном виде
	Login     string
	PwdHash   string
	Uname     string
	Role      string
	CreatedAt time.Time
	IsActive  bool
}

// Роли пользователей
const (
	RoleUser  = "user"
	RoleAdmin = "admin"
)
