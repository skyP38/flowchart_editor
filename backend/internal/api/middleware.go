// Package api содержит HTTP-обработчики и middleware сервиса
package api

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

// ctxKey - приватный тип для ключей context.Context
type ctxKey int

const (
	ctxUserID ctxKey = iota
	ctxSessionID
	ctxUserRole
)

// AuthMW - функция-middleware, оборачивающая http.Handler
type AuthMW func(http.Handler) http.Handler

// Auth парсит access-токен, проверяет активность сессии и кладёт userID/sessionID/role в контекст
func Auth(mgr *token.AccessTokenManager, sessions domains.SessionRepository) AuthMW {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if !strings.HasPrefix(header, "Bearer ") {
				transport.WriteError(w, http.StatusUnauthorized, transport.CodeUnauthorized, "missing bearer token")
				return
			}
			claims, err := mgr.ParseAccessToken(strings.TrimPrefix(header, "Bearer "))
			if err != nil {
				transport.WriteError(w, http.StatusUnauthorized, transport.CodeUnauthorized, "invalid or expired token")
				return
			}
			uid, err := strconv.ParseInt(claims.Subject, 10, 64)
			if err != nil {
				transport.WriteError(w, http.StatusUnauthorized, transport.CodeUnauthorized, "invalid token subject")
				return
			}
			sid, err := strconv.ParseInt(claims.ID, 10, 64)
			if err != nil {
				transport.WriteError(w, http.StatusUnauthorized, transport.CodeUnauthorized, "invalid token session")
				return
			}

			// проверка сессии в хранилище на каждом запросе приводит к logout
			sess, err := sessions.GetByID(r.Context(), sid)
			if err != nil || sess.UserID != uid || !sess.IsActive(time.Now().UTC()) {
				transport.WriteError(w, http.StatusUnauthorized, transport.CodeSessionRevoked, "session is no longer active")
				return
			}

			// чтобы читать было проще через отдельные хелперы
			ctx := context.WithValue(r.Context(), ctxUserID, uid)
			ctx = context.WithValue(ctx, ctxSessionID, sid)
			ctx = context.WithValue(ctx, ctxUserRole, claims.Role)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireRole возвращает middleware, пропускающий запрос если роль пользователя входит в список разрешённых
func RequireRole(roles ...string) AuthMW {
	allowed := make(map[string]struct{}, len(roles))
	for _, r := range roles {
		if r == "" {
			continue
		}
		allowed[r] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			role := RoleFrom(r.Context())
			if _, ok := allowed[role]; !ok {
				uid := UserIDFrom(r.Context())
				log.Printf("forbidden: uid=%d role=%q path=%s", uid, role, r.URL.Path)
				transport.WriteError(w, http.StatusForbidden, transport.CodeForbidden, "insufficient permissions")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// UserIDFrom извлекает ID пользователя из контекста запроса
func UserIDFrom(ctx context.Context) int64 {
	v, _ := ctx.Value(ctxUserID).(int64)
	return v
}

// SessionIDFrom извлекает ID сессии из контекста запроса
func SessionIDFrom(ctx context.Context) int64 {
	v, _ := ctx.Value(ctxSessionID).(int64)
	return v
}

// RoleFrom извлекает роль пользователя из контекста запроса
func RoleFrom(ctx context.Context) string {
	v, _ := ctx.Value(ctxUserRole).(string)
	return v
}
