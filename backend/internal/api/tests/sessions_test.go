package api_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

// TestRevokeSession_CannotRevokeOtherUser - пользователь не может отозвать сессию другого пользователя, даже зная её ID
func TestRevokeSession_CannotRevokeOtherUser(t *testing.T) {
	env := setupEnv(t, setupOpts{})

	// alice - 2 сессии
	_, _ = env.register(t, "alice", "Alice", "secret123")
	recLogin := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	var alice struct {
		AccessToken string `json:"access_token"`
	}
	_ = json.Unmarshal(recLogin.Body.Bytes(), &alice)

	// alice смотрит свои сессии
	list := env.do(t, http.MethodGet, "/api/sessions", alice.AccessToken, nil)
	var lr struct {
		Sessions []struct {
			ID      int64 `json:"id"`
			Current bool  `json:"current"`
		} `json:"sessions"`
	}
	_ = json.Unmarshal(list.Body.Bytes(), &lr)
	var targetID int64
	for _, s := range lr.Sessions {
		if !s.Current {
			targetID = s.ID
		}
	}
	if targetID == 0 {
		t.Fatalf("no target session")
	}

	// bob пытается отозвать сессию alice
	bobAccess, _ := env.register(t, "bob", "Bob", "secret123")
	rec := env.do(t, http.MethodDelete,
		"/api/sessions/"+strconv.FormatInt(targetID, 10), bobAccess, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status %d, want 404 (bob must not see alice's session)", rec.Code)
	}
}

// TestRegister_BodyTooLarge - тело запроса больше DefaultMaxBodyBytes отклоняется middleware BodyLimit
// TODO: после upload в бизнес логике подумать
func TestRegister_BodyTooLarge(t *testing.T) {
	env := setupEnv(t, setupOpts{})

	big := strings.Repeat("a", 2<<20) // 2 MiB
	body := `{"login":"` + big + `","uname":"x","password":"secret123"}`
	req := httptest.NewRequest(http.MethodPost, "/api/auth/register",
		strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	env.handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge &&
		rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d, want 413 or 400", rec.Code)
	}
}

// TestSessions_DeleteOwnCurrentSession - удаление текущей сессии немедленно делает ее access-токен недействительным
func TestSessions_DeleteOwnCurrentSession(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access, _ := env.register(t, "alice", "Alice", "secret123")

	list := env.do(t, http.MethodGet, "/api/sessions", access, nil)
	t.Logf("GET /api/sessions status=%d body=%q", list.Code, list.Body.String())
	var lr struct {
		Sessions []struct {
			ID      int64 `json:"id"`
			Current bool  `json:"current"`
		} `json:"sessions"`
	}
	_ = json.Unmarshal(list.Body.Bytes(), &lr)
	t.Logf("parsed sessions: %+v", lr.Sessions)
	var cur int64
	for _, s := range lr.Sessions {
		if s.Current {
			cur = s.ID
		}
	}
	if cur == 0 {
		t.Fatal("no current session")
	}

	rec := env.do(t, http.MethodDelete, "/api/sessions/"+strconv.FormatInt(cur, 10), access, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete current: %d", rec.Code)
	}
	rec = env.do(t, http.MethodGet, "/api/auth/me", access, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("access after self-delete: %d, want 401", rec.Code)
	}
}

// TestSessions_RevokeAllKeepsCurrent - DELETE /api/sessions отзывает
// все сессии пользователя, кроме текущей
func TestSessions_RevokeAllKeepsCurrent(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	var tokens []string
	for range 3 {
		rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
			"login": "alice", "password": "secret123",
		})
		var r struct {
			AccessToken string `json:"access_token"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &r)
		tokens = append(tokens, r.AccessToken)
	}

	if r := env.do(t, http.MethodDelete, "/api/sessions", tokens[2], nil); r.Code != http.StatusNoContent {
		t.Fatalf("revoke all: %d", r.Code)
	}

	if r := env.do(t, http.MethodGet, "/api/auth/me", tokens[2], nil); r.Code != http.StatusOK {
		t.Fatalf("current dead: %d", r.Code)
	}
	for i, tok := range tokens[:2] {
		if r := env.do(t, http.MethodGet, "/api/auth/me", tok, nil); r.Code != http.StatusUnauthorized {
			t.Fatalf("session %d alive: %d", i, r.Code)
		}
	}
}

// TestSessions_DoubleDeleteIdempotency - повторное удаление уже
// удаленной сессии возвращает 404 (сессия не найдена)
func TestSessions_DoubleDeleteIdempotency(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access, _ := env.register(t, "alice", "Alice", "secret123")

	// вторая сессия
	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	var r2 struct {
		AccessToken string `json:"access_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &r2)

	list := env.do(t, http.MethodGet, "/api/sessions", access, nil)
	var lr struct {
		Sessions []struct {
			ID      int64 `json:"id"`
			Current bool  `json:"current"`
		} `json:"sessions"`
	}
	_ = json.Unmarshal(list.Body.Bytes(), &lr)
	var target int64
	for _, s := range lr.Sessions {
		if !s.Current {
			target = s.ID
		}
	}

	if r := env.do(t, http.MethodDelete, fmt.Sprintf("/api/sessions/%d", target), access, nil); r.Code != http.StatusNoContent {
		t.Fatalf("first delete: %d", r.Code)
	}
	r := env.do(t, http.MethodDelete, fmt.Sprintf("/api/sessions/%d", target), access, nil)
	if r.Code != http.StatusNotFound && r.Code != http.StatusNoContent {
		t.Fatalf("second delete: %d", r.Code)
	}
}
