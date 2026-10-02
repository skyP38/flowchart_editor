package ratelimit

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

type entry struct {
	failures     []time.Time
	blockedUntil time.Time
	blockCount   int
}

type MemoryLimiter struct {
	mu              sync.RWMutex
	entries         map[string]*entry
	policies        map[string]Policy
	cleanupInterval time.Duration
	done            chan struct{}
	closeOnce       sync.Once
	wg              sync.WaitGroup
}

func NewMemoryLimiter(policies map[string]Policy, cleanupInterval time.Duration) (*MemoryLimiter, error) {
	var err error
	if len(policies) == 0 {
		err = errors.Join(err, errors.New("policies empty"))
	}
	if cleanupInterval <= 0 {
		err = errors.Join(err, errors.New("cleanup interval must be positive"))
	}
	for prefix, p := range policies {
		if prefix == "" {
			err = errors.Join(err, errors.New("empty policy prefix"))
		}
		if strings.Contains(prefix, ":") {
			err = errors.Join(err, fmt.Errorf("policy %q: prefix must not contain ':'", prefix))
		}
		if p.MaxAttempts <= 0 {
			err = errors.Join(err, fmt.Errorf("policy %q: max attempts must be positive", prefix))
		}
		if p.Window <= 0 {
			err = errors.Join(err, fmt.Errorf("policy %q: window must be positive", prefix))
		}
		if p.BlockDuration <= 0 {
			err = errors.Join(err, fmt.Errorf("policy %q: block duration must be positive", prefix))
		}
		if p.MaxBlockCount <= 0 {
			err = errors.Join(err, fmt.Errorf("policy %q: max block count must be positive", prefix))
		}
		if p.DecayWindow <= 0 {
			err = errors.Join(err, fmt.Errorf("policy %q: decy window must be positive", prefix))
		}
	}
	if err != nil {
		return nil, err
	}
	m := &MemoryLimiter{entries: make(map[string]*entry), policies: policies, cleanupInterval: cleanupInterval, done: make(chan struct{})}
	m.wg.Add(1)
	go m.cleanupLoop()
	return m, nil
}

func dedupeKeys(keys []string) []string {
	if len(keys) <= 1 {
		return keys
	}
	m := make(map[string]struct{}, len(keys))
	var ans []string

	for _, key := range keys {
		if _, ok := m[key]; !ok {
			ans = append(ans, key)
			m[key] = struct{}{}
		}
	}

	return ans
}

// проверяет разрешено ли действие по ключам
func (m *MemoryLimiter) Check(ctx context.Context, keys []string) (Decision, error) {
	var firstErr error

	now := time.Now()
	keys = dedupeKeys(keys)
	m.mu.RLock()
	defer m.mu.RUnlock()

	allowed := true
	var maxRetry time.Duration
	var blockedBy string

	for _, key := range keys {
		prefix, _, found := strings.Cut(key, ":")
		if !found {
			firstErr = &UnknownProfileError{Key: key}
			continue
		}
		if _, ok := m.policies[prefix]; !ok {
			firstErr = &UnknownProfileError{Key: key}
			continue
		}
		e, ok := m.entries[key]
		if !ok {
			continue
		}
		if now.Before(e.blockedUntil) {
			allowed = false
			retry := e.blockedUntil.Sub(now)
			if retry > maxRetry {
				maxRetry = retry
				blockedBy = key
			}
		}
	}

	return Decision{Allowed: allowed, RetryAfter: maxRetry, BlockedBy: blockedBy}, firstErr
}

// фиксирует неудачу по ключам
func (m *MemoryLimiter) RecordFailure(ctx context.Context, keys []string) error {
	var firstErr error

	keys = dedupeKeys(keys)
	now := time.Now()
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, key := range keys {
		prefix, _, found := strings.Cut(key, ":")
		if !found {
			firstErr = &UnknownProfileError{Key: key}
			continue
		}
		policy, ok := m.policies[prefix]
		if !ok {
			firstErr = &UnknownProfileError{Key: key}
			continue
		}
		e, ok := m.entries[key]
		if !ok {
			e = &entry{}
			m.entries[key] = e
		}
		if now.Before(e.blockedUntil) {
			continue
		}

		cutoff := now.Add(-policy.Window)
		pruned := e.failures[:0]
		for _, t := range e.failures {
			if t.After(cutoff) {
				pruned = append(pruned, t)
			}
		}
		e.failures = append(pruned, now)
		var count int
		if len(e.failures) >= policy.MaxAttempts {
			e.blockCount++
			count = min(e.blockCount, policy.MaxBlockCount)

			e.blockedUntil = now.Add(policy.BlockDuration * time.Duration(count))

			e.failures = nil
		}

	}
	return firstErr
}

// сбрасывает счетчики по переданным ключам
func (m *MemoryLimiter) RecordSuccess(ctx context.Context, keys []string) error {
	keys = dedupeKeys(keys)
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, key := range keys {
		delete(m.entries, key)
	}

	return nil

}

// удаляет просроченные записи, вызывается периодически
func (m *MemoryLimiter) Cleanup(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	for k, v := range m.entries {
		prefix, _, found := strings.Cut(k, ":")
		if !found {
			continue
		}
		policy, ok := m.policies[prefix]
		if !ok {
			continue
		}
		if v.blockCount > 0 && v.blockedUntil.IsZero() {
			continue
		}
		if now.After(v.blockedUntil) && (len(v.failures) == 0 || v.failures[len(v.failures)-1].Before(now.Add(-policy.Window))) && (v.blockCount == 0 || now.After(v.blockedUntil.Add(policy.DecayWindow))) {
			delete(m.entries, k)
		}

	}
	return nil
}

func (m *MemoryLimiter) cleanupLoop() {
	defer m.wg.Done()
	ticker := time.NewTicker(m.cleanupInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			_ = m.Cleanup(context.Background())
		case <-m.done:
			return
		}
	}
}

func (m *MemoryLimiter) Close() error {
	m.closeOnce.Do(func() {
		close(m.done)
	})
	m.wg.Wait()
	return nil
}
