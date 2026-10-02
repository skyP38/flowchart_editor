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

type Janitor struct {
	cleaner   domains.SessionCleaner
	interval  time.Duration
	retention time.Duration
	ctx       context.Context
	cancel    context.CancelFunc
	done      chan struct{}
	closeOnce sync.Once
	wg        sync.WaitGroup
}

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

	ctx, cancel := context.WithCancel(context.Background())
	j := &Janitor{cleaner: cleaner, interval: interval, retention: retention, ctx: ctx, cancel: cancel, done: make(chan struct{})}
	j.wg.Add(1)

	go j.cleanupLoop()

	return j, nil
}

func (j *Janitor) cleanupLoop() {
	defer j.wg.Done()

	ticker := time.NewTicker(j.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			func() {
				defer func() {
					if r := recover(); r != nil {
						log.Printf("panic: %v\n%s", r, debug.Stack())
					}
				}()
				_ = j.CleanupOnce(j.ctx)
			}()
		case <-j.done:
			return
		}
	}
}

func (j *Janitor) CleanupOnce(ctx context.Context) error {
	removed, err := j.cleaner.RemoveExpired(ctx, j.retention)
	if err != nil {
		log.Printf("err %v", err)
		return err
	}
	log.Printf("removed = %d", removed)
	return nil
}

func (j *Janitor) Close() error {
	j.closeOnce.Do(func() {
		close(j.done)
		j.cancel()
	})
	j.wg.Wait()
	log.Printf("session janitor: stopped")
	return nil
}
