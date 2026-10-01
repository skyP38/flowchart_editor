package token

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
)

const refreshTokenBytes = 32

func GenerateRefreshToken() (plain string, hash string, err error) {
	buf := make([]byte, refreshTokenBytes)
	if _, err = rand.Read(buf); err != nil {
		return "", "", err
	}
	plain = base64.RawURLEncoding.EncodeToString(buf)
	hash = HashRefreshToken(plain)
	return plain, hash, nil
}

func HashRefreshToken(plain string) string {
	sum := sha256.Sum256([]byte(plain))
	return hex.EncodeToString(sum[:])
}
