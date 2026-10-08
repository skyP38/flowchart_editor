// Package auth реализует регистрацию, аутентификацию, выдачу токенов и управление сессиями пользователей
package auth

import (
	"errors"
	"sort"
	"strings"
)

var (
	ErrLoginTaken          = errors.New("login already taken")
	ErrInvalidCredentials  = errors.New("invalid login or password")
	ErrInvalidRefreshToken = errors.New("invalid refresh token")
	ErrSessionNotFound     = errors.New("session not found")
)

// ValidationError - ошибка валидации одного поля
type ValidationError struct {
	Field   string
	Message string
}

// Error реализует интерфейс error
func (e *ValidationError) Error() string {
	return e.Field + ": " + e.Message
}

// ValidationErrors - набор ошибок полей, чтобы вернуть их одним ответом
type ValidationErrors struct {
	Fields map[string]string
}

func NewValidationErrors() *ValidationErrors {
	return &ValidationErrors{Fields: make(map[string]string)}
}

// Add добавляет ошибку поля
func (e *ValidationErrors) Add(field, message string) {
	e.Fields[field] = message
}

// HasAny сообщает, есть ли хоть одна ошибка
func (e *ValidationErrors) HasAny() bool {
	return len(e.Fields) > 0
}

// Error реализует интерфейс error, собирая все поля в одну строку в отсортированном порядке
func (e *ValidationErrors) Error() string {
	if len(e.Fields) == 0 {
		return "validation failed"
	}
	keys := make([]string, 0, len(e.Fields))
	for k := range e.Fields {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, k+": "+e.Fields[k])
	}
	return strings.Join(parts, "; ")
}
