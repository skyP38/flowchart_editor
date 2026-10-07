package ratelimit

import "time"

// Policy описывает параметры ограничения для одного профиля
type Policy struct {
	// сколько неудачных попыток допустимо до блокировки
	MaxAttempts int
	// окно, в котором считаются неудачи
	Window time.Duration
	// базовая длительность блокировки
	BlockDuration time.Duration
	// потолок множителя
	MaxBlockCount int
	// через сколько после окончания блокировки забывается счетчик блокировок
	DecayWindow time.Duration
}
