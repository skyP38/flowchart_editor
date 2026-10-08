// Package password хеширует и проверяет пароли пользователей через bcrypt
package password

import "golang.org/x/crypto/bcrypt"

// HashPassword хеширует пароль с дополнительным секретом приложения (pepper)
func HashPassword(plain, pepper string) (string, error) {
	// соль генерируется внутри bcrypt
	b, err := bcrypt.GenerateFromPassword([]byte(plain+pepper), bcrypt.DefaultCost)
	return string(b), err
}

// VerifyPassword проверяет, соответствует ли пароль хешу
func VerifyPassword(hash, plain, pepper string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain+pepper)) == nil
}
