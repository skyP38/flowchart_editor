package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestRegister_BoundaryLoginLength - границы длины логина и алфавит
// loginRe = `^[a-zA-Z0-9_]{3,32}$`
func TestRegister_BoundaryLoginLength(t *testing.T) {
	env := setupEnv(t, setupOpts{})

	valid := []string{"abc", strings.Repeat("a", 32)}
	for _, login := range valid {
		rec := doJSON(t, env.handler, "/api/auth/register", map[string]string{
			"login": login, "uname": "X", "password": "secret123",
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("login len=%d rejected: %d", len(login), rec.Code)
		}
	}

	invalid := []string{"ab", strings.Repeat("a", 33), "user-name", "user name", "user.name", "юзер"}
	for _, login := range invalid {
		rec := doJSON(t, env.handler, "/api/auth/register", map[string]string{
			"login": login, "uname": "X", "password": "secret123",
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("login %q accepted: %d", login, rec.Code)
		}
	}
}

// TestRegister_BoundaryUname - длина uname считается в рунах, а не в байтах
func TestRegister_BoundaryUname(t *testing.T) {
	env := setupEnv(t, setupOpts{})

	// 1 руна - валидно
	if r := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "usr1", "uname": "X", "password": "secret123",
	}); r.Code != http.StatusCreated {
		t.Fatalf("1-rune uname rejected: %d", r.Code)
	}

	// 200 рун - валидно (юникод)
	if r := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "usr2", "uname": strings.Repeat("я", 200), "password": "secret123",
	}); r.Code != http.StatusCreated {
		t.Fatalf("200-rune uname rejected: %d", r.Code)
	}

	// 201 руна - невалидно
	if r := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "usr3", "uname": strings.Repeat("я", 201), "password": "secret123",
	}); r.Code != http.StatusBadRequest {
		t.Fatalf("201-rune uname accepted: %d", r.Code)
	}
}

// TestRegister_LoginCaseInsensitiveUniqueness - логины сравниваются без учета регистра
func TestRegister_LoginCaseInsensitiveUniqueness(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_ = doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "Alice", "uname": "A", "password": "secret123",
	})
	rec := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "B", "password": "secret123",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("case-insensitive uniqueness broken: %d", rec.Code)
	}
}

// TestRegister_MultipleValidationErrors - при нескольких ошибках валидации возвращаются все
func TestRegister_MultipleValidationErrors(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	rec := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "a", "uname": "", "password": "1",
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d", rec.Code)
	}
	var resp struct {
		Error struct {
			Code    string            `json:"code"`
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if resp.Error.Code != "invalid_input" {
		t.Fatalf("code %q", resp.Error.Code)
	}
	for _, f := range []string{"login", "uname", "password"} {
		if resp.Error.Details[f] == "" {
			t.Errorf("missing detail %q: %+v", f, resp.Error.Details)
		}
	}
}

// TestRegister_MalformedJSON - невалидный JSON в теле - 400 с invalid_input
func TestRegister_MalformedJSON(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	req := httptest.NewRequest(http.MethodPost, "/api/auth/register",
		strings.NewReader(`{"login":`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	env.handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d, want 400", rec.Code)
	}
}

// TestRegister_EmptyBody - пустое тело (r.Body == nil) - 400
func TestRegister_EmptyBody(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", nil)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	env.handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d, want 400", rec.Code)
	}
}

// TestRegister_Success - успешная регистрация возвращает 201, профиль пользователя и пару токенов
func TestRegister_Success(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	rec := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d, want 201", rec.Code)
	}

	var resp struct {
		User struct {
			ID                 int64
			Login, Uname, Role string
		} `json:"user"`
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if resp.User.Login != "alice" || resp.User.Role != "user" {
		t.Fatalf("unexpected user: %+v", resp.User)
	}
	if resp.AccessToken == "" {
		t.Fatalf("access token empty")
	}
	if resp.ExpiresIn != 900 {
		t.Fatalf("expires_in = %d, want 900", resp.ExpiresIn)
	}
}

// TestRegister_LoginTaken - регистрация занятого логина возвращает 409 Conflict с кодом login_taken
func TestRegister_LoginTaken(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")
	rec := doJSON(t, env.handler, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Other", "password": "secret123",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("status %d, want 409", rec.Code)
	}
	if code := decodeError(t, rec); code != "login_taken" {
		t.Fatalf("code = %q, want login_taken", code)
	}
}
