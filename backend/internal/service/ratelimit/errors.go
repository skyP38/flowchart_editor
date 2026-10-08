package ratelimit

import (
	"errors"
	"fmt"
)

var ErrUnknownProfile = errors.New("ratelimit: unknown profile")

// UnknownProfileError возвращается, когда ключ не соответствует
// ни одному зарегистрированному профилю
type UnknownProfileError struct {
	Key string
}

func (e *UnknownProfileError) Error() string {
	return fmt.Sprintf("ratelimit: unknown profile for key %q", e.Key)
}

// Is позволяет errors.Is(err, ErrUnknownProfile) работать
func (e *UnknownProfileError) Is(target error) bool {
	return target == ErrUnknownProfile
}
