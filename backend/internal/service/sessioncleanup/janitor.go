// Package sessioncleanup реализует фоновую очистку просроченных сессий
//
// Janitor периодически вызывает SessionCleaner.RemoveExpired и удаляет
// сессии, ставшие неактивными более retention назад
// Работает в отдельной горутине, останавливается через Close
package sessioncleanup

import (
	"context"
	"errors"
	"log"
	"runtime/debug"
	"sync"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

// Janitor - фоновая задача очистки просроченных сессий
type Janitor struct {
	cleaner domains.SessionCleaner
	// период между запусками CleanupOnce
	interval time.Duration
	// как долго держать сессии после их деактивации
	retention time.Duration
	// контекст для передачи в CleanupOnce и сигнал остановки
	ctx    context.Context
	cancel context.CancelFunc
	// гарантирует выполнение close 1 раз
	closeOnce sync.Once
	// ожидание завершения фоновой горутины
	wg sync.WaitGroup
}

// New создает и запускает Janitor
func New(cleaner domains.SessionCleaner, interval time.Duration, retention time.Duration) (*Janitor, error) {
	var err error
	if cleaner == nil {
		err = errors.Join(err, errors.New("cleaner is empty"))
	}
	if interval <= 0 {
		err = errors.Join(err, errors.New("interval must be positive"))
	}
	if retention <= 0 {
		err = errors.Join(err, errors.New("retention must be positive"))
	}
	if err != nil {
		return nil, err
	}

	// создание контекста с возможностью отмены
	ctx, cancel := context.WithCancel(context.Background())
	j := &Janitor{cleaner: cleaner, interval: interval, retention: retention, ctx: ctx, cancel: cancel}
	j.wg.Add(1)

	go j.cleanupLoop()

	return j, nil
}

// cleanupLoop периодически запускает CleanupOnce, пока не отменен ctx
func (j *Janitor) cleanupLoop() {
	defer j.wg.Done()

	ticker := time.NewTicker(j.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			func() {
				defer func() {
					// паника не должна убить горутину
					if r := recover(); r != nil {
						log.Printf("sessioncleanup: panic: %v\n%s", r, debug.Stack())
					}
				}()
				_ = j.CleanupOnce(j.ctx)
			}()
		case <-j.ctx.Done():
			return
		}
	}
}

// CleanupOnce выполняет одну итерацию очистки
func (j *Janitor) CleanupOnce(ctx context.Context) error {
	removed, err := j.cleaner.RemoveExpired(ctx, j.retention)
	if err != nil {
		log.Printf("sessioncleanup: RemoveExpired failed: %v", err)
		return err
	}
	log.Printf("sessioncleanup: removed %d expired sessions", removed)
	return nil
}

// Close останавливает фоновую очистку и дожидается завершения горутины
func (j *Janitor) Close() error {
	j.closeOnce.Do(func() {
		j.cancel()
	})
	j.wg.Wait()
	log.Printf("session janitor: stopped")
	return nil
}
