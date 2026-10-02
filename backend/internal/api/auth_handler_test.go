package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
)

// setupHandler собирает HTTP-стек для тестов
// Возвращает готовый http.Handler и доступ к репозиторию
func setupHandler(t *testing.T) (http.Handler, domains.UserRepository) {
	t.Helper()
	users := memory.NewMemoryUserRepo()
	sessions := memory.NewMemorySessionRepo()
	accessMgr := token.NewAccessTokenManager("test-secret", 15*time.Minute)
	authSvc := auth.NewService(users, sessions, accessMgr, "test-pepper", 15*time.Minute, 7*24*time.Hour, []string{})
	limiter := newPermissiveLimiter(t)

	mux := http.NewServeMux()
	authMW := api.Auth(accessMgr, sessions)
	api.NewAuthHandler(authSvc, limiter).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)
	return mux, users
}

// doJSON сериализует body в JSON, выполняет POST-запрос к h по пути path
// и возвращает записанный ответ
func doJSON(t *testing.T, h http.Handler, path string, body map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func doReq(t *testing.T, h http.Handler, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rdr)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// decodeError разбирает тело ответа как ErrorResponse и возвращает error.code
func decodeError(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var resp struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode error body: %v (%s)", err, rec.Body.String())
	}
	return resp.Error.Code
}

// TestRegister_Success: успешная регистрация с 201 Created
func TestRegister_Success(t *testing.T) {
	h, _ := setupHandler(t)

	rec := doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d, want 201, body: %s", rec.Code, rec.Body.String())
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

// TestRegister_LoginTaken: повторная регистрация с тем же
// логином возвращает 409 Conflict и код ошибки "login_taken"
func TestRegister_LoginTaken(t *testing.T) {
	h, _ := setupHandler(t)
	_ = doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	rec := doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Other", "password": "secret123",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d, want 409", rec.Code)
	}
	if code := decodeError(t, rec); code != "login_taken" {
		t.Fatalf("code = %q, want login_taken", code)
	}
}

// TestRegister_InvalidPassword: некорректный пароль приводит к 400 Bad Request
func TestRegister_InvalidPassword(t *testing.T) {
	h, _ := setupHandler(t)

	for _, pwd := range []string{"short1", "onlyletters", "12345678"} {
		rec := doJSON(t, h, "/api/auth/register", map[string]string{
			"login": "alice", "uname": "Alice", "password": pwd,
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("pwd=%q status %d", pwd, rec.Code)
		}
	}
}

// TestLogin_Success: успешный логин зарегистрированного
// пользователя возвращает 200 OK
func TestLogin_Success(t *testing.T) {
	h, _ := setupHandler(t)
	_ = doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	rec := doJSON(t, h, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("status: %d body=%s", rec.Code, rec.Body.String())
	}
}

// TestLogin_InvalidCredentials: логин с несуществующим
// пользователем возвращает 401 Unauthorized и код "invalid_credentials"
func TestLogin_InvalidCredentials(t *testing.T) {
	h, _ := setupHandler(t)
	rec := doJSON(t, h, "/api/auth/login", map[string]string{
		"login": "nobody", "password": "secret123",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: %d", rec.Code)
	}
	if code := decodeError(t, rec); code != "invalid_credentials" {
		t.Fatalf("code = %q", code)
	}
}

func TestMe_Success(t *testing.T) {
	h, _ := setupHandler(t)
	rec := doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	var reg struct {
		AccessToken string `json:"access_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &reg)

	me := doReq(t, h, http.MethodGet, "/api/auth/me", reg.AccessToken, nil)
	if me.Code != http.StatusOK {
		t.Fatalf("status %d body=%s", me.Code, me.Body.String())
	}
}

func TestMe_Unauthorized(t *testing.T) {
	h, _ := setupHandler(t)
	rec := doReq(t, h, http.MethodGet, "/api/auth/me", "", nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d", rec.Code)
	}
}

func TestSessions_ListAndRevoke(t *testing.T) {
	h, _ := setupHandler(t)
	// 2 сессии
	rec1 := doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	rec2 := doJSON(t, h, "/api/auth/login", map[string]string{
		"login": "alice", "password": "secret123",
	})
	var r1, r2 struct {
		AccessToken string `json:"access_token"`
	}
	_ = json.Unmarshal(rec1.Body.Bytes(), &r1)
	_ = json.Unmarshal(rec2.Body.Bytes(), &r2)

	list := doReq(t, h, http.MethodGet, "/api/sessions", r2.AccessToken, nil)
	if list.Code != http.StatusOK {
		t.Fatalf("list status %d", list.Code)
	}
	var resp struct {
		Sessions []struct {
			ID      int64 `json:"id"`
			Current bool  `json:"current"`
		} `json:"sessions"`
	}
	_ = json.Unmarshal(list.Body.Bytes(), &resp)
	if len(resp.Sessions) != 2 {
		t.Fatalf("sessions = %d, want 2", len(resp.Sessions))
	}

	var firstID int64
	for _, s := range resp.Sessions {
		if !s.Current {
			firstID = s.ID
		}
	}
	del := doReq(t, h, http.MethodDelete, "/api/sessions/"+strconv.FormatInt(firstID, 10), r2.AccessToken, nil)
	if del.Code != http.StatusNoContent {
		t.Fatalf("delete status %d body=%s", del.Code, del.Body.String())
	}
}
func TestRegister_InvalidInput_Details(t *testing.T) {
	h, _ := setupHandler(t)
	rec := doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "a", "uname": "", "password": "123",
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
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error.Code != "invalid_input" {
		t.Fatalf("code = %q", resp.Error.Code)
	}
	if resp.Error.Details["login"] == "" || resp.Error.Details["password"] == "" {
		t.Fatalf("details = %+v", resp.Error.Details)
	}
}

func TestMe_RevokedSession_Unauthorized(t *testing.T) {
	h, _ := setupHandler(t)

	rec := doJSON(t, h, "/api/auth/register", map[string]string{
		"login": "alice", "uname": "Alice", "password": "secret123",
	})
	var r struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &r)

	// logout отзывает сессию на сервере
	logout := doReq(t, h, http.MethodPost, "/api/auth/logout", "", map[string]string{
		"refresh_token": r.RefreshToken,
	})
	if logout.Code != http.StatusNoContent {
		t.Fatalf("logout status %d", logout.Code)
	}

	me := doReq(t, h, http.MethodGet, "/api/auth/me", r.AccessToken, nil)
	if me.Code != http.StatusUnauthorized {
		t.Fatalf("me status %d, want 401", me.Code)
	}
}

func TestSeedAdmin_LoginTakenByUser_Errors(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	ctx := context.Background()

	// обычный пользователь занял admin
	_ = users.Create(ctx, &domains.User{
		Login: "admin", PwdHash: "x", Uname: "not-admin",
		Role: domains.RoleUser, IsActive: true,
	})

	err := memory.SeedAdmin(ctx, users, "admin", "secret", "pepper")
	if err == nil {
		t.Fatalf("want error, got nil")
	}
}

func TestSeedAdmin_Idempotent(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	ctx := context.Background()

	if err := memory.SeedAdmin(ctx, users, "admin", "secret", "pepper"); err != nil {
		t.Fatalf("first seed: %v", err)
	}
	if err := memory.SeedAdmin(ctx, users, "admin", "secret", "pepper"); err != nil {
		t.Fatalf("second seed: %v", err)
	}

}
