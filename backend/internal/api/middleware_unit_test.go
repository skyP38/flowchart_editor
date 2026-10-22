package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
)

// RequirRole

// TestRequireRole_Unit проверяет middleware RequireRole изнутри пакета,
// подкладывая роль прямо в контекст.
func TestRequireRole_Unit(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mw := RequireRole(domains.RoleAdmin)

	cases := []struct {
		name string
		role string
		want int
	}{
		{"admin allowed", domains.RoleAdmin, http.StatusOK},
		{"user forbidden", domains.RoleUser, http.StatusForbidden},
		{"empty forbidden", "", http.StatusForbidden},
		{"unknown forbidden", "moderator", http.StatusForbidden},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/test", nil)
			ctx := context.WithValue(req.Context(), ctxUserRole, tc.role)
			req = req.WithContext(ctx)

			rec := httptest.NewRecorder()
			mw(inner).ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("role=%q: got %d, want %d", tc.role, rec.Code, tc.want)
			}
		})
	}
}

// TestRequireRole_MultipleRoles - любая из перечисленных ролей допускается
func TestRequireRole_MultipleRoles(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mw := RequireRole(domains.RoleAdmin, domains.RoleUser)

	for _, role := range []string{domains.RoleAdmin, domains.RoleUser} {
		req := httptest.NewRequest(http.MethodGet, "/test", nil)
		ctx := context.WithValue(req.Context(), ctxUserRole, role)
		req = req.WithContext(ctx)
		rec := httptest.NewRecorder()
		mw(inner).ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("role=%q: got %d, want 200", role, rec.Code)
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	ctx := context.WithValue(req.Context(), ctxUserRole, "moderator")
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()
	mw(inner).ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("moderator: got %d, want 403", rec.Code)
	}
}

// TestRequireRole_EmptyListForbidsAll - если список ролей пуст, не пропускаем никого
func TestRequireRole_EmptyListForbidsAll(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mw := RequireRole("") // пустая роль игнорируется

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	ctx := context.WithValue(req.Context(), ctxUserRole, domains.RoleAdmin)
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()
	mw(inner).ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("empty whitelist should forbid admin, got %d", rec.Code)
	}
}

// Auth
// Секрет, который используется и в AccessTokenManager, и в signCustomToken
const authTestSecret = "test-secret"

// authFixture - минимальный набор зависимостей для тестов Auth
type authFixture struct {
	mgr      *token.AccessTokenManager
	sessions *memory.MemorySessionRepo
	user     *domains.User
	session  *domains.Session
}

func newAuthFixture(t *testing.T) *authFixture {
	t.Helper()
	mgr := token.NewAccessTokenManager(authTestSecret, 15*time.Minute)
	sessions := memory.NewMemorySessionRepo()

	user := &domains.User{
		ID:       1,
		Login:    "alice",
		Role:     domains.RoleUser,
		IsActive: true,
	}
	sess := &domains.Session{
		UserID:    user.ID,
		TokenHash: "hash-1",
		CreatedAt: time.Now().UTC(),
		ExpiresAt: time.Now().UTC().Add(time.Hour),
	}
	if err := sessions.Create(context.Background(), sess); err != nil {
		t.Fatalf("create session: %v", err)
	}
	return &authFixture{mgr: mgr, sessions: sessions, user: user, session: sess}
}

// authResult - результат запроса через Auth-middleware
type authResult struct {
	rec    *httptest.ResponseRecorder
	ctx    context.Context // nil, если inner не вызывался
	called bool
}

// authRequest прогоняет запрос через Auth-middleware с заданным заголовком Authorization
func authRequest(t *testing.T, mw AuthMW, header string) authResult {
	t.Helper()
	var (
		captured context.Context
		called   bool
	)
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		captured = r.Context()
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	if header != "" {
		req.Header.Set("Authorization", header)
	}
	rec := httptest.NewRecorder()
	mw(inner).ServeHTTP(rec, req)
	return authResult{rec: rec, ctx: captured, called: called}
}

// signCustomToken подписывает произвольные claims тем же секретом, что и AccessTokenManager
func signCustomToken(t *testing.T, claims jwt.MapClaims) string {
	t.Helper()
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).
		SignedString([]byte(authTestSecret))
	if err != nil {
		t.Fatalf("sign custom token: %v", err)
	}
	return tok
}

// TestAuth_MissingHeader - нет заголовка Authorization
func TestAuth_MissingHeader(t *testing.T) {
	f := newAuthFixture(t)
	res := authRequest(t, Auth(f.mgr, f.sessions), "")
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_MalformedHeader - заголовок есть, но не в формате "Bearer <token>"
func TestAuth_MalformedHeader(t *testing.T) {
	f := newAuthFixture(t)
	mw := Auth(f.mgr, f.sessions)

	cases := []struct {
		name   string
		header string
	}{
		{"no bearer prefix", "Token abc"},
		{"basic auth", "Basic dXNlcjpwYXNz"},
		{"bearer only", "Bearer"},
		{"bearer space only", "Bearer "},
		{"lowercase bearer", "bearer xyz"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res := authRequest(t, mw, tc.header)
			if res.rec.Code != http.StatusUnauthorized {
				t.Fatalf("status %d, want 401", res.rec.Code)
			}
			if res.called {
				t.Fatal("inner handler must not be called")
			}
		})
	}
}

// TestAuth_InvalidToken - строка не парсится как JWT
func TestAuth_InvalidToken(t *testing.T) {
	f := newAuthFixture(t)
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer not-a-jwt")
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_InvalidSubject - валидная подпись, но sub не парсится в int64
// Покрывает ветку "invalid token subject"
func TestAuth_InvalidSubject(t *testing.T) {
	f := newAuthFixture(t)
	tok := signCustomToken(t, jwt.MapClaims{
		"sub":  "not-a-number",
		"jti":  "1",
		"iss":  token.Issuer,
		"role": domains.RoleUser,
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(time.Hour).Unix(),
	})
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_InvalidSessionID - валидная подпись, sub корректен, но jti (ID сессии) не парсится в int64
// Покрывает ветку "invalid token session"
func TestAuth_InvalidSessionID(t *testing.T) {
	f := newAuthFixture(t)
	tok := signCustomToken(t, jwt.MapClaims{
		"sub":  "1",
		"jti":  "not-a-number",
		"iss":  token.Issuer,
		"role": domains.RoleUser,
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(time.Hour).Unix(),
	})
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_SessionNotFound - токен валиден, ссылается на несуществующий ID сессии
func TestAuth_SessionNotFound(t *testing.T) {
	f := newAuthFixture(t)
	tok, err := f.mgr.GenerateAccessToken(f.user, 99999)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_WrongUserInSession - сессия существует, но принадлежит другому пользователю
func TestAuth_WrongUserInSession(t *testing.T) {
	f := newAuthFixture(t)
	otherSess := &domains.Session{
		UserID:    2, // другой пользователь
		TokenHash: "hash-2",
		CreatedAt: time.Now().UTC(),
		ExpiresAt: time.Now().UTC().Add(time.Hour),
	}
	if err := f.sessions.Create(context.Background(), otherSess); err != nil {
		t.Fatalf("create other session: %v", err)
	}
	// Токен выпущен для user.ID=1, но ссылается на сессию user.ID=2
	tok, err := f.mgr.GenerateAccessToken(f.user, otherSess.ID)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_RevokedSession - сессия отозвана (RevokedAt != nil)
func TestAuth_RevokedSession(t *testing.T) {
	f := newAuthFixture(t)
	if err := f.sessions.Revoke(context.Background(), f.session.ID, time.Now().UTC()); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	tok, err := f.mgr.GenerateAccessToken(f.user, f.session.ID)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_ExpiredSession - сессия истекла по ExpiresAt
func TestAuth_ExpiredSession(t *testing.T) {
	f := newAuthFixture(t)
	expired := &domains.Session{
		UserID:    f.user.ID,
		TokenHash: "hash-expired",
		CreatedAt: time.Now().UTC().Add(-2 * time.Hour),
		ExpiresAt: time.Now().UTC().Add(-time.Hour),
	}
	if err := f.sessions.Create(context.Background(), expired); err != nil {
		t.Fatalf("create expired: %v", err)
	}
	tok, err := f.mgr.GenerateAccessToken(f.user, expired.ID)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.rec.Code)
	}
	if res.called {
		t.Fatal("inner handler must not be called")
	}
}

// TestAuth_Success - валидный токен, активная сессия того же пользователя
// Проверяет, что middleware пропускает запрос и кладёт userID / sessionID / role в контекст
func TestAuth_Success(t *testing.T) {
	f := newAuthFixture(t)
	tok, err := f.mgr.GenerateAccessToken(f.user, f.session.ID)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	res := authRequest(t, Auth(f.mgr, f.sessions), "Bearer "+tok)
	if res.rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200", res.rec.Code)
	}
	if !res.called {
		t.Fatal("inner handler must be called")
	}
	if got := UserIDFrom(res.ctx); got != f.user.ID {
		t.Fatalf("userID = %d, want %d", got, f.user.ID)
	}
	if got := SessionIDFrom(res.ctx); got != f.session.ID {
		t.Fatalf("sessionID = %d, want %d", got, f.session.ID)
	}
	if got := RoleFrom(res.ctx); got != f.user.Role {
		t.Fatalf("role = %q, want %q", got, f.user.Role)
	}
}
