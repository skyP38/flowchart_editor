package domains

import "errors"

var ErrNotFound = errors.New("not found")
var ErrUserAlreadyExists = errors.New("user already exists")
var ErrSessionNotFound = errors.New("session not found")
var ErrSessionAlreadyExists = errors.New("session already exists")
