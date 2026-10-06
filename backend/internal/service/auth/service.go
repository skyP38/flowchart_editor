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
	"golang.org/x/crypto/bcrypt"
)

var dummyHash = func() []byte {
	h, err := bcrypt.GenerateFromPassword([]byte("dummy-password-for-timing"), bcrypt.DefaultCost)
	if err != nil {
		panic(err)
	}
	return h
}()

// loginRe - регулярное выражение для валидации логина
var loginRe = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)

// Service - сервис аутентификации
type Service struct {
	users      domains.UserRepository
	sessions   domains.SessionRepository
	access     *token.AccessTokenManager
	pepper     string
	accessTTL  time.Duration
	refreshTTL time.Duration
	reserved   map[string]struct{}
}

func NewService(
	users domains.UserRepository,
	sessions domains.SessionRepository,
	access *token.AccessTokenManager,
	pepper string,
	accessTTL, refreshTTL time.Duration,
	reservedLogins []string,
) *Service {
	reserved := make(map[string]struct{}, len(reservedLogins))
	for _, l := range reservedLogins {
		reserved[domains.NormalizeLogin(l)] = struct{}{}
	}
	return &Service{
		users:      users,
		sessions:   sessions,
		access:     access,
		pepper:     pepper,
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
		reserved:   reserved,
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
	User         *domains.User
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
}

// Register создает нового пользователя и сразу выпускает ему access-токен
func (s *Service) Register(ctx context.Context, in RegisterInput) (*AuthResult, error) {
	login := domains.NormalizeLogin(in.Login)
	uname := strings.TrimSpace(in.Uname)

	verrs := NewValidationErrors()

	if !loginRe.MatchString(login) {
		verrs.Add("login", "must be 3-32 chars of [a-zA-Z0-9_]")
	} else if _, isReserved := s.reserved[domains.NormalizeLogin(in.Login)]; isReserved {
		verrs.Add("login", "this login is reserved")
	}

	if l := len([]rune(uname)); l < 1 || l > 200 {
		verrs.Add("uname", "must be 1-200 characters")
	}
	if err := validatePassword(in.Password); err != nil {
		var ve *ValidationError
		if errors.As(err, &ve) {
			verrs.Add(ve.Field, ve.Message)
		} else {
			verrs.Add("password", "invalid password")
		}
	}

	if verrs.HasAny() {
		return nil, verrs
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
		if errors.Is(err, domains.ErrUserAlreadyExists) {
			return nil, ErrLoginTaken
		}
		return nil, err
	}

	return s.issueTokens(ctx, u)
}

// Login проверяет учетные данные и выпускает access-токен
func (s *Service) Login(ctx context.Context, in LoginInput) (*AuthResult, error) {
	login := domains.NormalizeLogin(in.Login)
	if login == "" || in.Password == "" {
		return nil, ErrInvalidCredentials
	}

	u, err := s.users.GetByLogin(ctx, login)
	if err != nil || u == nil || !u.IsActive {
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(in.Password+s.pepper))
		return nil, ErrInvalidCredentials
	}
	if !password.VerifyPassword(u.PwdHash, in.Password, s.pepper) {
		return nil, ErrInvalidCredentials
	}

	return s.issueTokens(ctx, u)
}

// Refresh обновляет access-токен
func (s *Service) Refresh(ctx context.Context, refreshToken string) (*AuthResult, error) {
	if refreshToken == "" {
		return nil, ErrInvalidRefreshToken
	}
	hash := token.HashRefreshToken(refreshToken)
	sess, err := s.sessions.GetByTokenHash(ctx, hash)
	if err != nil {
		return nil, ErrInvalidRefreshToken
	}

	now := time.Now().UTC()
	if !sess.IsActive(now) {
		if sess.RevokedAt != nil {
			_ = s.sessions.RevokeAllExcept(ctx, sess.UserID, 0, now)
		}
		return nil, ErrInvalidRefreshToken
	}

	u, err := s.users.GetByID(ctx, sess.UserID)
	if err != nil || u == nil || !u.IsActive {
		return nil, ErrInvalidRefreshToken
	}

	if err := s.sessions.Revoke(ctx, sess.ID, now); err != nil {
		return nil, err
	}
	return s.issueTokens(ctx, u)
}

// Logout пользователь выходит из системы
func (s *Service) Logout(ctx context.Context, refreshToken string) error {
	if refreshToken == "" {
		return nil
	}
	sess, err := s.sessions.GetByTokenHash(ctx, token.HashRefreshToken(refreshToken))
	if err != nil {
		return nil
	}
	return s.sessions.Revoke(ctx, sess.ID, time.Now().UTC())
}

// GetUser - для GET /api/auth/me
func (s *Service) GetUser(ctx context.Context, id int64) (*domains.User, error) {
	u, err := s.users.GetByID(ctx, id)
	if err != nil || u == nil || !u.IsActive {
		return nil, ErrInvalidCredentials
	}
	return u, nil
}

// ListSessions - для GET /api/sessions
func (s *Service) ListSessions(ctx context.Context, userID int64) ([]*domains.Session, error) {
	return s.sessions.ListByUserID(ctx, userID)
}

// RevokeSession - для DELETE /api/sessions/{id}
func (s *Service) RevokeSession(ctx context.Context, userID, sessionID int64) error {
	sess, err := s.sessions.GetByID(ctx, sessionID)
	if err != nil || sess.UserID != userID {
		return ErrSessionNotFound
	}
	return s.sessions.Revoke(ctx, sessionID, time.Now().UTC())
}

// RevokeAllSessions - для DELETE /api/sessions
// keepID - текущая
func (s *Service) RevokeAllSessions(ctx context.Context, userID, keepID int64) error {
	return s.sessions.RevokeAllExcept(ctx, userID, keepID, time.Now().UTC())
}

// issueTokens выпускает access-токен для пользователя и формирует AuthResult
func (s *Service) issueTokens(ctx context.Context, u *domains.User) (*AuthResult, error) {
	plain, hash, err := token.GenerateRefreshToken()
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()
	sess := &domains.Session{
		UserID:    u.ID,
		TokenHash: hash,
		CreatedAt: now,
		ExpiresAt: now.Add(s.refreshTTL),
	}
	if err := s.sessions.Create(ctx, sess); err != nil {
		return nil, err
	}

	accessTok, err := s.access.GenerateAccessToken(u, sess.ID)
	if err != nil {
		return nil, err
	}

	return &AuthResult{
		User:         u,
		AccessToken:  accessTok,
		RefreshToken: plain,
		ExpiresIn:    int(s.accessTTL.Seconds()),
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
