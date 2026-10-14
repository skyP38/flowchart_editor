package memory

import "errors"

var ErrUserAlreadyExists = errors.New("user already exists")

var ErrNotFound = errors.New("not found")

var ErrSessionNotFound = errors.New("session not found")

var ErrSessionAlreadyExists = errors.New("session already exists")
