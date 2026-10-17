package auth

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newStore(t *testing.T) (*Store, string) {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "cfg")
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	return s, dir
}

func TestPairHappyPathIsOneTime(t *testing.T) {
	s, _ := newStore(t)
	code, _, err := s.NewCode()
	if err != nil {
		t.Fatal(err)
	}
	if len(code) != 9 || code[4] != '-' {
		t.Fatalf("code format: %q", code)
	}
	// Lower case and no dash must still work (typed on a phone).
	token, err := s.Pair(strings.ToLower(strings.ReplaceAll(code, "-", " ")), "pixel")
	if err != nil {
		t.Fatalf("pair: %v", err)
	}
	if !s.Verify(token) {
		t.Fatal("fresh token should verify")
	}
	if s.Verify(token + "x") {
		t.Fatal("altered token must not verify")
	}
	if _, err := s.Pair(code, "again"); err != ErrBadCode {
		t.Fatalf("code reuse should fail with ErrBadCode, got %v", err)
	}
}

func TestPairWithoutCodeFails(t *testing.T) {
	s, _ := newStore(t)
	if _, err := s.Pair("AAAA-AAAA", "x"); err != ErrBadCode {
		t.Fatalf("got %v", err)
	}
}

func TestCodeExpires(t *testing.T) {
	s, _ := newStore(t)
	now := time.Now()
	s.now = func() time.Time { return now }
	code, _, _ := s.NewCode()
	s.now = func() time.Time { return now.Add(codeTTL + time.Second) }
	if _, err := s.Pair(code, "late"); err != ErrBadCode {
		t.Fatalf("expired code should fail, got %v", err)
	}
}

func TestLockoutAfterFiveWrongCodes(t *testing.T) {
	s, _ := newStore(t)
	now := time.Now()
	s.now = func() time.Time { return now }
	code, _, _ := s.NewCode()
	var err error
	for i := 0; i < maxBadAttempts; i++ {
		_, err = s.Pair("WRONG-000", "x")
	}
	if err != ErrLocked {
		t.Fatalf("5th wrong code should lock, got %v", err)
	}
	if _, err := s.Pair(code, "x"); err != ErrLocked {
		t.Fatalf("even the right code must fail while locked, got %v", err)
	}
	s.now = func() time.Time { return now.Add(lockoutFor + time.Second) }
	if _, err := s.Pair(code, "x"); err != nil {
		t.Fatalf("after lockout the right code should work: %v", err)
	}
}

func TestPersistenceAndFileSafety(t *testing.T) {
	s, dir := newStore(t)
	code, _, _ := s.NewCode()
	token, err := s.Pair(code, "phone")
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, pairedFile))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), token) {
		t.Fatal("paired.json must not contain the raw token")
	}
	if info, _ := os.Stat(filepath.Join(dir, pairedFile)); info.Mode().Perm() != 0o600 {
		t.Fatalf("paired.json mode = %v, want 0600", info.Mode().Perm())
	}
	if info, _ := os.Stat(dir); info.Mode().Perm() != 0o700 {
		t.Fatalf("config dir mode = %v, want 0700", info.Mode().Perm())
	}
	s2, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !s2.Verify(token) {
		t.Fatal("token should survive a restart")
	}
}

func TestRevokeFromAnotherProcessTakesEffect(t *testing.T) {
	s, dir := newStore(t)
	code, _, _ := s.NewCode()
	token, _ := s.Pair(code, "lost-phone")
	if !s.Verify(token) {
		t.Fatal("precondition")
	}
	time.Sleep(20 * time.Millisecond) // file mtime must differ from the load above
	other, _ := Open(dir)             // stands in for `i30ltz-node revoke` run separately
	if n, err := other.Revoke("lost-phone"); err != nil || n != 1 {
		t.Fatalf("revoke: n=%d err=%v", n, err)
	}
	if s.Verify(token) {
		t.Fatal("running daemon must notice the revoke")
	}
}

func TestMiddleware(t *testing.T) {
	s, _ := newStore(t)
	code, _, _ := s.NewCode()
	token, _ := s.Pair(code, "p")
	h := s.Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(204) }))
	cases := []struct {
		header string
		want   int
	}{{"", 401}, {"Bearer nope", 401}, {"Basic " + token, 401}, {"Bearer " + token, 204}, {"bearer " + token, 204}}
	for _, c := range cases {
		req := httptest.NewRequest("GET", "/", nil)
		if c.header != "" {
			req.Header.Set("Authorization", c.header)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Errorf("header %q: got %d want %d", c.header, rec.Code, c.want)
		}
	}
}

func TestIsLoopback(t *testing.T) {
	cases := []struct {
		addr, xff string
		want      bool
	}{{"127.0.0.1:5000", "", true}, {"[::1]:5000", "", true}, {"100.82.1.20:5000", "", false},
		{"127.0.0.1:5000", "100.82.1.20", false}, {"garbage", "", false}}
	for _, c := range cases {
		r := httptest.NewRequest("GET", "/", nil)
		r.RemoteAddr = c.addr
		if c.xff != "" {
			r.Header.Set("X-Forwarded-For", c.xff)
		}
		if got := IsLoopback(r); got != c.want {
			t.Errorf("%q xff=%q: got %v want %v", c.addr, c.xff, got, c.want)
		}
	}
}
