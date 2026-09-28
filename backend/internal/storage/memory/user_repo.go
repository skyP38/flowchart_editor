package memory

import (
	"context"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

// MemoryUserRepo - потокобезопасная реализация domains.UserRepository
type MemoryUserRepo struct {
	mu      sync.RWMutex
	nextID  atomic.Int64
	byID    map[int64]*domains.User
	byLogin map[string]*domains.User
}

func NewMemoryUserRepo() *MemoryUserRepo {
	return &MemoryUserRepo{
		byID:    make(map[int64]*domains.User),
		byLogin: make(map[string]*domains.User),
	}
}

// Create создает нового пользователя
func (r *MemoryUserRepo) Create(ctx context.Context, u *domains.User) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	key := strings.ToLower(u.Login)
	if _, exists := r.byLogin[key]; exists {
		return ErrUserAlreadyExists
	}

	id := r.nextID.Add(1)
	cp := *u
	cp.ID = id

	r.byID[u.ID] = &cp
	r.byLogin[key] = &cp
	return nil
}

// GetByID возвращает копию пользователя по числовую идентификатору
func (r *MemoryUserRepo) GetByID(ctx context.Context, id int64) (*domains.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	u, ok := r.byID[id]
	if !ok {
		return nil, ErrNotFound
	}
	cp := *u
	return &cp, nil
}

// GetByLogin возвращает копию пользователя по логину
func (r *MemoryUserRepo) GetByLogin(ctx context.Context, login string) (*domains.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	u, ok := r.byLogin[strings.ToLower(login)]
	if !ok {
		return nil, ErrNotFound
	}
	cp := *u
	return &cp, nil
}
