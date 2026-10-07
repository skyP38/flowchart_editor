package memory

import (
	"context"
	"sync"
	"sync/atomic"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

// MemoryUserRepo - потокобезопасная реализация domains.UserRepository
//
//nolint:revive
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

// Create создает нового пользователя и присваивает ему ID через переданный указатель
// Если нормализованный логин занят, возвращает ErrUserAlreadyExists
func (r *MemoryUserRepo) Create(_ context.Context, u *domains.User) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	key := domains.NormalizeLogin(u.Login)
	if _, exists := r.byLogin[key]; exists {
		return domains.ErrUserAlreadyExists
	}

	id := r.nextID.Add(1)
	u.ID = id
	cp := *u
	if cp.CreatedAt.IsZero() {
		cp.CreatedAt = time.Now().UTC()
	}
	r.byID[cp.ID] = &cp
	r.byLogin[key] = &cp
	*u = cp
	return nil
}

// GetByID возвращает копию пользователя по по ID или ErrNotFound
func (r *MemoryUserRepo) GetByID(_ context.Context, id int64) (*domains.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	u, ok := r.byID[id]
	if !ok {
		return nil, domains.ErrNotFound
	}
	cp := *u
	return &cp, nil
}

// GetByLogin возвращает копию пользователя по логину или ErrNotFound
func (r *MemoryUserRepo) GetByLogin(_ context.Context, login string) (*domains.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	u, ok := r.byLogin[domains.NormalizeLogin(login)]
	if !ok {
		return nil, domains.ErrNotFound
	}
	cp := *u
	return &cp, nil
}
