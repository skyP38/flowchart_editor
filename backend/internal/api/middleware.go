// Package api содержит HTTP-обработчики и middleware сервиса
package api

import (
	"context"
	"errors"
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
func Auth(mgr *token.AccessTokenManager, sessions domains.SessionRepository, audits ...domains.AuditLogRepository) AuthMW {
	var auditRepo domains.AuditLogRepository
	if len(audits) > 0 {
		auditRepo = audits[0]
	}
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
			if err != nil {
				if errors.Is(err, domains.ErrNotFound) || errors.Is(err, domains.ErrSessionNotFound) {
					transport.WriteError(w, http.StatusUnauthorized, transport.CodeSessionRevoked, "session is no longer active")
					return
				}
				// реальная ошибка БД
				log.Printf("auth: session lookup: %v", err)
				transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
				return
			}
			if sess.UserID != uid || !sess.IsActive(time.Now().UTC()) {
				transport.WriteError(w, http.StatusUnauthorized, transport.CodeSessionRevoked, "session is no longer active")
				return
			}

			// чтобы читать было проще через отдельные хелперы
			ctx := context.WithValue(r.Context(), ctxUserID, uid)
			ctx = context.WithValue(ctx, ctxSessionID, sid)
			ctx = context.WithValue(ctx, ctxUserRole, claims.Role)
			
			recorder := &auditResponseWriter {
				ResponseWriter: w,
				status: http.StatusOK,
			}
			authedRequest := r.WithContext(ctx)
			next.ServeHTTP(recorder, authedRequest)

			if auditRepo == nil {
				return
			}

			action, entity, entityID, ok := auditAction(authedRequest)
			if !ok {
				return
			}
			status := "Success"
			if recorder.status >= http.StatusBadRequest {
				status = "Fail"
			}
			userID := uid
			entry := &domains.AuditLog {
				UserID: &userID,
				Action: action,
				Entity: entity,
				EntityID: entityID,
				Status: status,
			}
			if err := auditRepo.CreateLog(r.Context(), entry); err != nil {
				log.Printf("audit request: %v", err)
			}
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

type auditResponseWriter struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (w *auditResponseWriter) WriteHeader(status int) {
	if w.wroteHeader {
		return
	}

	w.status = status
	w.wroteHeader = true
	w.ResponseWriter.WriteHeader(status)
}

func (w *auditResponseWriter) Write(data []byte) (int, error) {
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(data)
}

func auditID(value string) *int64 {
	id, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return nil
	}
	return &id
}

func auditAction(r *http.Request) (string, string, *int64, bool) {
	path := r.URL.Path

	switch {
	case r.Method == http.MethodPost && path == "/api/projects":
		return "project.create", "project", nil, true

	case r.Method == http.MethodPatch && r.PathValue("projectId") != "":
		return "project.update", "project", auditID(r.PathValue("projectId")), true

	case r.Method == http.MethodDelete && r.PathValue("flowchartId") != "":
		return "block_scheme.delete", "block_scheme", auditID(r.PathValue("flowchartId")), true

	case r.Method == http.MethodPut && strings.HasSuffix(path, "/content"):
		return "block_scheme.update", "block_scheme", auditID(r.PathValue("flowchartId")), true

	case r.Method == http.MethodPost &&
		strings.HasPrefix(path, "/api/projects/") &&
		strings.HasSuffix(path, "/flowcharts"):
		return "block_scheme.create", "project", auditID(r.PathValue("projectId")), true

	case r.Method == http.MethodDelete && r.PathValue("projectId") != "":
		return "project.delete", "project", auditID(r.PathValue("projectId")), true

	case r.Method == http.MethodPost && path == "/api/admin/users":
		return "user.create", "user", nil, true

	case r.Method == http.MethodDelete && r.PathValue("id") != "" &&
		strings.HasPrefix(path, "/api/sessions/"):
		return "session.revoke", "session", auditID(r.PathValue("id")), true

	case r.Method == http.MethodDelete && path == "/api/sessions":
		return "session.revoke_all", "session", nil, true
	}

	return "", "", nil, false
}
