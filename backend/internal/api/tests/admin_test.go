package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
)

// createAdmin - создает администратора напрямую в репозитории и логинится
// Возвращает access-токен
func createAdmin(t *testing.T, env *testEnv, login, pwd string) string {
	t.Helper()
	hash, err := password.HashPassword(pwd, "test-pepper")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	u := &domains.User{
		Login: login, PwdHash: hash, Uname: "Admin",
		Role: domains.RoleAdmin, IsActive: true, CreatedAt: time.Now(),
	}
	if err := env.users.Create(context.Background(), u); err != nil {
		t.Fatalf("create admin: %v", err)
	}
	rec := doJSON(t, env.handler, "/api/auth/login", map[string]string{
		"login": login, "password": pwd,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("admin login: %d %s", rec.Code, rec.Body.String())
	}
	var r struct {
		AccessToken string `json:"access_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &r)
	return r.AccessToken
}

// TestMe_ReturnsRole - роль admin приходит и в login, и в /me
func TestMe_ReturnsRole(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	adminAccess := createAdmin(t, env, "admin", "adminpass")

	rec := env.do(t, http.MethodGet, "/api/auth/me", adminAccess, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("me: %d", rec.Code)
	}
	var me struct {
		Role string `json:"role"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &me)
	if me.Role != domains.RoleAdmin {
		t.Fatalf("role = %q, want admin", me.Role)
	}
}

// TestAccessToken_ContainsRoleClaim - роль зашита в JWT claims
func TestAccessToken_ContainsRoleClaim(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access, _ := env.register(t, "alice", "Alice", "secret123")

	claims, err := env.access.ParseAccessToken(access)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if claims.Role != domains.RoleUser {
		t.Fatalf("role claim = %q, want user", claims.Role)
	}
}

// TestAdminOnlyEndpoint - RequireRole через реальный middleware
func TestAdminOnlyEndpoint(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	mux := env.handler.(*http.ServeMux)
	authMW := api.Auth(env.access, env.sessions)

	// endpoint с реальным RequireRole, а не с inline-проверкой
	mux.Handle("GET /api/admin/ping",
		authMW(api.RequireRole(domains.RoleAdmin)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))))

	// user -> 403
	userAccess, _ := env.register(t, "alice", "Alice", "secret123")
	if r := env.do(t, http.MethodGet, "/api/admin/ping", userAccess, nil); r.Code != http.StatusForbidden {
		t.Fatalf("user: %d, want 403", r.Code)
	}
	// no token -> 401
	if r := env.do(t, http.MethodGet, "/api/admin/ping", "", nil); r.Code != http.StatusUnauthorized {
		t.Fatalf("no token: %d, want 401", r.Code)
	}
	// admin -> 200
	adminAccess := createAdmin(t, env, "admin", "adminpass")
	if r := env.do(t, http.MethodGet, "/api/admin/ping", adminAccess, nil); r.Code != http.StatusOK {
		t.Fatalf("admin: %d, want 200", r.Code)
	}
}

// TestAdminStats_Endpoint - реальный GET /api/admin/stats
// Проверяет доступ по роли и SessionStats
// func TestAdminStats_Endpoint(t *testing.T) {
// 	env := setupEnv(t, setupOpts{})

// 	memSessions, ok := env.sessions.(*memory.MemorySessionRepo)
// 	if !ok {
// 		t.Fatalf("expected *memory.MemorySessionRepo, got %T", env.sessions)
// 	}

// 	memUsers, ok := env.users.(*memory.MemoryUserRepo)
// 	if !ok {
// 		t.Fatalf("expected *memory.MemoryUserRepo, got %T", env.users)
// 	}

// 	mux := env.handler.(*http.ServeMux)
// 	authMW := api.Auth(env.access, env.sessions)
// 	api.NewAdminHandler(memSessions, memUsers, "test").RegisterRoutes(mux, authMW)

// 	// user -> 403
// 	userAccess, _ := env.register(t, "alice", "Alice", "secret123")
// 	if r := env.do(t, http.MethodGet, "/api/admin/stats", userAccess, nil); r.Code != http.StatusForbidden {
// 		t.Fatalf("user: %d, want 403", r.Code)
// 	}
// 	// no token -> 401
// 	if r := env.do(t, http.MethodGet, "/api/admin/stats", "", nil); r.Code != http.StatusUnauthorized {
// 		t.Fatalf("no token: %d, want 401", r.Code)
// 	}

// 	// admin -> 200
// 	adminAccess := createAdmin(t, env, "admin", "adminpass")
// 	rec := env.do(t, http.MethodGet, "/api/admin/stats", adminAccess, nil)
// 	if rec.Code != http.StatusOK {
// 		t.Fatalf("admin: %d body=%s", rec.Code, rec.Body.String())
// 	}

// 	var resp struct {
// 		Sessions struct {
// 			Total   int `json:"total"`
// 			Active  int `json:"active"`
// 			Revoked int `json:"revoked"`
// 			Expired int `json:"expired"`
// 		} `json:"sessions"`
// 	}
// 	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
// 		t.Fatalf("unmarshal: %v", err)
// 	}
// 	s := resp.Sessions
// 	if s.Total != s.Active+s.Revoked+s.Expired {
// 		t.Fatalf("invariant broken: %+v", s)
// 	}
// 	// alice + admin = 2 active sessions
// 	if s.Active < 2 {
// 		t.Fatalf("active = %d, want >= 2", s.Active)
// 	}
// }
