package sessioncleanup

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

type fakeCleaner struct {
	mu            sync.Mutex
	calls         int
	removed       int
	err           error
	panicVal      any
	lastRetention time.Duration
}

func (f *fakeCleaner) RemoveExpired(ctx context.Context, retention time.Duration) (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.lastRetention = retention
	if f.panicVal != nil {
		p := f.panicVal
		f.panicVal = nil
		panic(p)
	}
	return f.removed, f.err
}

func (f *fakeCleaner) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

func (f *fakeCleaner) retentionArg() time.Duration {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.lastRetention
}

var _ domains.SessionCleaner = (*fakeCleaner)(nil)

func newTestJanitor(t *testing.T, cleaner domains.SessionCleaner, interval, retention time.Duration) *Janitor {
	t.Helper()
	j, err := New(cleaner, interval, retention)
	if err != nil {
		t.Fatalf("new janitor: %v", err)
	}
	t.Cleanup(func() { _ = j.Close() })
	return j
}

func TestNew_InvalidInput(t *testing.T) {
	cases := []struct {
		name      string
		cleaner   domains.SessionCleaner
		interval  time.Duration
		retention time.Duration
	}{
		{"nil cleaner", nil, time.Minute, time.Hour},
		{"zero interval", &fakeCleaner{}, 0, time.Hour},
		{"negative interval", &fakeCleaner{}, -time.Second, time.Hour},
		{"zero retention", &fakeCleaner{}, time.Minute, 0},
		{"negative retention", &fakeCleaner{}, time.Minute, -time.Second},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			j, err := New(tt.cleaner, tt.interval, tt.retention)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
			if j != nil {
				t.Fatalf("expected nil janitor, got %v", j)
			}
		})
	}
}

func TestCleanupOnce(t *testing.T) {
	t.Run("calls RemoveExpired with retention", func(t *testing.T) {
		f := &fakeCleaner{removed: 5}
		j := newTestJanitor(t, f, time.Hour, 30*time.Minute)

		if err := j.CleanupOnce(context.Background()); err != nil {
			t.Fatalf("cleanup once: %v", err)
		}
		if got := f.callCount(); got != 1 {
			t.Fatalf("calls: got %d, want 1", got)
		}
		if got := f.retentionArg(); got != 30*time.Minute {
			t.Fatalf("retention: got %v, want %v", got, 30*time.Minute)
		}
	})

	t.Run("returns error from cleaner", func(t *testing.T) {
		wantErr := errors.New("boom")
		f := &fakeCleaner{err: wantErr}
		j := newTestJanitor(t, f, time.Hour, time.Hour)

		err := j.CleanupOnce(context.Background())
		if !errors.Is(err, wantErr) {
			t.Fatalf("want %v, got %v", wantErr, err)
		}
	})
}

func TestCleanupLoop_Runs(t *testing.T) {
	f := &fakeCleaner{removed: 1}
	_ = newTestJanitor(t, f, 20*time.Millisecond, time.Hour)

	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		if f.callCount() >= 1 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("cleanup loop did not run within 500ms, calls=%d", f.callCount())
}

func TestCleanupLoop_SurvivesPanic(t *testing.T) {
	f := &fakeCleaner{panicVal: "boom"}
	_ = newTestJanitor(t, f, 20*time.Millisecond, time.Hour)

	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if f.callCount() >= 2 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("cleanup loop did not survive panic, calls=%d", f.callCount())
}

func TestClose_StopsLoop(t *testing.T) {
	f := &fakeCleaner{}
	j, err := New(f, 20*time.Millisecond, time.Hour)
	if err != nil {
		t.Fatalf("new janitor: %v", err)
	}

	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) && f.callCount() == 0 {
		time.Sleep(10 * time.Millisecond)
	}
	if f.callCount() == 0 {
		t.Fatalf("janitor did not run before Close")
	}

	if err := j.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	after := f.callCount()
	time.Sleep(80 * time.Millisecond)
	if got := f.callCount(); got != after {
		t.Fatalf("cleanup called after Close: was %d, now %d", after, got)
	}
}

func TestClose_Idempotent(t *testing.T) {
	f := &fakeCleaner{}
	j, err := New(f, time.Hour, time.Hour)
	if err != nil {
		t.Fatalf("new janitor: %v", err)
	}
	if err := j.Close(); err != nil {
		t.Fatalf("first close: %v", err)
	}
	if err := j.Close(); err != nil {
		t.Fatalf("second close: %v", err)
	}
}
