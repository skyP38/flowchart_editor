package ratelimit

import (
	"errors"
	"fmt"
)

var ErrUnknownProfile = errors.New("ratelimit: unknown profile")

type UnknownProfileError struct {
	Key string
}

func (e *UnknownProfileError) Error() string {
	return fmt.Sprintf("ratelimit: unknown profile for key %q", e.Key)
}

func (e *UnknownProfileError) Is(target error) bool {
	return target == ErrUnknownProfile
}
