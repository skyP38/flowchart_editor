package auth

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/auth/token"
	"github.com/skyP38/flowchart_editor/backend/internal/service/password"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
)

// loginRe - регулярное выражение для валидации логина
var loginRe = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)

// Service - сервис аутентификации
type Service struct {
	users     domains.UserRepository
	access    *token.AccessTokenManager
	pepper    string
	accessTTL time.Duration
}

func NewService(
	users domains.UserRepository,
	access *token.AccessTokenManager,
	pepper string,
	accessTTL time.Duration,
) *Service {
	return &Service{
		users:     users,
		access:    access,
		pepper:    pepper,
		accessTTL: accessTTL,
	}
}

// RegisterInput данные для регистрации
type RegisterInput struct {
	Login    string
	Uname    string
	Password string
}

// LoginInput  данные для логина
type LoginInput struct {
	Login    string
	Password string
}

// AuthResult - результат успешной регистрации или логина
type AuthResult struct {
	User        *domains.User
	AccessToken string
	ExpiresIn   int
}

// Register создает нового пользователя и сразу выпускает ему access-токен
func (s *Service) Register(ctx context.Context, in RegisterInput) (*AuthResult, error) {
	login := strings.TrimSpace(in.Login)
	uname := strings.TrimSpace(in.Uname)

	if !loginRe.MatchString(login) {
		return nil, &ValidationError{
			Field:   "login",
			Message: "must be 3-32 chars of [a-zA-Z0-9_]",
		}
	}
	if l := len([]rune(uname)); l < 1 || l > 200 {
		return nil, &ValidationError{
			Field:   "uname",
			Message: "must be 1-200 characters",
		}
	}
	if err := validatePassword(in.Password); err != nil {
		return nil, err
	}

	if existing, err := s.users.GetByLogin(ctx, login); err == nil && existing != nil {
		return nil, ErrLoginTaken
	}

	pwdHash, err := password.HashPassword(in.Password, s.pepper)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	u := &domains.User{
		Login:     login,
		PwdHash:   pwdHash,
		Uname:     uname,
		Role:      domains.RoleUser,
		CreatedAt: now,
		IsActive:  true,
	}
	if err := s.users.Create(ctx, u); err != nil {
		if errors.Is(err, memory.ErrUserAlreadyExists) {
			return nil, ErrLoginTaken
		}
		return nil, err
	}

	return s.issueAccess(u)
}

// Login проверяет учетные данные и выпускает access-токен
func (s *Service) Login(ctx context.Context, in LoginInput) (*AuthResult, error) {
	login := strings.TrimSpace(in.Login)
	if login == "" || in.Password == "" {
		return nil, ErrInvalidCredentials
	}

	u, err := s.users.GetByLogin(ctx, login)
	if err != nil || u == nil || !u.IsActive {
		return nil, ErrInvalidCredentials
	}
	if !password.VerifyPassword(u.PwdHash, in.Password, s.pepper) {
		return nil, ErrInvalidCredentials
	}

	return s.issueAccess(u)
}

// issueAccess выпускает access-токен для пользователя и формирует AuthResult
func (s *Service) issueAccess(u *domains.User) (*AuthResult, error) {
	tok, err := s.access.GenerateAccessToken(u)
	if err != nil {
		return nil, err
	}
	return &AuthResult{
		User:        u,
		AccessToken: tok,
		ExpiresIn:   int(s.accessTTL.Seconds()),
	}, nil
}

// validatePassword проверяет требования к паролю
// Требования:
//   - длина не менее 8 байт;
//   - содержит хотя бы одну латинскую букву (a–z или A–Z);
//   - содержит хотя бы одну цифру (0–9)
func validatePassword(p string) error {
	if len(p) < 8 {
		return &ValidationError{Field: "password", Message: "must be at least 8 characters"}
	}
	var hasLetter, hasDigit bool
	for _, r := range p {
		switch {
		case (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z'):
			hasLetter = true
		case r >= '0' && r <= '9':
			hasDigit = true
		}
	}
	if !hasLetter || !hasDigit {
		return &ValidationError{Field: "password", Message: "must contain at least one letter and one digit"}
	}
	return nil
}
