package ratelimit

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"
)

type tc struct {
	name     string
	policies func() map[string]Policy
	interval time.Duration
}

func TestNewMemoryLimiter_InvalidInput(t *testing.T) {
	cases := []tc{
		{"empty policies", func() map[string]Policy { return nil }, time.Second},
		{"zero cleanup interval", func() map[string]Policy { return map[string]Policy{"login": defaultPolicy()} }, 0},
		{"negative cleanup interval", func() map[string]Policy { return map[string]Policy{"login": defaultPolicy()} }, -time.Second},
		{"empty prefix", func() map[string]Policy { return map[string]Policy{"": defaultPolicy()} }, -time.Second},
		{"prefix with colon", func() map[string]Policy { return map[string]Policy{"log:in": defaultPolicy()} }, time.Second},
		{"zero max attempts", func() map[string]Policy {
			p := defaultPolicy()
			p.MaxAttempts = 0
			return map[string]Policy{"login": p}
		}, time.Second},
		{"negative max attempts", func() map[string]Policy {
			p := defaultPolicy()
			p.MaxAttempts = -1
			return map[string]Policy{"login": p}
		}, time.Second},
		{"zero window", func() map[string]Policy {
			p := defaultPolicy()
			p.Window = 0
			return map[string]Policy{"login": p}
		}, time.Second},
		{"negative window", func() map[string]Policy {
			p := defaultPolicy()
			p.Window = -time.Second
			return map[string]Policy{"login": p}
		}, time.Second},
		{"zero block duration", func() map[string]Policy {
			p := defaultPolicy()
			p.BlockDuration = 0
			return map[string]Policy{"login": p}
		}, time.Second},
		{"zero max block count", func() map[string]Policy {
			p := defaultPolicy()
			p.MaxBlockCount = 0
			return map[string]Policy{"login": p}
		}, time.Second},
		{"negative max block count", func() map[string]Policy {
			p := defaultPolicy()
			p.MaxBlockCount = -1
			return map[string]Policy{"login": p}
		}, time.Second},
		{"zero decay window", func() map[string]Policy {
			p := defaultPolicy()
			p.DecayWindow = 0
			return map[string]Policy{"login": p}
		}, time.Second},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			ml, err := NewMemoryLimiter(tt.policies(), tt.interval)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
			if ml != nil {
				t.Fatalf("expected nil limiter, got %v", ml)
			}
		})
	}

}

func defaultPolicy() Policy {
	return Policy{
		MaxAttempts:   3,
		Window:        100 * time.Millisecond,
		BlockDuration: 200 * time.Millisecond,
		MaxBlockCount: 2,
		DecayWindow:   500 * time.Millisecond,
	}
}

func newTestLimiter(t *testing.T) *MemoryLimiter {
	t.Helper()
	return newTestLimiterWithCleanup(t, time.Hour)
}

func newTestLimiterWithCleanup(t *testing.T, interval time.Duration) *MemoryLimiter {
	t.Helper()
	m, err := NewMemoryLimiter(map[string]Policy{"login": defaultPolicy()}, interval)
	if err != nil {
		t.Fatalf("new limiter: %v", err)
	}
	t.Cleanup(func() { _ = m.Close() })
	return m
}

func TestDedupeKeys(t *testing.T) {
	cases := []struct {
		name string
		in   []string
		want []string
	}{
		{"nil", nil, nil},
		{"empty", []string{}, []string{}},
		{"single", []string{"a"}, []string{"a"}},
		{"all unique", []string{"a", "b", "c"}, []string{"a", "b", "c"}},
		{"with duplicates", []string{"a", "b", "a", "c", "b"}, []string{"a", "b", "c"}},
		{"all same", []string{"x", "x", "x"}, []string{"x"}},
	}

	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			got := dedupeKeys(tt.in)
			if !slices.Equal(got, tt.want) {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCheck(t *testing.T) {
	t.Run("no state", func(t *testing.T) {
		m := newTestLimiter(t)
		d, err := m.Check(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !d.Allowed {
			t.Fatalf("want allowed, got blocked")
		}
		if d.RetryAfter != 0 {
			t.Fatalf("want RetryAfter 0, got %v", d.RetryAfter)
		}
		if d.BlockedBy != "" {
			t.Fatalf("want empty BlockedBy, got %q", d.BlockedBy)
		}
	})

	t.Run("empty keys ", func(t *testing.T) {
		m := newTestLimiter(t)
		d, err := m.Check(context.Background(), nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !d.Allowed {
			t.Fatalf("want allowed, got blocked")
		}
	})

	t.Run("not blocked", func(t *testing.T) {
		m := newTestLimiter(t)
		setBlocked(t, m, "login:alice", -time.Second)
		d, err := m.Check(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !d.Allowed {
			t.Fatalf("want allowed, got blocked")
		}
		if d.RetryAfter != 0 {
			t.Fatalf("want RetryAfter 0, got %v", d.RetryAfter)
		}
	})

	t.Run("blocked", func(t *testing.T) {
		m := newTestLimiter(t)
		setBlocked(t, m, "login:alice", 50*time.Millisecond)
		d, err := m.Check(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if d.Allowed {
			t.Fatalf("want blocked, got allowed")
		}
		if d.RetryAfter <= 0 || d.RetryAfter > 50*time.Millisecond {
			t.Fatalf("RetryAfter out of range: %v", d.RetryAfter)
		}
		if d.BlockedBy != "login:alice" {
			t.Fatalf("want BlockedBy login:alice, got %q", d.BlockedBy)
		}
	})
	t.Run("unknown no colon", func(t *testing.T) {
		m := newTestLimiter(t)
		setBlocked(t, m, "login:alice", 50*time.Millisecond)
		d, err := m.Check(context.Background(), []string{"login"})
		if !errors.Is(err, ErrUnknownProfile) {
			t.Fatalf("want ErrUnknownProfile, got %v", err)
		}
		if !d.Allowed {
			t.Fatalf("want allowed, got blocked")
		}
	})
	t.Run("unknown prefix", func(t *testing.T) {
		m := newTestLimiter(t)
		setBlocked(t, m, "login:alice", 50*time.Millisecond)
		d, err := m.Check(context.Background(), []string{"foo:alice"})
		if !errors.Is(err, ErrUnknownProfile) {
			t.Fatalf("want ErrUnknownProfile, got %v", err)
		}
		if !d.Allowed {
			t.Fatalf("want allowed, got blocked")
		}
	})
	t.Run("mixed unknown and blocked", func(t *testing.T) {
		m := newTestLimiter(t)
		setBlocked(t, m, "login:alice", 50*time.Millisecond)
		d, err := m.Check(context.Background(), []string{"foo:bob", "login:alice"})
		if !errors.Is(err, ErrUnknownProfile) {
			t.Fatalf("want ErrUnknownProfile, got %v", err)
		}
		if d.Allowed {
			t.Fatalf("want blocked, got allowed")
		}
		if d.BlockedBy != "login:alice" {
			t.Fatalf("want BlockedBy login:alice, got %q", d.BlockedBy)
		}
	})
	t.Run("multiple blocked different retry", func(t *testing.T) {
		m := newTestLimiter(t)
		setBlocked(t, m, "login:alice", 30*time.Millisecond)
		setBlocked(t, m, "login:bob", 80*time.Millisecond)
		d, err := m.Check(context.Background(), []string{"login:alice", "login:bob"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if d.Allowed {
			t.Fatalf("want blocked, got allowed")
		}
		if d.BlockedBy != "login:bob" {
			t.Fatalf("want BlockedBy login:bob, got %q", d.BlockedBy)
		}
		if d.RetryAfter <= 30*time.Millisecond || d.RetryAfter > 80*time.Millisecond {
			t.Fatalf("RetryAfter out of range: %v", d.RetryAfter)
		}
	})

	t.Run("multiple blocked equal retry", func(t *testing.T) {
		m := newTestLimiter(t)
		target := time.Now().Add(50 * time.Millisecond)
		m.mu.Lock()
		m.entries["login:alice"] = &entry{blockedUntil: target}
		m.entries["login:bob"] = &entry{blockedUntil: target}
		m.mu.Unlock()

		d, err := m.Check(context.Background(), []string{"login:alice", "login:bob"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if d.Allowed {
			t.Fatalf("want blocked, got allowed")
		}
		if d.BlockedBy != "login:alice" {
			t.Fatalf("want BlockedBy login:alice (first), got %q", d.BlockedBy)
		}
	})

}

func setBlocked(t *testing.T, m *MemoryLimiter, key string, retryAfter time.Duration) {
	t.Helper()
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.entries[key]
	if !ok {
		e = &entry{}
		m.entries[key] = e
	}
	e.blockedUntil = time.Now().Add(retryAfter)
}

func TestRecordFailure(t *testing.T) {
	t.Run("single failure", func(t *testing.T) {
		m := newTestLimiter(t)
		err := m.RecordFailure(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		e := getEntry(t, m, "login:alice")
		if len(e.failures) != 1 {
			t.Fatalf("want 1 failure, got %d", len(e.failures))
		}
		if e.blockCount != 0 {
			t.Fatalf("want blockCount 0, got %d", e.blockCount)
		}
		if !e.blockedUntil.IsZero() {
			t.Fatalf("want zero blockedUntil, got %v", e.blockedUntil)
		}
	})

	t.Run("threshold reached", func(t *testing.T) {
		m := newTestLimiter(t)
		for i := range 3 {
			if err := m.RecordFailure(context.Background(), []string{"login:alice"}); err != nil {
				t.Fatalf("failure %d: %v", i, err)
			}
		}
		e := getEntry(t, m, "login:alice")
		if e.blockCount != 1 {
			t.Fatalf("want blockCount 1, got %d", e.blockCount)
		}
		if len(e.failures) != 0 {
			t.Fatalf("want failures cleared, got %d", len(e.failures))
		}
		checkBlockDuration(t, e, defaultPolicy().BlockDuration, 1)
	})

	t.Run("below threshold not blocked", func(t *testing.T) {
		m := newTestLimiter(t)
		for _ = range 2 {
			_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		}
		d, err := m.Check(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("check: %v", err)
		}
		if !d.Allowed {
			t.Fatalf("want allowed, got blocked")
		}
	})

	t.Run("at threshold blocked", func(t *testing.T) {
		m := newTestLimiter(t)
		for _ = range 3 {
			_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		}
		d, err := m.Check(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("check: %v", err)
		}
		if d.Allowed {
			t.Fatalf("want blocked, got allowed")
		}
	})

	t.Run("failure during block is noop", func(t *testing.T) {
		m := newTestLimiter(t)
		for _ = range 3 {
			_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		}
		before := getEntry(t, m, "login:alice")
		beforeUntil := before.blockedUntil
		beforeCount := before.blockCount

		for _ = range 3 {
			_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		}

		after := getEntry(t, m, "login:alice")
		if !after.blockedUntil.Equal(beforeUntil) {
			t.Fatalf("blockedUntil changed: was %v, now %v", beforeUntil, after.blockedUntil)
		}
		if after.blockCount != beforeCount {
			t.Fatalf("blockCount changed: was %d, now %d", beforeCount, after.blockCount)
		}
		if len(after.failures) != 0 {
			t.Fatalf("failures not empty: %d", len(after.failures))
		}
	})

	t.Run("window prunes old failures", func(t *testing.T) {
		m := newTestLimiter(t)
		now := time.Now()
		m.mu.Lock()
		m.entries["login:alice"] = &entry{
			failures: []time.Time{
				now.Add(-2 * defaultPolicy().Window),
				now.Add(-defaultPolicy().Window / 2),
			},
		}
		m.mu.Unlock()

		if err := m.RecordFailure(context.Background(), []string{"login:alice"}); err != nil {
			t.Fatalf("record: %v", err)
		}
		e := getEntry(t, m, "login:alice")
		if len(e.failures) != 2 {
			t.Fatalf("want 2 failures after prune+append, got %d", len(e.failures))
		}
	})

	t.Run("escalation increases duration", func(t *testing.T) {
		m := newTestLimiter(t)

		for _ = range 3 {
			_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		}
		e := getEntry(t, m, "login:alice")
		if e.blockCount != 1 {
			t.Fatalf("first block: want blockCount 1, got %d", e.blockCount)
		}

		setBlocked(t, m, "login:alice", -time.Millisecond)

		for _ = range 3 {
			_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		}
		e = getEntry(t, m, "login:alice")
		if e.blockCount != 2 {
			t.Fatalf("second block: want blockCount 2, got %d", e.blockCount)
		}
		checkBlockDuration(t, e, defaultPolicy().BlockDuration, 2)
	})

	t.Run("escalation capped by MaxBlockCount", func(t *testing.T) {
		m := newTestLimiter(t)

		for round := 1; round <= 3; round++ {
			for _ = range 3 {
				_ = m.RecordFailure(context.Background(), []string{"login:alice"})
			}
			e := getEntry(t, m, "login:alice")
			if e.blockCount != round {
				t.Fatalf("round %d: want blockCount %d, got %d", round, round, e.blockCount)
			}
			wantCount := round
			if wantCount > defaultPolicy().MaxBlockCount {
				wantCount = defaultPolicy().MaxBlockCount
			}
			checkBlockDuration(t, e, defaultPolicy().BlockDuration, wantCount)
			setBlocked(t, m, "login:alice", -time.Millisecond)
		}
	})

	t.Run("unknown key is reported", func(t *testing.T) {
		m := newTestLimiter(t)
		err := m.RecordFailure(context.Background(), []string{"foo:alice"})
		if !errors.Is(err, ErrUnknownProfile) {
			t.Fatalf("want ErrUnknownProfile, got %v", err)
		}
		m.mu.RLock()
		_, exists := m.entries["foo:alice"]
		m.mu.RUnlock()
		if exists {
			t.Fatalf("entry for unknown key was created")
		}
	})

	t.Run("mixed unknown and valid", func(t *testing.T) {
		m := newTestLimiter(t)
		err := m.RecordFailure(context.Background(), []string{"foo:bob", "login:alice"})
		if !errors.Is(err, ErrUnknownProfile) {
			t.Fatalf("want ErrUnknownProfile, got %v", err)
		}
		e := getEntry(t, m, "login:alice")
		if len(e.failures) != 1 {
			t.Fatalf("valid key was not processed: len=%d", len(e.failures))
		}
	})

	t.Run("dedupe prevents double count", func(t *testing.T) {
		m := newTestLimiter(t)
		err := m.RecordFailure(context.Background(), []string{"login:alice", "login:alice"})
		if err != nil {
			t.Fatalf("record: %v", err)
		}
		e := getEntry(t, m, "login:alice")
		if len(e.failures) != 1 {
			t.Fatalf("want 1 failure, got %d", len(e.failures))
		}
	})
}
func getEntry(t *testing.T, m *MemoryLimiter, key string) *entry {
	t.Helper()
	m.mu.RLock()
	defer m.mu.RUnlock()
	e, ok := m.entries[key]
	if !ok {
		t.Fatalf("entry %q not found", key)
	}
	return e
}

func checkBlockDuration(t *testing.T, e *entry, base time.Duration, count int) {
	t.Helper()
	want := base * time.Duration(count)
	got := time.Until(e.blockedUntil)
	if got <= 0 {
		t.Fatalf("blockedUntil not in the future: %v", got)
	}
	tolerance := want / 4
	diff := got - want
	if diff < 0 {
		diff = -diff
	}
	if diff > tolerance {
		t.Fatalf("block duration: got %v, want ~%v", got, want)
	}
}

func TestRecordSuccess(t *testing.T) {
	t.Run("removes entry", func(t *testing.T) {
		m := newTestLimiter(t)
		_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		requireEntry(t, m, "login:alice")

		err := m.RecordSuccess(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		requireNoEntry(t, m, "login:alice")
	})

	t.Run("no-op for missing key", func(t *testing.T) {
		m := newTestLimiter(t)
		err := m.RecordSuccess(context.Background(), []string{"login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		requireNoEntry(t, m, "login:alice")
	})

	t.Run("multiple keys", func(t *testing.T) {
		m := newTestLimiter(t)
		_ = m.RecordFailure(context.Background(), []string{"login:alice"})
		_ = m.RecordFailure(context.Background(), []string{"login:bob"})

		err := m.RecordSuccess(context.Background(), []string{"login:alice", "login:bob"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		requireNoEntry(t, m, "login:alice")
		requireNoEntry(t, m, "login:bob")
	})

	t.Run("dedupe safe", func(t *testing.T) {
		m := newTestLimiter(t)
		_ = m.RecordFailure(context.Background(), []string{"login:alice"})

		err := m.RecordSuccess(context.Background(), []string{"login:alice", "login:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		requireNoEntry(t, m, "login:alice")
	})

	t.Run("unknown prefix is noop", func(t *testing.T) {
		m := newTestLimiter(t)
		m.mu.Lock()
		m.entries["foo:alice"] = &entry{}
		m.mu.Unlock()

		err := m.RecordSuccess(context.Background(), []string{"foo:alice"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		requireNoEntry(t, m, "foo:alice")
	})
}

func requireEntry(t *testing.T, m *MemoryLimiter, key string) {
	t.Helper()
	m.mu.RLock()
	defer m.mu.RUnlock()
	if _, ok := m.entries[key]; !ok {
		t.Fatalf("entry %q not found", key)
	}
}

func requireNoEntry(t *testing.T, m *MemoryLimiter, key string) {
	t.Helper()
	m.mu.RLock()
	defer m.mu.RUnlock()
	if _, ok := m.entries[key]; ok {
		t.Fatalf("entry %q still present", key)
	}
}

func TestCleanup(t *testing.T) {
	cases := []struct {
		name    string
		entry   func() *entry
		removed bool
	}{
		{
			"removes idle entry",
			func() *entry {
				return &entry{blockedUntil: time.Now().Add(-time.Second)}
			},
			true,
		},
		{
			"keeps blocked entry",
			func() *entry {
				return &entry{blockedUntil: time.Now().Add(time.Second)}
			},
			false,
		},
		{
			"keeps recent failures",
			func() *entry {
				now := time.Now()
				return &entry{
					failures:     []time.Time{now.Add(-defaultPolicy().Window / 2)},
					blockedUntil: now.Add(-time.Second),
				}
			},
			false,
		},
		{
			"removes old failures",
			func() *entry {
				now := time.Now()
				return &entry{
					failures:     []time.Time{now.Add(-2 * defaultPolicy().Window)},
					blockedUntil: now.Add(-time.Second),
				}
			},
			true,
		},
		{
			"keeps escalation within decay",
			func() *entry {
				now := time.Now()
				return &entry{
					blockCount:   1,
					blockedUntil: now.Add(-100 * time.Millisecond),
				}
			},
			false,
		},
		{
			"removes escalation past decay",
			func() *entry {
				now := time.Now()
				return &entry{
					blockCount:   1,
					blockedUntil: now.Add(-600 * time.Millisecond),
				}
			},
			true,
		},
		{
			"keeps anomalous entry",
			func() *entry {
				return &entry{blockCount: 1}
			},
			false,
		},
	}

	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			m := newTestLimiter(t)
			m.mu.Lock()
			m.entries["login:alice"] = tt.entry()
			m.mu.Unlock()

			if err := m.Cleanup(context.Background()); err != nil {
				t.Fatalf("cleanup: %v", err)
			}

			exists := hasEntry(t, m, "login:alice")
			if tt.removed && exists {
				t.Fatalf("entry should be removed but still present")
			}
			if !tt.removed && !exists {
				t.Fatalf("entry should be kept but was removed")
			}
		})
	}

	t.Run("unknown prefix is skipped", func(t *testing.T) {
		m := newTestLimiter(t)
		m.mu.Lock()
		m.entries["foo:alice"] = &entry{blockedUntil: time.Now().Add(-time.Second)}
		m.mu.Unlock()

		if err := m.Cleanup(context.Background()); err != nil {
			t.Fatalf("cleanup: %v", err)
		}
		if !hasEntry(t, m, "foo:alice") {
			t.Fatalf("unknown prefix entry was removed")
		}
	})
}

func hasEntry(t *testing.T, m *MemoryLimiter, key string) bool {
	t.Helper()
	m.mu.RLock()
	defer m.mu.RUnlock()
	_, ok := m.entries[key]
	return ok
}

func TestCleanupLoop_Runs(t *testing.T) {
	m := newTestLimiterWithCleanup(t, 20*time.Millisecond)

	m.mu.Lock()
	m.entries["login:alice"] = &entry{blockedUntil: time.Now().Add(-time.Second)}
	m.mu.Unlock()

	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		if !hasEntry(t, m, "login:alice") {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("cleanup loop did not remove idle entry within 500ms")
}
