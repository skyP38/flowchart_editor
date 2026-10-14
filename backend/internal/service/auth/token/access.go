package token

import (
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

const Issuer = "backend"

var (
	ErrInvalidToken = errors.New("invalid access token")
	ErrExpiredToken = errors.New("access token expired")
)

// Claims - полезная нагрузка access-токена
type Claims struct {
	Role string `json:"role"`
	// RegisteredClaims — стандартные поля JWT: Subject,
	// Issuer, IssuedAt, ExpiresAt и др.
	jwt.RegisteredClaims
}

// AccessTokenManager выпускает и проверяет токены
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
			Subject:   fmt.Sprintf("%d", u.ID),
			ID:        strconv.FormatInt(sessionID, 10),
			Issuer:    Issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.ttl)),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
}

// ParseAccessToken проверяет подпись и срок действия токена и возвращает
// полезную нагрузку
func (m *AccessTokenManager) ParseAccessToken(token string) (*Claims, error) {
	claims := &Claims{}
	parsed, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
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
