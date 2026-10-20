package api

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

// SessionStatsProvider provides session statistics.
type SessionStatsProvider interface {
	Stats(ctx context.Context) (domains.SessionStats, error)
}

// AdminUserRepository is the subset of the user repository used by admin routes.
type AdminUserRepository interface {
	domains.UserRepository
	ListAll(ctx context.Context) ([]*domains.User, error)
}

// AdminHandler handles administrator-only API routes.
type AdminHandler struct {
	sessions SessionStatsProvider
	users    AdminUserRepository
	pepper   string
}

func NewAdminHandler(s SessionStatsProvider, users AdminUserRepository, pepper string) *AdminHandler {
	return &AdminHandler{sessions: s, users: users, pepper: pepper}
}

// RegisterRoutes registers administrator-only endpoints.
func (h *AdminHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	adminMW := func(next http.Handler) http.Handler {
		return authMW(RequireRole(domains.RoleAdmin)(next))
	}
	mux.Handle("GET /api/admin/stats", adminMW(http.HandlerFunc(h.Stats)))
	mux.Handle("GET /api/admin/users", adminMW(http.HandlerFunc(h.ListUsers)))
	mux.Handle("POST /api/admin/users", adminMW(http.HandlerFunc(h.CreateUser)))
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
