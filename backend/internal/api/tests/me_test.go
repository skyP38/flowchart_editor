package api_test

import (
	"net/http"
	"testing"
)

// TestMe_Success - GET /api/auth/me с валидным access-токеном возвращает 200 и профиль текущего пользователя
func TestMe_Success(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access, _ := env.register(t, "alice", "Alice", "secret123")

	rec := env.do(t, http.MethodGet, "/api/auth/me", access, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d body=%s", rec.Code, rec.Body.String())
	}
}

// TestMe_Unauthorized - GET /api/auth/me без Authorization-заголовка возвращает 401
func TestMe_Unauthorized(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	rec := env.do(t, http.MethodGet, "/api/auth/me", "", nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", rec.Code)
	}
}
