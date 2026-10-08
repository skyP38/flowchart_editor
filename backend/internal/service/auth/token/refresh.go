// Package token выпускает и проверяет access- и refresh-токены
package token

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
)

// refreshTokenBytes - размер refresh-токена в байтах
const refreshTokenBytes = 32

// GenerateRefreshToken создаёт новый refresh-токен.
// Возвращает:
//   - plain - токен для клиента (base64url, 43 символа)
//   - hash - SHA-256 хеш для хранения в сессии;
//   - err - ошибка генерации случайных байт
func GenerateRefreshToken() (plain string, hash string, err error) {
	buf := make([]byte, refreshTokenBytes)
	if _, err = rand.Read(buf); err != nil {
		return "", "", err
	}
	plain = base64.RawURLEncoding.EncodeToString(buf)
	hash = HashRefreshToken(plain)
	return plain, hash, nil
}

// HashRefreshToken возвращает SHA-256 хеш refresh-токена в hex-виде
func HashRefreshToken(plain string) string {
	sum := sha256.Sum256([]byte(plain))
	return hex.EncodeToString(sum[:])
}
