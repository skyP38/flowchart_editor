package api

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

type ctxKey int

const (
	ctxUserID ctxKey = iota
	ctxSessionID
	ctxUserRole
)

type AuthMW func(http.Handler) http.Handler

// Auth парсит access-токен, проверяет активность сессии и кладёт userID/sessionID/role в контекст
func Auth(mgr *token.AccessTokenManager, sessions domains.SessionRepository) AuthMW {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if !strings.HasPrefix(header, "Bearer ") {
				transport.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			claims, err := mgr.ParseAccessToken(strings.TrimPrefix(header, "Bearer "))
			if err != nil {
				transport.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}
			uid, err := strconv.ParseInt(claims.Subject, 10, 64)
			if err != nil {
				transport.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid token subject")
				return
			}
			sid, err := strconv.ParseInt(claims.ID, 10, 64)
			if err != nil {
				transport.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid token session")
				return
			}

			sess, err := sessions.GetByID(r.Context(), sid)
			if err != nil || sess.UserID != uid || !sess.IsActive(time.Now().UTC()) {
				transport.WriteError(w, http.StatusUnauthorized, "session_revoked", "session is no longer active")
				return
			}

			ctx := context.WithValue(r.Context(), ctxUserID, uid)
			ctx = context.WithValue(ctx, ctxSessionID, sid)
			ctx = context.WithValue(ctx, ctxUserRole, claims.Role)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func UserIDFrom(ctx context.Context) int64 {
	v, _ := ctx.Value(ctxUserID).(int64)
	return v
}

func SessionIDFrom(ctx context.Context) int64 {
	v, _ := ctx.Value(ctxSessionID).(int64)
	return v
}

func RoleFrom(ctx context.Context) string {
	v, _ := ctx.Value(ctxUserRole).(string)
	return v
}
