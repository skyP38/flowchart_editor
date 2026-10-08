// Package config загружает конфигурацию приложения из переменных окружения
package config

import (
	"fmt"
	"os"
	"strconv"
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

	// Максимальное число неудачных попыток входа до блокировки
	// По умолчанию: 5
	RatelimitLoginMaxAttempts int
	// Окно, в котором считаются неудачные попытки входа
	// По умолчанию: 15 минут
	RatelimitLoginWindow time.Duration
	// Базовая длительность блокировки
	// По умолчанию: 15 минут
	RatelimitLoginBlockDuration time.Duration
	// Потолок множителя для эскалации длительности блокировки
	// По умолчанию: 4
	RatelimitLoginMaxBlockCount int
	// Через сколько после окончания блокировки забывается счётчик блокировок
	// По умолчанию: 24 часа
	RatelimitLoginDecayWindow time.Duration
	// Интервал запуска очистки просроченных записей лимитера
	// По умолчанию: 5 минут
	RatelimitCleanupInterval time.Duration

	SessionCleanupInterval time.Duration
	SessionRetention       time.Duration
}

// Load читает информацию из переменных окружения и возвращает заполненный Config
// Если в ACCESS_TOKEN_TTL, REFRESH_TOKEN_TTL, LOGIN_WINDOW, LOGIN_BLOCK_DURATION,
// LOGIN_DECAY_WINDOW или RATELIMIT_CLEANUP_INTERVAL содержится некорректная
// длительность, будет возвращена ошибка с указанием имени переменной.
// Аналогично для целочисленных переменных LOGIN_MAX_ATTEMPTS и LOGIN_MAX_BLOCK_COUNT.
func Load() (*Config, error) {
	accessTTL, err := getDuration("ACCESS_TOKEN_TTL", time.Minute)
	if err != nil {
		return nil, err
	}
	refreshTTL, err := getDuration("REFRESH_TOKEN_TTL", 7*24*time.Hour)
	if err != nil {
		return nil, err
	}

	loginWindow, err := getDuration("LOGIN_WINDOW", 15*time.Minute)
	if err != nil {
		return nil, err
	}
	loginBlockDuration, err := getDuration("LOGIN_BLOCK_DURATION", 15*time.Minute)
	if err != nil {
		return nil, err
	}
	loginDecayWindow, err := getDuration("LOGIN_DECAY_WINDOW", 24*time.Hour)
	if err != nil {
		return nil, err
	}
	cleanupInterval, err := getDuration("RATELIMIT_CLEANUP_INTERVAL", 5*time.Minute)
	if err != nil {
		return nil, err
	}

	loginMaxAttempts, err := getInt("LOGIN_MAX_ATTEMPTS", 5)
	if err != nil {
		return nil, err
	}
	loginMaxBlockCount, err := getInt("LOGIN_MAX_BLOCK_COUNT", 4)
	if err != nil {
		return nil, err
	}

	sessionCleanupInterval, err := getDuration("SESSION_CLEANUP_INTERVAL", 5*time.Minute)
	if err != nil {
		return nil, err
	}
	sessionRetention, err := getDuration("SESSION_RETENTION", 24*time.Hour)
	if err != nil {
		return nil, err
	}

	return &Config{
		AppPort:                     getEnv("APP_PORT", "8080"),
		JWTSecret:                   getEnv("JWT_SECRET", "change-me"),
		PasswordPepper:              getEnv("PASSWORD_PEPPER", "change-me"),
		AccessTokenTTL:              accessTTL,
		RefreshTokenTTL:             refreshTTL,
		AdminLogin:                  getEnv("ADMIN_LOGIN", "admin"),
		AdminPassword:               getEnv("ADMIN_PASSWORD", "admin"),
		RatelimitLoginMaxAttempts:   loginMaxAttempts,
		RatelimitLoginWindow:        loginWindow,
		RatelimitLoginBlockDuration: loginBlockDuration,
		RatelimitLoginMaxBlockCount: loginMaxBlockCount,
		RatelimitLoginDecayWindow:   loginDecayWindow,
		RatelimitCleanupInterval:    cleanupInterval,
		SessionCleanupInterval:      sessionCleanupInterval,
		SessionRetention:            sessionRetention,
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

// getInt читает переменную окружения key и парсит её как int
// Если значение задано, но не может быть разобрано strconv.Atoi,
// возвращается ошибка вида "invalid KEY: ...".
func getInt(key string, def int) (int, error) {
	v := os.Getenv(key)
	if v == "" {
		return def, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return 0, fmt.Errorf("invalid %s: %w", key, err)
	}
	return n, nil
}
