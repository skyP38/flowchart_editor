package config

import (
	"fmt"
	"os"
	"time"
)

// Config содержит конфигурацию, которая загружается из переменных окружения
type Config struct {
	// Порт, на котором слушает сервер
	// По умолчанию: 8080
	AppPort string
	// Ключ для подписи токенов
	// По умолчанию: change-me
	JWTSecret string
	// Дополнительная секретная строка(перец), добавляемая к паролю перед хешированием
	// По умолчанию: change-me
	PasswordPepper string
	// Время жизни access-токена
	// По умолчанию: 15 минут
	AccessTokenTTL time.Duration
	// Время жизни refresh-токена
	// По умолчанию: 7 дней
	RefreshTokenTTL time.Duration
	// Логин администратора
	// По умолчанию: admin
	AdminLogin string
	// Пароль администратора
	// По умолчанию: admin
	AdminPassword string
}

// Load читает информацию из переменных окружения и возвращает заполненный Config
// Если в ACCESS_TOKEN_TTL или REFRESH_TOKEN_TTL содержится некорректная длительность
// будет возвращена ошибка с указанием имени переменной
func Load() (*Config, error) {
	accessTTL, err := getDuration("ACCESS_TOKEN_TTL", 15*time.Minute)
	if err != nil {
		return nil, err
	}
	refreshTTL, err := getDuration("REFRESH_TOKEN_TTL", 7*24*time.Hour)
	if err != nil {
		return nil, err
	}

	return &Config{
		AppPort:         getEnv("APP_PORT", "8080"),
		JWTSecret:       getEnv("JWT_SECRET", "change-me"),
		PasswordPepper:  getEnv("PASSWORD_PEPPER", "change-me"),
		AccessTokenTTL:  accessTTL,
		RefreshTokenTTL: refreshTTL,
		AdminLogin:      getEnv("ADMIN_LOGIN", "admin"),
		AdminPassword:   getEnv("ADMIN_PASSWORD", "admin"),
	}, nil
}

// getEnv возвращает значение переменной окружения key
// Если переменная не задана или пуста, возвращается def
func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// getDuration читает переменную окружения key и парсит её как time.Duration
// Если значение задано, но не может быть разобрано time.ParseDuration,
// возвращается ошибка вида "invalid KEY: ...".
func getDuration(key string, def time.Duration) (time.Duration, error) {
	v := os.Getenv(key)
	if v == "" {
		return def, nil
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return 0, fmt.Errorf("invalid %s: %w", key, err)
	}
	return d, nil
}
