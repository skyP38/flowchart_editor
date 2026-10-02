package memory

import (
	"context"
	"errors"
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

// GetByTokenHash возвращает копию сессии по хешу
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

// GetByID возвращает копию сессии по числовому идентификатору
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

// ListByUserID возвращает список всех сессий пользователя по его числовому идентификатору
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
	defer r.mu.Unlock()

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
	defer r.mu.Unlock()

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

func (r *MemorySessionRepo) RemoveExpired(ctx context.Context, retention time.Duration) (int, error) {
	if retention <= 0 {
		return 0, errors.New("retention must be positive")
	}

	select {
	case <-ctx.Done():
		return 0, ctx.Err()
	default:
	}

	now := time.Now().UTC()

	r.mu.Lock()
	defer r.mu.Unlock()

	type pair struct {
		id   int64
		hash string
	}

	toDelete := make([]pair, 0)
	for id, s := range r.byID {
		if s == nil {
			continue
		}
		deadline := s.ExpiresAt
		if s.RevokedAt != nil && s.RevokedAt.After(deadline) {
			deadline = *s.RevokedAt
		}
		if now.After(deadline.Add(retention)) {
			toDelete = append(toDelete, pair{id, s.TokenHash})
		}
	}

	for _, p := range toDelete {
		delete(r.byHash, p.hash)
		delete(r.byID, p.id)
	}
	return len(toDelete), nil
}
