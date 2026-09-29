package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/skyP38/flowchart_editor/backend/internal/service/auth"
	"github.com/skyP38/flowchart_editor/backend/internal/transport"
)

// AuthHandler - HTTP-обработчик аутентификации
type AuthHandler struct {
	svc *auth.Service
}

func NewAuthHandler(svc *auth.Service) *AuthHandler {
	return &AuthHandler{svc: svc}
}

// RegisterRoutes регистрирует маршруты обработчика в mux
func (h *AuthHandler) RegisterRoutes(mux *http.ServeMux, authMW AuthMW) {
	mux.HandleFunc("POST /api/auth/register", h.Register)
	mux.HandleFunc("POST /api/auth/login", h.Login)
	mux.HandleFunc("POST /api/auth/refresh", h.Refresh)
	mux.HandleFunc("POST /api/auth/logout", h.Logout)

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
	Login    string `json:"login"`
	Password string `json:"password"`
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

// Register обрабатывает POST /api/auth/register
// Возвращает 201 Created при успехе, иначе 400 invalid_input
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()

	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", "wrong JSON body")
		return
	}

	res, err := h.svc.Register(r.Context(), auth.RegisterInput{
		Login:    req.Login,
		Uname:    req.Uname,
		Password: req.Password,
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
	defer r.Body.Close()
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", "wrong JSON body")
		return
	}

	res, err := h.svc.Login(r.Context(), auth.LoginInput{
		Login: req.Login, Password: req.Password,
	})
	if err != nil {
		writeAuthError(w, err)
		return
	}
	transport.WriteJSON(w, http.StatusOK, toDTO(res))
}

// Refresh обрабатывает POST /api/auth/refresh
// Возвращает 200 OK при успехе, иначе 400 invalid_input
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", "wrong JSON body")
		return
	}

	res, err := h.svc.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	transport.WriteJSON(w, http.StatusOK, toDTO(res))
}

// Logout обрабатывает POST /api/auth/refresh
// Возвращает 200 OK при успехе, иначе 400 invalid_input
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", "wrong JSON body")
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
		ExpiresIn:    res.ExpiresIn,
	}
}

// writeAuthError переводит ошибки сервиса в HTTP-ответы
// Соответствие ошибок и ответов:
//   - *auth.ValidationError       -> 400 invalid_input;
//   - auth.ErrLoginTaken          -> 409 login_taken;
//   - auth.ErrInvalidCredentials  -> 401 invalid_credentials;
//   - любая другая ошибка         -> 500 internal
func writeAuthError(w http.ResponseWriter, err error) {
	var ve *auth.ValidationError
	switch {
	case errors.As(err, &ve):
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", ve.Field+": "+ve.Message)
	case errors.Is(err, auth.ErrLoginTaken):
		transport.WriteError(w, http.StatusConflict, "login_taken", "login is already taken")
	case errors.Is(err, auth.ErrInvalidCredentials):
		transport.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "invalid login or password")
	case errors.Is(err, auth.ErrInvalidRefreshToken):
		transport.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "refresh token is invalid or expired")
	default:
		transport.WriteError(w, http.StatusInternalServerError, "internal", "internal server error")
	}
}
