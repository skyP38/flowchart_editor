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
func (h *AuthHandler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/auth/register", h.Register)
	mux.HandleFunc("POST /api/auth/login", h.Login)
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

// userDTO - представление пользователя в ответах
type userDTO struct {
	ID    int64  `json:"id"`
	Login string `json:"login"`
	Uname string `json:"uname"`
	Role  string `json:"role"`
}

// authResponse - ответ на успешные попытки Register/Login
type authResponse struct {
	User        userDTO `json:"user"`
	AccessToken string  `json:"access_token"`
	ExpiresIn   int     `json:"expires_in"`
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
		transport.WriteError(w, http.StatusBadRequest, "invalid_input", "malformed JSON body")
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

// toDTO преобразует AuthResult в authResponse
func toDTO(res *auth.AuthResult) authResponse {
	return authResponse{
		User: userDTO{
			ID: res.User.ID, Login: res.User.Login,
			Uname: res.User.Uname, Role: res.User.Role,
		},
		AccessToken: res.AccessToken,
		ExpiresIn:   res.ExpiresIn,
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
	default:
		transport.WriteError(w, http.StatusInternalServerError, "internal", "internal server error")
	}
}
