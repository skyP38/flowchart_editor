package token

import (
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

// Issuer - значение поля iss в access-токенах
// Используется для проверки, что токен выпущен именно этим сервисом
const Issuer = "backend"

var (
	ErrInvalidToken = errors.New("invalid access token")
	ErrExpiredToken = errors.New("access token expired")
)

// Claims - полезная нагрузка access-токена
type Claims struct {
	Role string `json:"role"`
	// RegisteredClaims - стандартные поля JWT: Subject,
	// Issuer, IssuedAt, ExpiresAt и др.
	jwt.RegisteredClaims
}

// AccessTokenManager выпускает и проверяет токены через HS256
type AccessTokenManager struct {
	secret []byte
	ttl    time.Duration
}

func NewAccessTokenManager(secret string, ttl time.Duration) *AccessTokenManager {
	return &AccessTokenManager{secret: []byte(secret), ttl: ttl}
}

// GenerateAccessToken возвращает подписанную строку или ошибку подписи
func (m *AccessTokenManager) GenerateAccessToken(u *domains.User, sessionID int64) (string, error) {
	now := time.Now().UTC()
	claims := Claims{
		Role: u.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   fmt.Sprintf("%d", u.ID),          // ID пользователя
			ID:        strconv.FormatInt(sessionID, 10), // ID сессии
			Issuer:    Issuer,                           // "backend"
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.ttl)),
		},
	}
	// HMAC-SHA256 - симметричный алгоритм: один секрет используется и для подписи, и для проверки
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
}

// ParseAccessToken проверяет подпись и срок действия токена и возвращает полезную нагрузку
func (m *AccessTokenManager) ParseAccessToken(token string) (*Claims, error) {
	claims := &Claims{}
	parsed, err := jwt.ParseWithClaims(token, claims, func(_ *jwt.Token) (any, error) {
		return m.secret, nil
	}, jwt.WithIssuer(Issuer), jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrExpiredToken
		}
		return nil, ErrInvalidToken
	}
	if !parsed.Valid {
		return nil, ErrInvalidToken
	}
	return claims, nil
}
