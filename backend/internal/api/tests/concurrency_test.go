package api_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

// TestRegister_ConcurrentSameLogin - 20 параллельных регистраций одного логина:
// должен создаться ровно один пользователь, остальные получают 409
func TestRegister_ConcurrentSameLogin(t *testing.T) {
	env := setupEnv(t, setupOpts{})

	const n = 20
	body, _ := json.Marshal(map[string]string{
		"login": "race", "uname": "R", "password": "secret123",
	})

	var wg sync.WaitGroup
	codes := make([]int, n)
	for i := range n {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			req := httptest.NewRequest(http.MethodPost, "/api/auth/register", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			env.handler.ServeHTTP(rec, req)
			codes[idx] = rec.Code
		}(i)
	}
	wg.Wait()

	created, conflict := 0, 0
	for _, c := range codes {
		switch c {
		case http.StatusCreated:
			created++
		case http.StatusConflict:
			conflict++
		}
	}
	if created != 1 {
		t.Fatalf("created=%d, want 1 (codes=%v)", created, codes)
	}
	if conflict != n-1 {
		t.Fatalf("conflict=%d, want %d (codes=%v)", conflict, n-1, codes)
	}
}

// TestLogin_Concurrent - 20 параллельных логинов одного пользователя должны все вернуть 200
func TestLogin_Concurrent(t *testing.T) {
	env := setupEnv(t, setupOpts{})
	_, _ = env.register(t, "alice", "Alice", "secret123")

	const n = 20
	body, _ := json.Marshal(map[string]string{
		"login": "alice", "password": "secret123",
	})

	var wg sync.WaitGroup
	codes := make([]int, n)
	for i := range n {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			req := httptest.NewRequest(http.MethodPost, "/api/auth/login", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			env.handler.ServeHTTP(rec, req)
			codes[idx] = rec.Code
		}(i)
	}
	wg.Wait()

	for i, c := range codes {
		if c != http.StatusOK {
			t.Fatalf("goroutine %d: status %d, want 200 (codes=%v)", i, c, codes)
		}
	}
}
