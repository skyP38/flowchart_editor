// Package api_test содержит интеграционные тесты HTTP-слоя
package api_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/api"
	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/service/ratelimit"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
)

// testEnv - окружение одного теста:
// готовый HTTP-хендлер и доступ к репозиториям для проверки состояния и подготовки данных
type testEnv struct {
	handler  http.Handler
	users    domains.UserRepository
	sessions domains.SessionRepository
	access   *token.AccessTokenManager
}

// setupOpts - параметры настройки тестового окружения
type setupOpts struct {
	AccessTTL  time.Duration
	RefreshTTL time.Duration
	Pepper     string
	RateLimit  ratelimit.Limiter
}

// newPermissiveLimiter возвращает limiter, который почти никогда не блокирует
func newPermissiveLimiter(t *testing.T) *ratelimit.MemoryLimiter {
	t.Helper()
	m, err := ratelimit.NewMemoryLimiter(map[string]ratelimit.Policy{
		"login": {
			MaxAttempts:   1000,
			Window:        time.Hour,
			BlockDuration: time.Minute,
			MaxBlockCount: 1,
			DecayWindow:   time.Hour,
		},
	}, time.Hour)
	if err != nil {
		t.Fatalf("new limiter: %v", err)
	}
	t.Cleanup(func() { _ = m.Close() })
	return m
}

// setupEnv создет изолированное окружение для одного теста
func setupEnv(t *testing.T, opts setupOpts) *testEnv {
	t.Helper()
	if opts.AccessTTL == 0 {
		opts.AccessTTL = 15 * time.Minute
	}
	if opts.RefreshTTL == 0 {
		opts.RefreshTTL = 7 * 24 * time.Hour
	}
	if opts.Pepper == "" {
		opts.Pepper = "test-pepper"
	}
	limiter := opts.RateLimit
	if limiter == nil {
		limiter = newPermissiveLimiter(t)
	}

	users := memory.NewMemoryUserRepo()
	sessions := memory.NewMemorySessionRepo()
	accessMgr := token.NewAccessTokenManager("test-secret", opts.AccessTTL)
	authSvc := auth.NewService(
		users, sessions, accessMgr,
		opts.Pepper, opts.AccessTTL, opts.RefreshTTL,
	)

	authMW := api.Auth(accessMgr, sessions)
	mux := http.NewServeMux()
	api.NewAuthHandler(authSvc, limiter).RegisterRoutes(mux, authMW)
	api.NewSessionHandler(authSvc).RegisterRoutes(mux, authMW)
	return &testEnv{handler: mux, users: users, sessions: sessions, access: accessMgr}
}

func (e *testEnv) do(t *testing.T, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	return doReq(t, e.handler, method, path, token, body)
}

// register регистрирует пользователя через API и возвращает пару access/refresh токенов
func (e *testEnv) register(t *testing.T, login, uname, password string) (access, refresh string) {
	t.Helper()
	rec := doJSON(t, e.handler, "/api/auth/register", map[string]string{
		"login": login, "uname": uname, "password": password,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("register %s: status %d, body %s", login, rec.Code, rec.Body.String())
	}
	var r struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("register unmarshal: %v", err)
	}
	return r.AccessToken, r.RefreshToken
}

// doJSON сериализует body в JSON, выполняет POST-запрос к h по пути path и возвращает записанный ответ
func doJSON(t *testing.T, h http.Handler, path string, body map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// doReq выполняет произвольный HTTP-запрос
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

// doReqRawHeader - как doReq, но позволяет передать заголовок Authorization без автоматического "Bearer "
func doReqRawHeader(t *testing.T, h http.Handler, method, path, rawAuth string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rdr)
	req.Header.Set("Content-Type", "application/json")
	if rawAuth != "" {
		req.Header.Set("Authorization", rawAuth)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}
