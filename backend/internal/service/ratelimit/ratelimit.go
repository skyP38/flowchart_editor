package ratelimit

import (
	"context"
	"time"
)

type Decision struct {
	Allowed bool
	// сколько ждать при Allow = false
	RetryAfter time.Duration
	BlockedBy  string
}

type Limiter interface {
	// проверяет разрешено ли действие по ключам
	Check(ctx context.Context, keys []string) (Decision, error)
	// фиксирует неудачу по ключам
	RecordFailure(ctx context.Context, keys []string) error
	// сбрасывает счетчики по переданным ключам
	RecordSuccess(ctx context.Context, keys []string) error
	// удаляет просроченные записи, вызывается периодически
	Cleanup(ctx context.Context) error
}

type Closer interface {
	Close() error
}
