package api

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

type SessionStatsProvider interface {
	Stats(ctx context.Context) (domains.SessionStats, error)
}

type AdminUserRepository interface {
	domains.UserRepository
	ListAll(ctx context.Context) ([]*domains.User, error)
	DeleteWithData(ctx context.Context, id int64) error
}

type AdminSessionRepository interface {
	SessionStatsProvider
	ListAll(ctx context.Context) ([]*domains.Session, error)
	Revoke(ctx context.Context, id int64, at time.Time) error
}

type AdminHandler struct {
	sessions AdminSessionRepository
	users    AdminUserRepository
	pepper   string
	logs     domains.AuditLogRepository
}

func NewAdminHandler(s AdminSessionRepository, users AdminUserRepository, pepper string, logs ...domains.AuditLogRepository) *AdminHandler {
	h := &AdminHandler{sessions: s, users: users, pepper: pepper}
	if len(logs) > 0 {
		h.logs = logs[0]
	}
	return h
}

// RegisterRoutes registers administrator-only endpoints.
func (h *AdminHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	adminMW := func(next http.Handler) http.Handler {
		return authMW(RequireRole(domains.RoleAdmin)(next))
	}
	mux.Handle("GET /api/admin/stats", adminMW(http.HandlerFunc(h.Stats)))
	mux.Handle("GET /api/admin/users", adminMW(http.HandlerFunc(h.ListUsers)))
	mux.Handle("POST /api/admin/users", adminMW(http.HandlerFunc(h.CreateUser)))
	mux.Handle("GET /api/admin/sessions", adminMW(http.HandlerFunc(h.ListSessions)))
	mux.Handle("DELETE /api/admin/sessions/{id}", adminMW(http.HandlerFunc(h.RevokeSession)))
	mux.Handle("GET /api/admin/logs", adminMW(http.HandlerFunc(h.ListLogs)))
	mux.Handle("DELETE /api/admin/users/{id}", adminMW(http.HandlerFunc(h.DeleteUser)))
}

// Stats handles GET /api/admin/stats.
func (h *AdminHandler) Stats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.sessions.Stats(r.Context())
	if err != nil {
		log.Printf("admin stats: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	transport.WriteJSON(w, http.StatusOK, map[string]any{"sessions": stats})
}

// adminUserDTO is safe to return to the client; it never contains a password hash.
type adminUserDTO struct {
	ID        int64      `json:"id"`
	Login     string     `json:"login"`
	Uname     string     `json:"uname"`
	Role      string     `json:"role"`
	CreatedAt time.Time  `json:"createdAt"`
	LastLogin *time.Time `json:"lastLogin"`
	IsActive  bool       `json:"isActive"`
}

func toAdminUserDTO(u *domains.User) adminUserDTO {
	return adminUserDTO{
		ID: u.ID, Login: u.Login, Uname: u.Uname, Role: u.Role,
		CreatedAt: u.CreatedAt, LastLogin: u.LastLogin, IsActive: u.IsActive,
	}
}

// ListUsers handles GET /api/admin/users.
func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := h.users.ListAll(r.Context())
	if err != nil {
		log.Printf("admin list users: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	result := make([]adminUserDTO, 0, len(users))
	for _, u := range users {
		result = append(result, toAdminUserDTO(u))
	}
	transport.WriteJSON(w, http.StatusOK, map[string]any{"users": result})
}

type createUserRequest struct {
	Login    string `json:"login"`
	Uname    string `json:"uname"`
	Password string `json:"password"`
	Role     string `json:"role"`
}

var adminLoginPattern = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)

func (h *AdminHandler) CreateUser(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	var req createUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "wrong JSON body")
		return
	}

	login := domains.NormalizeLogin(req.Login)
	uname := strings.TrimSpace(req.Uname)
	role := strings.ToLower(strings.TrimSpace(req.Role))
	if role == "" {
		role = domains.RoleUser
	}
	fieldErrors := make(map[string]string)
	if !adminLoginPattern.MatchString(login) {
		fieldErrors["login"] = "must be 3-32 chars of [a-zA-Z0-9_]"
	}
	if len([]rune(uname)) < 1 || len([]rune(uname)) > 200 {
		fieldErrors["uname"] = "must be 1-200 characters"
	}
	if role != domains.RoleUser && role != domains.RoleAdmin {
		fieldErrors["role"] = "must be either 'user' or 'admin'"
	}
	hasLetter, hasDigit := false, false
	for _, r := range req.Password {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
			hasLetter = true
		}
		if r >= '0' && r <= '9' {
			hasDigit = true
		}
	}
	if len(req.Password) < 8 || !hasLetter || !hasDigit {
		fieldErrors["password"] = "must be at least 8 characters and contain a letter and a digit"
	}
	if len(fieldErrors) > 0 {
		transport.WriteErrorDetails(w, http.StatusBadRequest, transport.CodeInvalidInput, "Validation failed", fieldErrors)
		return
	}

	if existing, err := h.users.GetByLogin(r.Context(), login); err == nil && existing != nil {
		transport.WriteError(w, http.StatusConflict, transport.CodeLoginTaken, "login is already taken")
		return
	} else if err != nil && !errors.Is(err, domains.ErrNotFound) {
		log.Printf("admin user lookup: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}

	hash, err := password.HashPassword(req.Password, h.pepper)
	if err != nil {
		log.Printf("admin hash password: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	u := &domains.User{
		Login: login, Uname: uname, PwdHash: hash, Role: role,
		CreatedAt: time.Now().UTC(), IsActive: true,
	}
	if err := h.users.Create(r.Context(), u); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			transport.WriteError(w, http.StatusConflict, transport.CodeLoginTaken, "login is already taken")
			return
		}
		log.Printf("admin create user: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	transport.WriteJSON(w, http.StatusCreated, map[string]any{"user": toAdminUserDTO(u)})
}

type adminSessionDTO struct {
	ID        int64      `json:"id"`
	UserID    int64      `json:"userId"`
	Login     string     `json:"login"`
	Uname     string     `json:"uname"`
	CreatedAt time.Time  `json:"createdAt"`
	ExpiresAt time.Time  `json:"expiresAt"`
	RevokedAt *time.Time `json:"revokedAt,omitempty"`
	Active    bool       `json:"active"`
}

func (h *AdminHandler) ListSessions(w http.ResponseWriter, r *http.Request) {
	sessions, err := h.sessions.ListAll(r.Context())
	if err != nil {
		log.Printf("admin list sessions: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	users, err := h.users.ListAll(r.Context())
	if err != nil {
		log.Printf("admin list session users: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	usersByID := make(map[int64]*domains.User, len(users))
	for _, user := range users {
		usersByID[user.ID] = user
	}
	now := time.Now().UTC()
	result := make([]adminSessionDTO, 0, len(sessions))
	for _, session := range sessions {
		item := adminSessionDTO{
			ID: session.ID, UserID: session.UserID, CreatedAt: session.CreatedAt,
			ExpiresAt: session.ExpiresAt, RevokedAt: session.RevokedAt,
			Active: session.IsActive(now),
		}
		if user, ok := usersByID[session.UserID]; ok {
			item.Login = user.Login
			item.Uname = user.Uname
		}
		result = append(result, item)
	}
	transport.WriteJSON(w, http.StatusOK, map[string]any{"sessions": result})
}

func (h *AdminHandler) RevokeSession(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "invalid session id")
		return
	}
	if err := h.sessions.Revoke(r.Context(), id, time.Now().UTC()); err != nil {
		if errors.Is(err, domains.ErrNotFound) || errors.Is(err, domains.ErrSessionNotFound) {
			transport.WriteError(w, http.StatusNotFound, transport.CodeSessionNotFound, "session not found")
			return
		}
		log.Printf("admin revoke session: %v", err)
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *AdminHandler) ListLogs(
	w http.ResponseWriter,
	r *http.Request,
) {
	if h.logs == nil {
		transport.WriteError(
			w,
			http.StatusInternalServerError,
			transport.CodeInternal,
			"logging repository is unavailable",
		)
		return
	}

	limit := 10
	offset := 0

	if value := r.URL.Query().Get("limit"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 1 {
			transport.WriteError(
				w,
				http.StatusBadRequest,
				transport.CodeInvalidInput,
				"invalid limit",
			)
			return
		}
		limit = parsed
	}

	if limit > 100 {
		limit = 100
	}

	if value := r.URL.Query().Get("offset"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 0 {
			transport.WriteError(
				w,
				http.StatusBadRequest,
				transport.CodeInvalidInput,
				"invalid offset",
			)
			return
		}
		offset = parsed
	}

	logs, total, err := h.logs.ListLogs(
		r.Context(),
		limit,
		offset,
	)
	if err != nil {
		log.Printf("admin list logs: %v", err)
		transport.WriteError(
			w,
			http.StatusInternalServerError,
			transport.CodeInternal,
			"internal server error",
		)
		return
	}

	transport.WriteJSON(
		w,
		http.StatusOK,
		map[string]any{
			"logs":   logs,
			"total":  total,
			"limit":  limit,
			"offset": offset,
		},
	)
}

func (h *AdminHandler) DeleteUser(w http.ResponseWriter, r *http.Request) {
    id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
    if err != nil || id <= 0 {
        transport.WriteError(
            w,
            http.StatusBadRequest,
            transport.CodeInvalidInput,
            "invalid user id",
        )
        return
    }

    if id == UserIDFrom(r.Context()) {
        transport.WriteError(
            w,
            http.StatusForbidden,
            transport.CodeForbidden,
            "cannot delete the currently authenticated administrator",
        )
        return
    }

    if err := h.users.DeleteWithData(r.Context(), id); err != nil {
	if errors.Is(err, domains.ErrLastAdmin) {
		transport.WriteError(
			w,
			http.StatusConflict,
			transport.CodeLastAdmin,
			"Cannot delete the last administrator",
		)
		return
	}
	if errors.Is(err, domains.ErrNotFound) {
            transport.WriteError(
                w,
                http.StatusNotFound,
                transport.CodeNotFound,
                "user not found",
            )
            return
        }

        if errors.Is(err, domains.ErrLastAdmin) {
            transport.WriteError(
                w,
                http.StatusConflict,
                transport.CodeForbidden,
                "cannot delete the last administrator",
            )
            return
        }

        log.Printf("admin delete user: %v", err)
        transport.WriteError(
            w,
            http.StatusInternalServerError,
            transport.CodeInternal,
            "internal server error",
        )
        return
    }

    w.WriteHeader(http.StatusNoContent)
}
