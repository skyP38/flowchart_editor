package auth

import "errors"

var (
	ErrLoginTaken          = errors.New("login already taken")
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
