package api_test

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

// TestAuth_MalformedAuthorizationHeader - некорректные варианты
// заголовка Authorization отклоняются с 401
func TestAuth_MalformedAuthorizationHeader(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	cases := []struct {
		name   string
		header string
	}{
		{"empty", ""},
		{"no bearer prefix", "Token abc.def.ghi"},
		{"bearer without value", "Bearer"},
		{"bearer with space only", "Bearer "},
		{"lowercase bearer", "bearer abc.def.ghi"},
		{"basic auth", "Basic dXNlcjpwYXNz"},
		{"newline injection", "Bearer abc\ndef"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := doReqRawHeader(t, env.handler, http.MethodGet, "/api/auth/me", tc.header, nil)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("status %d, want 401", rec.Code)
			}
		})
	}
}

// TestAuth_TokenSignedWithWrongSecret - токен, подписанный чужим секретом, отклоняется:
// HMAC-подпись не сходится
func TestAuth_TokenSignedWithWrongSecret(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	claims := jwt.MapClaims{
		"sub": "1", "jti": "1", "iss": "backend",
		"role": domains.RoleAdmin,
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(time.Hour).Unix(),
	}
	tok, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).
		SignedString([]byte("wrong-secret"))

	rec := env.do(t, http.MethodGet, "/api/auth/me", tok, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("forged token accepted: %d", rec.Code)
	}
}

// TestAuth_RejectsNoneAlgorithm - токен с alg=none отклоняется
func TestAuth_RejectsNoneAlgorithm(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	claims := jwt.MapClaims{
		"sub": "1", "jti": "1", "iss": "backend",
		"role": domains.RoleAdmin,
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(time.Hour).Unix(),
	}
	tok, err := jwt.NewWithClaims(jwt.SigningMethodNone, claims).
		SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("sign none: %v", err)
	}
	rec := env.do(t, http.MethodGet, "/api/auth/me", tok, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("alg=none accepted! status %d", rec.Code)
	}
}

// TestAuth_RejectsWrongIssuer - токен с iss != "backend" отклоняется
func TestAuth_RejectsWrongIssuer(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	claims := jwt.MapClaims{
		"sub": "1", "jti": "1", "iss": "evil",
		"role": domains.RoleUser,
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(time.Hour).Unix(),
	}
	tok, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).
		SignedString([]byte("test-secret"))
	rec := env.do(t, http.MethodGet, "/api/auth/me", tok, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("wrong issuer accepted: %d", rec.Code)
	}
}

// TestAuth_RejectsTamperedPayload - изменение payload ломает подпись
func TestAuth_RejectsTamperedPayload(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	access, _ := env.register(t, "alice", "Alice", "secret123")

	parts := strings.Split(access, ".")
	if len(parts) != 3 {
		t.Fatalf("unexpected token shape")
	}
	p := []byte(parts[1])
	if p[0] == 'e' {
		p[0] = 'f'
	} else {
		p[0] = 'e'
	}
	tampered := parts[0] + "." + string(p) + "." + parts[2]

	rec := env.do(t, http.MethodGet, "/api/auth/me", tampered, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("tampered token accepted: %d", rec.Code)
	}
}

// TestAuth_RejectsTokenWithUnknownSession - токен валиден, но сессии нет
func TestAuth_RejectsTokenWithUnknownSession(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	u := &domains.User{ID: 1, Login: "ghost", Role: domains.RoleUser}
	tok, err := env.access.GenerateAccessToken(u, 99999)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	rec := env.do(t, http.MethodGet, "/api/auth/me", tok, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", rec.Code)
	}
}
