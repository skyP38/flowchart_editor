package auth

import (
	"errors"
	"sort"
	"strings"
)

var (
	ErrLoginTaken          = errors.New("login already taken")
	ErrLoginReserved       = errors.New("login is reserved")
	ErrInvalidCredentials  = errors.New("invalid login or password")
	ErrInvalidRefreshToken = errors.New("invalid refresh token")
	ErrSessionNotFound     = errors.New("session not found")
)

type ValidationError struct {
	Field   string
	Message string
}

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

func (e *ValidationErrors) Add(field, message string) {
	e.Fields[field] = message
}

func (e *ValidationErrors) HasAny() bool {
	return len(e.Fields) > 0
}

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
