// Package ratelimit реализует ограничение частоты действий по ключам
//
// Модель использования:
//
//  1. Перед действием клиент вызывает Check(ctx, keys).
//     Если Allowed == false, действие нужно отклонить и подождать
//     RetryAfter.
//
//  2. На неудаче клиент вызывает RecordFailure(ctx, keys).
//     При превышении MaxAttempts в окне Window ключ блокируется
//     на BlockDuration, с эскалацией при повторных нарушениях.
//
//  3. На успехе клиент вызывает RecordSuccess(ctx, keys),
//     сбрасывая счётчики по ключам.
//
//  4. Cleanup периодически удаляет просроченные записи; в MemoryLimiter
//     он запускается автоматически в фоновой горутине и останавливается
//     через Close.
//
// Ключи имеют вид "<prefix>:<value>", где prefix соответствует
// зарегистрированному профилю (Policy). Один вызов может принимать
// несколько ключей одновременно - блокировка срабатывает, если
// заблокирован хотя бы один
package ratelimit

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

// entry - состояние одного ключа
type entry struct {
	// список неудачных попыток в окне
	failures []time.Time
	// до какого мемента ключ заблокирован
	blockedUntil time.Time
	// сколько раз ключ блокировался
	blockCount int
}

// MemoryLimiter - потокобезопасный in-memory ограничитель частоты
// Хранит состояния в мапе entries
// Регулярно запускает Cleanup в фоновой горутине
type MemoryLimiter struct {
	mu sync.RWMutex
	// ключ - <prefix>
	entries         map[string]*entry
	policies        map[string]Policy
	cleanupInterval time.Duration
	// сигнал для остановки фоновой горутины cleanupLoop
	done chan struct{}
	// гарантия что close(done) выполнится 1 раз
	closeOnce sync.Once
	// ждем завершения фоновой горутины
	wg sync.WaitGroup
}

// NewMemoryLimiter создаёт ограничитель и запускает фоновую очистку
// Возвращает ошибку, если policies пусты, cleanupInterval <= 0
// или хотя бы один Policy содержит некорректные значения
// (неположительные MaxAttempts, Window, BlockDuration, MaxBlockCount, DecayWindow)
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

// dedupeKeys удаляет дубликаты из слайса ключей, сохраняя порядок первого вхождения
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

// Check проверяет разрешено ли действие по ключам
// Возвращает Decision:
//   - Allowed=false, если хотя бы один ключ заблокирован;
//   - RetryAfter - максимальное время до разблокировки среди ключей;
//   - BlockedBy - ключ с наибольшим RetryAfter (для логирования).
func (m *MemoryLimiter) Check(_ context.Context, keys []string) (Decision, error) {
	var firstErr error

	now := time.Now()
	keys = dedupeKeys(keys)
	m.mu.RLock()
	defer m.mu.RUnlock()

	allowed := true
	var maxRetry time.Duration
	var blockedBy string

	for _, key := range keys {
		// разделяет ключ на key:value(login:alice) на 2 поля
		prefix, _, found := strings.Cut(key, ":")
		if !found {
			// сохраняет первую ошибку
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
				// берется максимальное время блокировки среди ключей
				maxRetry = retry
				blockedBy = key
			}
		}
	}

	return Decision{Allowed: allowed, RetryAfter: maxRetry, BlockedBy: blockedBy}, firstErr
}

// RecordFailure фиксирует неудачу по ключам
// Для каждого ключа:
//   - удаляет из истории неудачи старше Window (скользящее окно);
//   - добавляет текущую неудачу;
//   - если неудач в окне стало >= MaxAttempts, устанавливает блокировку
//     длительностью BlockDuration * min(blockCount, MaxBlockCount).
func (m *MemoryLimiter) RecordFailure(_ context.Context, keys []string) error {
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

		// если ключ уже заблокирован новые неудачи не учитываются
		if now.Before(e.blockedUntil) {
			continue
		}

		// скользящее окно: остаются только неудачи внутри Window
		cutoff := now.Add(-policy.Window)
		pruned := e.failures[:0]
		for _, t := range e.failures {
			if t.After(cutoff) {
				pruned = append(pruned, t)
			}
		}
		//nolint:gocritic
		e.failures = append(pruned, now)
		var count int
		if len(e.failures) >= policy.MaxAttempts {
			e.blockCount++
			count = min(e.blockCount, policy.MaxBlockCount)

			e.blockedUntil = now.Add(policy.BlockDuration * time.Duration(count))

			// после блокировки история не нужна
			e.failures = nil
		}
	}
	return firstErr
}

// RecordSuccess сбрасывает счетчики по переданным ключам
// Удаляет записи целиком: после успеха история неудач и счетчик блокировок забываются
func (m *MemoryLimiter) RecordSuccess(_ context.Context, keys []string) error {
	keys = dedupeKeys(keys)
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, key := range keys {
		delete(m.entries, key)
	}

	return nil
}

// Cleanup удаляет просроченные записи, вызывается периодически
// Запись удаляется, если одновременно:
//
//   - блокировка истекла (now > blockedUntil);
//   - список неудач пуст или последняя неудача старше Window;
//   - счетчик блокировок равен нулю или после окончания блокировки прошло больше DecayWindow.
func (m *MemoryLimiter) Cleanup(_ context.Context) error {
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
		// удаляем запись если после блокировки прошло достаточно времени или попыток нет(или они старые) или блокировок нет(или они забыты)
		if now.After(v.blockedUntil) && (len(v.failures) == 0 || v.failures[len(v.failures)-1].Before(now.Add(-policy.Window))) && (v.blockCount == 0 || now.After(v.blockedUntil.Add(policy.DecayWindow))) {
			delete(m.entries, k)
		}
	}
	return nil
}

// cleanupLoop периодически запускает Cleanup, пока не закрыт done
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

// Close останавливает фоновую очистку и дожидается завершения горутины
func (m *MemoryLimiter) Close() error {
	m.closeOnce.Do(func() {
		close(m.done)
	})
	m.wg.Wait()
	return nil
}
