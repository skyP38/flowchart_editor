package api_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

// TestLogout_InvalidatesAccessToken - logout мгновенно делает access-токен недействительным,
// не дожидаясь истечения его TTL
func TestLogout_InvalidatesAccessToken(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access, refresh := env.register(t, "alice", "Alice", "secret123")

	// access работает
	rec := env.do(t, http.MethodGet, "/api/auth/me", access, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("me before logout: %d", rec.Code)
	}

	// logout
	rec = env.do(t, http.MethodPost, "/api/auth/logout", "", map[string]string{
		"refresh_token": refresh,
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("logout: %d %s", rec.Code, rec.Body.String())
	}

	rec = env.do(t, http.MethodGet, "/api/auth/me", access, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("me after logout: %d, want 401 (access token still valid!)", rec.Code)
	}
}

// TestLogout_RefreshDoesNotWorkAfterLogout - после logout refresh-токен тоже не работает
func TestLogout_RefreshDoesNotWorkAfterLogout(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, refresh := env.register(t, "alice", "Alice", "secret123")

	_ = env.do(t, http.MethodPost, "/api/auth/logout", "", map[string]string{
		"refresh_token": refresh,
	})

	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh,
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("refresh after logout: %d, want 401", rec.Code)
	}
}

// TestLogout_Idempotent - повторный logout с тем же refresh-токеном возвращает 204
func TestLogout_Idempotent(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, refresh := env.register(t, "alice", "Alice", "secret123")

	// дважды logout - оба 204
	for i := range 2 {
		rec := env.do(t, http.MethodPost, "/api/auth/logout", "", map[string]string{
			"refresh_token": refresh,
		})
		if rec.Code != http.StatusNoContent {
			t.Fatalf("logout #%d: %d", i+1, rec.Code)
		}
	}
}

// TestLogout_MissingToken_NoError - logout без refresh-токена всё равно возвращает 204
func TestLogout_MissingToken_NoError(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	rec := env.do(t, http.MethodPost, "/api/auth/logout", "", map[string]string{
		"refresh_token": "",
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("logout empty: %d", rec.Code)
	}
}

// TestLogout_DoesNotAffectOtherSessions - logout одной сессии не трогает остальные
func TestLogout_DoesNotAffectOtherSessions(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, refresh1 := env.register(t, "alice", "Alice", "secret123")

	// Вторая сессия через login
	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	var r2 struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &r2)

	// Logout первой сессии
	if r := env.do(t, http.MethodPost, "/api/auth/logout", "", map[string]string{
		"refresh_token": refresh1,
	}); r.Code != http.StatusNoContent {
		t.Fatalf("logout: %d", r.Code)
	}

	// Вторая сессия жива
	if r := env.do(t, http.MethodGet, "/api/auth/me", r2.AccessToken, nil); r.Code != http.StatusOK {
		t.Fatalf("other session killed: %d", r.Code)
	}
	if r := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": r2.RefreshToken,
	}); r.Code != http.StatusOK {
		t.Fatalf("other refresh broken: %d", r.Code)
	}
}
