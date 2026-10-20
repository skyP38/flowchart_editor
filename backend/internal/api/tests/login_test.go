package api_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
	"github.com/skyP38/flowchart_editor/backend/internal/service/ratelimit"
)

// TestLogin_CaseInsensitive - логин не зависит от регистра и пробелов
func TestLogin_CaseInsensitive(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "ALICE", "password": "secret123",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("case-insensitive login failed: %d %s", rec.Code, rec.Body.String())
	}
}

// TestLogin_EmptyFields - пустой логин или пароль возвращает 401 invalid_credentials, а не 400
func TestLogin_EmptyFields(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	for _, tc := range []map[string]string{
		{"login": "", "password": "secret123"},
		{"login": "alice", "password": ""},
		{"login": "", "password": ""},
	} {
		rec := doJSON(t, env.handler, "/api/auth/login", tc)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("empty fields %+v: %d", tc, rec.Code)
		}
	}
}

// TestLogin_InactiveUser - деактивированный пользователь не может войти.
func TestLogin_InactiveUser(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	ctx := context.Background()

	hash, _ := password.HashPassword("secret123", "test-pepper")
	u := &domains.User{
		Login: "inactive", PwdHash: hash, Uname: "Inactive",
		Role: domains.RoleUser, IsActive: false, CreatedAt: time.Now(),
	}
	if err := env.users.Create(ctx, u); err != nil {
		t.Fatalf("create: %v", err)
	}

	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "inactive", "password": "secret123",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("inactive login: %d, want 401", rec.Code)
	}
	if code := decodeError(t, rec); code != "invalid_credentials" {
		t.Fatalf("code %q", code)
	}
}

// TestLogin_NoUserEnumeration - ответ для несуществующего пользователя
// и для существующего с неверным паролем  идентичен
func TestLogin_NoUserEnumeration(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	rec1 := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "ghost", "password": "secret123",
	})
	rec2 := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "wrong",
	})

	if rec1.Code != rec2.Code {
		t.Fatalf("status mismatch: %d vs %d", rec1.Code, rec2.Code)
	}
	if rec1.Body.String() != rec2.Body.String() {
		t.Fatalf("body differs:\n%s\n%s", rec1.Body.String(), rec2.Body.String())
	}
}

// TestLogin_RateLimit - при превышении MaxAttempts неудачных попыток логин блокируется: 429 + заголовок Retry-After
// Блокировка применяется даже к корректному паролю, пока она активна
func TestLogin_RateLimit(t *testing.T) {
	limiter, err := ratelimit.NewMemoryLimiter(map[string]ratelimit.Policy{
		"login": {
			MaxAttempts:   3,
			Window:        time.Minute,
			BlockDuration: time.Minute,
			MaxBlockCount: 1,
			DecayWindow:   time.Minute,
		},
	}, time.Hour)
	if err != nil {
		t.Fatalf("limiter: %v", err)
	}
	t.Cleanup(func() { _ = limiter.Close() })

	env := setupEnv(t, setupOpts{RateLimit: limiter})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	// 3 неудачи - все 401
	for i := range 3 {
		rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
			"login": "alice", "password": "wrong",
		})
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("failure #%d: %d, want 401", i+1, rec.Code)
		}
	}

	// 4-й запрос - 429, есть Retry-After
	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "wrong",
	})
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("blocked: %d, want 429", rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatalf("missing Retry-After header")
	}
	if code := decodeError(t, rec); code != "too_many_requests" {
		t.Fatalf("code = %q, want too_many_requests", code)
	}

	// Корректный пароль во время блокировки - тоже 429
	rec = doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("correct password during block: %d, want 429", rec.Code)
	}
}

// TestLogin_TimingUserNotFound - защита от timing-атаки через dummyHash
// Время ответа для существующего и несуществующего пользователя должно быть сопоставимо
func TestLogin_TimingUserNotFound(t *testing.T) {
	if testing.Short() {
		t.Skip("timing test skipped in -short")
	}
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	measure := func(login string) time.Duration {
		start := time.Now()
		_ = doJSON(t, env.handler, "/api/auth/login", map[string]string{
			"login": login, "password": "wrong-pass",
		})
		return time.Since(start)
	}

	measure("alice")
	measure("nobody")

	existing := measure("alice")
	missing := measure("nobody")

	diff := existing - missing
	if diff < 0 {
		diff = -diff
	}
	if diff > 20*time.Millisecond {
		t.Fatalf("timing leak: existing=%v missing=%v", existing, missing)
	}
}
