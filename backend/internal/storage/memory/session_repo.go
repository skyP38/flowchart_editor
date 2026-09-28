package memory

import (
	"context"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

type MemorySessionRepo struct {
	mu     sync.RWMutex
	nextID atomic.Int64
	byID   map[int64]*domains.Session
	byHash map[string]int64
}

func NewMemorySessionRepo() *MemorySessionRepo {
	return &MemorySessionRepo{
		byID:   make(map[int64]*domains.Session),
		byHash: make(map[string]int64),
	}
}

// Create создает новую сессию
func (r *MemorySessionRepo) Create(ctx context.Context, s *domains.Session) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if _, exists := r.byHash[string(s.TokenHash)]; exists {
		return ErrSessionAlreadyExists
	}

	id := r.nextID.Add(1)
	cp := *s
	cp.ID = id
	if cp.CreatedAt.IsZero() {
		cp.CreatedAt = time.Now().UTC()
	}
	r.byID[id] = &cp
	r.byHash[cp.TokenHash] = id
	*s = cp
	return nil
}

// GetByHash возвращает копию сессии по хешу
func (r *MemorySessionRepo) GetByTokenHash(ctx context.Context, tokenHash string) (*domains.Session, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	id, ok := r.byHash[tokenHash]
	if !ok {
		return nil, ErrSessionNotFound
	}
	s := r.byID[id]
	cp := *s
	return &cp, nil
}

// GetByHash возвращает копию сессии по числовому идентификатору
func (r *MemorySessionRepo) GetByID(ctx context.Context, id int64) (*domains.Session, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	s, ok := r.byID[id]
	if !ok {
		return nil, ErrSessionNotFound
	}
	cp := *s
	return &cp, nil
}

// GetByHash возвращает список всех сессий пользователя по его числовому идентификатору
func (r *MemorySessionRepo) ListByUserID(ctx context.Context, userID int64) ([]*domains.Session, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	out := make([]*domains.Session, 0)
	for _, s := range r.byID {
		if s.UserID == userID {
			cp := *s
			out = append(out, &cp)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

func (r *MemorySessionRepo) Revoke(ctx context.Context, id int64, at time.Time) error {
	r.mu.Lock()
	defer r.mu.RUnlock()

	s, ok := r.byID[id]
	if !ok {
		return ErrSessionNotFound
	}
	if s.RevokedAt == nil {
		t := at
		s.RevokedAt = &t
	}
	return nil
}

func (r *MemorySessionRepo) RevokeAllExcept(ctx context.Context, userID int64, keepSessionID int64, at time.Time) error {
	r.mu.Lock()
	defer r.mu.RUnlock()

	for _, s := range r.byID {
		if s.UserID != userID || s.ID == keepSessionID {
			continue
		}

		if s.RevokedAt == nil {
			t := at
			s.RevokedAt = &t
		}

	}

	return nil

}
