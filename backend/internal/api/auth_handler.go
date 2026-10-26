package api

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"net/http"
	"strconv"
	"time"
	// "os"
	// "fmt"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/service/ratelimit"
	"github.com/skyP38/flowchart_editor/backend/internal/service/sessionmetadata"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

// AuthHandler - HTTP-обработчик аутентификации
type AuthHandler struct {
	svc              *auth.Service
	limiter          ratelimit.Limiter
	audit            domains.AuditLogRepository
	metadataResolver SessionMetadataResolver
}

func NewAuthHandler(svc *auth.Service, limiter ratelimit.Limiter, audits ...domains.AuditLogRepository) *AuthHandler {
	h := &AuthHandler{svc: svc, limiter: limiter}
	if len(audits) > 0 {
		h.audit = audits[0]
	}
	/*geoClient := sessionmetadata.NewGeoLiteClient(
	        os.Getenv("MAXMIND_ACCOUNT_ID"),
	        os.Getenv("MAXMIND_LICENSE_KEY"),
		)

		h.SetSessionMetadataResolver(
			sessionmetadata.NewResolver(geoClient),
		)*/
	h.metadataResolver = sessionmetadata.NewResolver(nil)
	return h
}

// RegisterRoutes регистрирует маршруты обработчика в mux
func (h *AuthHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.HandleFunc("POST /api/auth/register", h.Register)
	mux.HandleFunc("POST /api/auth/login", h.Login)
	mux.HandleFunc("POST /api/auth/refresh", h.Refresh)
	mux.HandleFunc("POST /api/auth/logout", h.Logout)

	// требуется активная сессия
	mux.Handle("GET /api/auth/me", authMW(http.HandlerFunc(h.Me)))
}

// registerRequest - тело запроса регистрации
type registerRequest struct {
	Login    string `json:"login"`
	Uname    string `json:"uname"`
	Password string `json:"password"`
}

// loginRequest - тело запроса логина
type loginRequest struct {
	Login     string   `json:"login"`
	Password  string   `json:"password"`
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// userDTO - представление пользователя в ответах
type userDTO struct {
	ID    int64  `json:"id"`
	Login string `json:"login"`
	Uname string `json:"uname"`
	Role  string `json:"role"`
}

// authResponse - ответ на успешные попытки Register/Login
type authResponse struct {
	User         userDTO `json:"user"`
	AccessToken  string  `json:"access_token"`
	RefreshToken string  `json:"refresh_token"`
	ExpiresIn    int     `json:"expires_in"`
}

type SessionMetadataResolver interface {
	Resolve(userAgent string, remoteAddr string) domains.SessionMetadata
}

// Register обрабатывает POST /api/auth/register
// Возвращает 201 Created при успехе, иначе 400 invalid_input
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	defer func() { _ = r.Body.Close() }()

	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "wrong JSON body")
		return
	}

	res, err := h.svc.Register(r.Context(), auth.RegisterInput{
		Login:    req.Login,
		Uname:    req.Uname,
		Password: req.Password,
		Metadata: h.sessionMetadata(r),
	})
	if err != nil {
		writeAuthError(w, err)
		return
	}
	transport.WriteJSON(w, http.StatusCreated, toDTO(res))
}

// Login обрабатывает POST /api/auth/login
// Возвращает 200 OK при успехе, иначе 400 invalid_input
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	defer func() { _ = r.Body.Close() }()
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "wrong JSON body")
		return
	}

	login := domains.NormalizeLogin(req.Login)
	if login == "" || req.Password == "" {
		h.writeAudit(r.Context(), nil, login, "login.failed", "Fail")
		writeAuthError(w, auth.ErrInvalidCredentials)
		return
	}

	// rate limit по логину
	keys := []string{"login:" + login}

	d, err := h.limiter.Check(r.Context(), keys)
	if err != nil {
		log.Printf("ratelimit: check failed: %v; keys=%v", err, keys)
	}
	if !d.Allowed {
		retrySeconds := max(1, int(math.Ceil(d.RetryAfter.Seconds())))
		w.Header().Set("Retry-After", strconv.Itoa(retrySeconds))
		log.Printf("ratelimit: blocked; keys=%v blocked_by=%s retry_after=%s", keys, d.BlockedBy, d.RetryAfter)
		transport.WriteError(w, http.StatusTooManyRequests, transport.CodeTooManyRequests, "too many attempts, try again later")
		h.writeAudit(r.Context(), nil, login, "login.failed", "Fail")
		return
	}

	res, err := h.svc.Login(r.Context(), auth.LoginInput{
		Login:    req.Login,
		Password: req.Password,
		Metadata: h.metadataForRequest(r, req.Latitude, req.Longitude),
	})

	if err != nil {
		if errors.Is(err, auth.ErrInvalidCredentials) {
			if rerr := h.limiter.RecordFailure(r.Context(), keys); rerr != nil {
				log.Printf("ratelimit: record failure: %v; keys=%v", rerr, keys)
			}
		}
		h.writeAudit(r.Context(), nil, login, "login.failed", "Fail")
		writeAuthError(w, err)
		return
	}

	if rerr := h.limiter.RecordSuccess(r.Context(), keys); rerr != nil {
		log.Printf("ratelimit: record success: %v; keys=%v", rerr, keys)
	}
	userID := res.User.ID
	h.writeAudit(r.Context(), &userID, login, "login.success", "Success")
	transport.WriteJSON(w, http.StatusOK, toDTO(res))
}

// Refresh обрабатывает POST /api/auth/refresh
// Возвращает 200 OK при успехе, иначе 400 invalid_input
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	defer func() { _ = r.Body.Close() }()
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "wrong JSON body")
		return
	}

	res, err := h.svc.RefreshWithMetadata(r.Context(), req.RefreshToken, h.sessionMetadata(r))
	if err != nil {
		writeAuthError(w, err)
		return
	}
	transport.WriteJSON(w, http.StatusOK, toDTO(res))
}

// Logout обрабатывает POST /api/auth/refresh
// Возвращает 200 OK при успехе, иначе 400 invalid_input
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	defer func() { _ = r.Body.Close() }()
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, transport.CodeInvalidInput, "wrong JSON body")
		return
	}

	_ = h.svc.Logout(r.Context(), req.RefreshToken)
	w.WriteHeader(http.StatusNoContent)
}

// Me обрабатывает GET /api/auth/me - возвращает профиль текущего пользователя
func (h *AuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	u, err := h.svc.GetUser(r.Context(), UserIDFrom(r.Context()))
	if err != nil {
		writeAuthError(w, err)
		return
	}
	transport.WriteJSON(w, http.StatusOK, userDTO{
		ID: u.ID, Login: u.Login, Uname: u.Uname, Role: u.Role,
	})
}

// toDTO преобразует AuthResult в authResponse
func toDTO(res *auth.AuthResult) authResponse {
	return authResponse{
		User: userDTO{
			ID: res.User.ID, Login: res.User.Login,
			Uname: res.User.Uname, Role: res.User.Role,
		},
		AccessToken:  res.AccessToken,
		RefreshToken: res.RefreshToken,
		ExpiresIn:    int(res.ExpiresIn / time.Second),
	}
}

// writeAuthError переводит ошибки сервиса в HTTP-ответы
// Соответствие ошибок и ответов:
//   - *auth.ValidationError       -> 400 invalid_input;
//   - auth.ErrLoginTaken          -> 409 login_taken;
//   - auth.ErrInvalidCredentials  -> 401 invalid_credentials;
//   - любая другая ошибка         -> 500 internal
func writeAuthError(w http.ResponseWriter, err error) {
	var verrs *auth.ValidationErrors
	var verr *auth.ValidationError

	switch {
	case errors.As(err, &verrs):
		transport.WriteErrorDetails(
			w, http.StatusBadRequest,
			transport.CodeInvalidInput, "Validation failed",
			verrs.Fields,
		)
	case errors.As(err, &verr):
		transport.WriteErrorDetails(
			w, http.StatusBadRequest,
			transport.CodeInvalidInput, "Validation failed",
			map[string]string{verr.Field: verr.Message},
		)
	case errors.Is(err, auth.ErrLoginTaken):
		transport.WriteError(w, http.StatusConflict, transport.CodeLoginTaken, "login is already taken")
	case errors.Is(err, auth.ErrInvalidCredentials):
		transport.WriteError(w, http.StatusUnauthorized, transport.CodeInvalidCredentials, "invalid login or password")
	case errors.Is(err, auth.ErrInvalidRefreshToken):
		transport.WriteError(w, http.StatusUnauthorized, transport.CodeInvalidRefreshToken, "refresh token is invalid or expired")
	default:
		transport.WriteError(w, http.StatusInternalServerError, transport.CodeInternal, "internal server error")
	}
}

// запись события авторизации
func (h *AuthHandler) writeAudit(
	ctx context.Context,
	userID *int64,
	login string,
	action string,
	status string,
) {
	if h.audit == nil {
		return
	}

	entry := &domains.AuditLog{
		UserID: userID,
		Login:  domains.NormalizeLogin(login),
		Action: action,
		Entity: "session",
		Status: status,
	}

	if err := h.audit.CreateLog(ctx, entry); err != nil {
		log.Printf("audit authentication: %v", err)
	}
}

func (h *AuthHandler) SetSessionMetadataResolver(
	resolver SessionMetadataResolver,
) {
	h.metadataResolver = resolver
}

func (h *AuthHandler) sessionMetadata(r *http.Request) domains.SessionMetadata {
	if h.metadataResolver == nil {
		return domains.SessionMetadata{
			DeviceName: "Unknown device",
			Location:   "Not recorded",
		}
	}
	return h.metadataResolver.Resolve(r.UserAgent(), r.RemoteAddr)
}

func (h *AuthHandler) metadataForRequest(
	r *http.Request,
	latitude *float64,
	longitude *float64,
) domains.SessionMetadata {
	// Получаем название браузера через существующий resolver.
	// Resolver больше не должен обращаться к GeoLite API.
	metadata := h.sessionMetadata(r)

	if latitude == nil || longitude == nil {
		return metadata
	}

	lat := *latitude
	lon := *longitude

	// Проверяем допустимые диапазоны координат.
	if lat < -90 || lat > 90 || lon < -180 || lon > 180 {
		return metadata
	}

	metadata.Location = sessionmetadata.CoordinatesToLocation(lat, lon)
	return metadata
}
