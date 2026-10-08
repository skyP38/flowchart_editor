// Package ratelimit реализует ограничение частоты действий по ключам
package ratelimit

import (
	"context"
	"time"
)

// Decision - результат проверки лимита
type Decision struct {
	Allowed bool
	// сколько ждать при Allow = false
	RetryAfter time.Duration
	BlockedBy  string
}

// Limiter - интерфейс ограничителя частоты действий
type Limiter interface {
	// Check проверяет разрешено ли действие по ключам
	Check(ctx context.Context, keys []string) (Decision, error)
	// RecordFailure фиксирует неудачу по ключам
	RecordFailure(ctx context.Context, keys []string) error
	// RecordSuccess сбрасывает счетчики по переданным ключам
	RecordSuccess(ctx context.Context, keys []string) error
	// Cleanup удаляет просроченные записи, вызывается периодически
	Cleanup(ctx context.Context) error
}

// Closer — интерфейс для остановки фоновых задач Limiter
type Closer interface {
	Close() error
}
