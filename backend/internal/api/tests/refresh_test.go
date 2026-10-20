package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// TestRefresh_Success - успешный refresh возвращает новую пару токенов
func TestRefresh_Success(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, refresh := env.register(t, "alice", "Alice", "secret123")

	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, body %s", rec.Code, rec.Body.String())
	}

	var r struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if r.AccessToken == "" || r.RefreshToken == "" {
		t.Fatalf("empty tokens: %+v", r)
	}
	if r.RefreshToken == refresh {
		t.Fatalf("refresh token не ротирован")
	}
}

// TestRefresh_Rotation_OldRefreshInvalid - после ротации старый
// refresh-токен не принимается: 401 invalid_refresh_token
func TestRefresh_Rotation_OldRefreshInvalid(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, refresh1 := env.register(t, "alice", "Alice", "secret123")

	// первый refresh — должен вернуть новую пару
	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh1,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("first refresh: %d %s", rec.Code, rec.Body.String())
	}

	// повторный refresh со старым токеном — 401
	rec = env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh1,
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("reuse old refresh: status %d, want 401", rec.Code)
	}
	if code := decodeError(t, rec); code != "invalid_refresh_token" {
		t.Fatalf("code = %q", code)
	}
}

// TestRefresh_ReuseDetection_RevokesAll - reuse отозванного refresh-токена
// трактуется как компрометация: отзываются все сессии пользователя
func TestRefresh_ReuseDetection_RevokesAll(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access1, refresh1 := env.register(t, "alice", "Alice", "secret123")

	// логин второй раз — вторая сессия
	recLogin := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	if recLogin.Code != http.StatusOK {
		t.Fatalf("login: %d", recLogin.Code)
	}
	var r2 struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	_ = json.Unmarshal(recLogin.Body.Bytes(), &r2)

	// refresh1 - ротация
	_ = env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh1,
	})

	// reuse refresh1 - должно отозвать все сессии пользователя
	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh1,
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("reuse: status %d", rec.Code)
	}

	// вторая сессия тоже должна быть невалидна
	rec = env.do(t, http.MethodGet, "/api/auth/me", r2.AccessToken, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("second session still works: %d, want 401", rec.Code)
	}

	// и первая тоже
	rec = env.do(t, http.MethodGet, "/api/auth/me", access1, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("first session still works: %d, want 401", rec.Code)
	}
}

// TestRefresh_InvalidToken - произвольная строка вместо refresh-токена отклоняется 401
func TestRefresh_InvalidToken(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": "not-a-real-token",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", rec.Code)
	}
}

// TestRefresh_EmptyToken - пустой refresh-токен отклоняется сразу
func TestRefresh_EmptyToken(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": "",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", rec.Code)
	}
}

// TestRefresh_ExpiredSession - истекшая сессия не обновляется
func TestRefresh_ExpiredSession(t *testing.T) {
	env := setupEnv(t, setupOpts{RefreshTTL: -time.Second})
	_, refresh := env.register(t, "alice", "Alice", "secret123")

	rec := env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh,
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expired refresh: status %d, want 401", rec.Code)
	}
}

// TestRefresh_Concurrent - две независимые сессии одного пользователя обновляются параллельно
func TestRefresh_Concurrent(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, r1 := env.register(t, "alice", "Alice", "secret123")

	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	var lr struct {
		RefreshToken string `json:"refresh_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &lr)
	r2 := lr.RefreshToken

	tokens := []string{r1, r2}
	codes := make([]int, len(tokens))
	var wg sync.WaitGroup

	for i := range tokens {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			body, _ := json.Marshal(map[string]string{"refresh_token": tokens[idx]})
			req := httptest.NewRequest(http.MethodPost, "/api/auth/refresh", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			env.handler.ServeHTTP(rec, req)
			codes[idx] = rec.Code
		}(i)
	}
	wg.Wait()

	for i, c := range codes {
		if c != http.StatusOK {
			t.Fatalf("session %d: status %d, want 200 (codes=%v)", i, c, codes)
		}
	}
}

// TestRefresh_ReuseDetection_MarksRevoked - после reuse-detection сессии не удаляются, а помечаются RevokedAt
func TestRefresh_ReuseDetection_MarksRevoked(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, refresh1 := env.register(t, "alice", "Alice", "secret123")

	// Вторая сессия
	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("second login: %d", rec.Code)
	}

	// Первый refresh - ротация
	_ = env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh1,
	})

	// Повторный refresh старым токеном - reuse-detection
	_ = env.do(t, http.MethodPost, "/api/auth/refresh", "", map[string]string{
		"refresh_token": refresh1,
	})

	// Все сессии пользователя должны быть отозваны
	u, err := env.users.GetByLogin(context.Background(), "alice")
	if err != nil {
		t.Fatalf("get user: %v", err)
	}
	sessions, err := env.sessions.ListByUserID(context.Background(), u.ID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(sessions) < 2 {
		t.Fatalf("want >= 2 sessions, got %d", len(sessions))
	}
	for _, s := range sessions {
		if s.RevokedAt == nil {
			t.Fatalf("session %d not revoked after reuse detection", s.ID)
		}
	}
}
