package password

import "golang.org/x/crypto/bcrypt"

func HashPassword(plain, pepper string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(plain+pepper), bcrypt.DefaultCost)
	return string(b), err
}

func VerifyPassword(hash, plain, pepper string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain+pepper)) == nil
}
