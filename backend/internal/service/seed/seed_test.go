package seed_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
	"github.com/skyP38/flowchart_editor/backend/internal/service/seed"
	"github.com/skyP38/flowchart_editor/backend/internal/storage/memory"
)

// fakeUserRepo — минимальная реализация domains.UserRepository,
// позволяющая подменить поведение GetByLogin и Create.
// GetByID в seed.Admin не вызывается, поэтому возвращает ErrNotFound.
type fakeUserRepo struct {
	getByLoginFn func(ctx context.Context, login string) (*domains.User, error)
	createFn     func(ctx context.Context, u *domains.User) error
}

func (f *fakeUserRepo) Create(ctx context.Context, u *domains.User) error {
	return f.createFn(ctx, u)
}

func (f *fakeUserRepo) GetByID(_ context.Context, _ int64) (*domains.User, error) {
	return nil, domains.ErrNotFound
}

func (f *fakeUserRepo) GetByLogin(ctx context.Context, login string) (*domains.User, error) {
	return f.getByLoginFn(ctx, login)
}

// Compile-time проверка, что fake реализует интерфейс.
var _ domains.UserRepository = (*fakeUserRepo)(nil)

// --- Базовые сценарии (memory) ---

func TestAdmin_CreatesWhenMissing(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	ctx := context.Background()

	if err := seed.Admin(ctx, users, "admin", "secret", "pepper"); err != nil {
		t.Fatalf("seed: %v", err)
	}
	u, err := users.GetByLogin(ctx, "admin")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if u.Role != domains.RoleAdmin {
		t.Fatalf("role = %q, want admin", u.Role)
	}
	if !u.IsActive {
		t.Fatalf("admin must be active")
	}
}

func TestAdmin_Idempotent(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	ctx := context.Background()

	if err := seed.Admin(ctx, users, "admin", "secret", "pepper"); err != nil {
		t.Fatalf("first: %v", err)
	}
	if err := seed.Admin(ctx, users, "admin", "secret", "pepper"); err != nil {
		t.Fatalf("second: %v", err)
	}
}

func TestAdmin_LoginTakenByUser_Errors(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	ctx := context.Background()

	_ = users.Create(ctx, &domains.User{
		Login: "admin", PwdHash: "x", Uname: "not-admin",
		Role: domains.RoleUser, IsActive: true,
	})

	err := seed.Admin(ctx, users, "admin", "secret", "pepper")
	if err == nil {
		t.Fatalf("want error, got nil")
	}
	if !strings.Contains(err.Error(), "non-admin") {
		t.Fatalf("error should mention non-admin: %v", err)
	}
}

func TestAdmin_EmptyCreds_Skips(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	ctx := context.Background()

	if err := seed.Admin(ctx, users, "", "", "pepper"); err != nil {
		t.Fatalf("empty creds: %v", err)
	}
	if _, err := users.GetByLogin(ctx, "admin"); err == nil {
		t.Fatalf("user unexpectedly created")
	}
}

// --- Покрытие ветки lookup-error ---

// TestAdmin_LookupError — GetByLogin вернул ошибку, не являющуюся
// domains.ErrNotFound. Ошибка должна обернуться с префиксом "lookup",
// а Create — не вызываться.
func TestAdmin_LookupError(t *testing.T) {
	boom := errors.New("db down")
	createCalled := false
	users := &fakeUserRepo{
		getByLoginFn: func(_ context.Context, _ string) (*domains.User, error) {
			return nil, boom
		},
		createFn: func(_ context.Context, _ *domains.User) error {
			createCalled = true
			return nil
		},
	}

	err := seed.Admin(context.Background(), users, "admin", "secret", "pepper")
	if err == nil {
		t.Fatal("want error, got nil")
	}
	if !errors.Is(err, boom) {
		t.Fatalf("want wrapped boom, got %v", err)
	}
	if !strings.Contains(err.Error(), "lookup") {
		t.Fatalf("error should mention lookup: %v", err)
	}
	if createCalled {
		t.Fatal("Create must not be called after lookup error")
	}
}

// --- Покрытие ветки hash-error ---

// TestAdmin_HashError — bcrypt отклоняет пароли длиннее 72 байт
// (ErrPasswordTooLong в x/crypto). Это позволяет покрыть ветку
// "seed admin: hash password: ...". Если версия bcrypt не отклоняет
// длинные пароли — тест пропускается (нечего проверять).
func TestAdmin_HashError(t *testing.T) {
	users := memory.NewMemoryUserRepo()
	long := strings.Repeat("a", 100) // > 72 байт

	err := seed.Admin(context.Background(), users, "admin", long, "pepper")
	if err == nil {
		t.Skip("bcrypt does not reject long passwords in this version of x/crypto")
	}
	if !strings.Contains(err.Error(), "hash password") {
		t.Fatalf("error should mention hash password: %v", err)
	}
}

// --- Покрытие ветки create-error (не AlreadyExists) ---

// TestAdmin_CreateError — Create вернул ошибку, не являющуюся
// domains.ErrUserAlreadyExists. Ошибка оборачивается с префиксом "create".
func TestAdmin_CreateError(t *testing.T) {
	boom := errors.New("write failed")
	users := &fakeUserRepo{
		getByLoginFn: func(_ context.Context, _ string) (*domains.User, error) {
			return nil, domains.ErrNotFound
		},
		createFn: func(_ context.Context, _ *domains.User) error {
			return boom
		},
	}

	err := seed.Admin(context.Background(), users, "admin", "secret", "pepper")
	if err == nil {
		t.Fatal("want error, got nil")
	}
	if !errors.Is(err, boom) {
		t.Fatalf("want wrapped boom, got %v", err)
	}
	if !strings.Contains(err.Error(), "create") {
		t.Fatalf("error should mention create: %v", err)
	}
}

// --- Покрытие ветки create-race AlreadyExists ---

// TestAdmin_CreateRaceAlreadyExists — между GetByLogin (NotFound)
// и Create логин занял параллельный процесс. Seed должен вернуть nil:
// «кто-то уже создал, всё в порядке».
func TestAdmin_CreateRaceAlreadyExists(t *testing.T) {
	users := &fakeUserRepo{
		getByLoginFn: func(_ context.Context, _ string) (*domains.User, error) {
			return nil, domains.ErrNotFound
		},
		createFn: func(_ context.Context, _ *domains.User) error {
			return domains.ErrUserAlreadyExists
		},
	}

	err := seed.Admin(context.Background(), users, "admin", "secret", "pepper")
	if err != nil {
		t.Fatalf("race with existing user should be nil, got %v", err)
	}
}
