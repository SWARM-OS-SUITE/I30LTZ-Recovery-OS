// Package auth handles device pairing and bearer-token checks for the node agent.
//
// A phone gets a token by trading a one-time pairing code that an operator
// generates on the node itself (loopback only). Only SHA-256 hashes of tokens
// are stored, so a copy of the config directory does not reveal a usable token.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	codeTTL        = 10 * time.Minute
	maxBadAttempts = 5
	lockoutFor     = 60 * time.Second
	// No 0/O/1/I/L so a code read off a screen cannot be mistyped.
	codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	codeLen      = 8
	pairedFile   = "paired.json"
)

var (
	ErrBadCode = errors.New("pairing code is wrong or expired")
	ErrLocked  = errors.New("too many wrong codes; pairing is locked for a minute")
)

// Device is one paired phone. Hash is the hex SHA-256 of its token.
type Device struct {
	Label     string    `json:"label"`
	Hash      string    `json:"hash"`
	CreatedAt time.Time `json:"created_at"`
}

// Store keeps paired devices on disk (mode 0600) and the single active pairing code in memory.
type Store struct {
	mu          sync.Mutex
	dir         string
	devices     []Device
	loadedMod   time.Time
	code        string
	codeExpires time.Time
	bad         int
	lockedUntil time.Time
	now         func() time.Time
}

// Open creates dir (mode 0700) if needed and loads any previously paired devices.
func Open(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	s := &Store{dir: dir, now: time.Now}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s, s.reloadLocked(true)
}

func (s *Store) path() string { return filepath.Join(s.dir, pairedFile) }

// reloadLocked re-reads the file when it changed, so `revoke` run from another
// process takes effect on the running daemon without a restart.
func (s *Store) reloadLocked(force bool) error {
	info, err := os.Stat(s.path())
	if errors.Is(err, os.ErrNotExist) {
		s.devices, s.loadedMod = nil, time.Time{}
		return nil
	}
	if err != nil {
		return err
	}
	if !force && info.ModTime().Equal(s.loadedMod) {
		return nil
	}
	raw, err := os.ReadFile(s.path())
	if err != nil {
		return err
	}
	var devices []Device
	if err := json.Unmarshal(raw, &devices); err != nil {
		return err
	}
	s.devices, s.loadedMod = devices, info.ModTime()
	return nil
}

func (s *Store) saveLocked() error {
	raw, err := json.MarshalIndent(s.devices, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path() + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, s.path()); err != nil {
		return err
	}
	if info, err := os.Stat(s.path()); err == nil {
		s.loadedMod = info.ModTime()
	}
	return nil
}

func randomString(alphabet string, n int) (string, error) {
	out := make([]byte, n)
	max := big.NewInt(int64(len(alphabet)))
	for i := range out {
		v, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		out[i] = alphabet[v.Int64()]
	}
	return string(out), nil
}

// NewCode makes a fresh one-time pairing code, replacing any earlier one.
func (s *Store) NewCode() (code string, valid time.Duration, err error) {
	raw, err := randomString(codeAlphabet, codeLen)
	if err != nil {
		return "", 0, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.code = raw
	s.codeExpires = s.now().Add(codeTTL)
	return raw[:4] + "-" + raw[4:], codeTTL, nil
}

func normalizeCode(c string) string {
	c = strings.ToUpper(strings.TrimSpace(c))
	return strings.NewReplacer("-", "", " ", "").Replace(c)
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func cleanLabel(l string) string {
	l = strings.TrimSpace(l)
	if l == "" {
		return "device"
	}
	if len(l) > 64 {
		l = l[:64]
	}
	return l
}

// Pair trades a valid one-time code for a new bearer token. The code is spent
// on success; five wrong guesses lock pairing for a minute.
func (s *Store) Pair(code, label string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if now.Before(s.lockedUntil) {
		return "", ErrLocked
	}
	given := normalizeCode(code)
	valid := s.code != "" && now.Before(s.codeExpires) &&
		subtle.ConstantTimeCompare([]byte(given), []byte(s.code)) == 1
	if !valid {
		s.bad++
		if s.bad >= maxBadAttempts {
			s.bad, s.lockedUntil = 0, now.Add(lockoutFor)
			return "", ErrLocked
		}
		return "", ErrBadCode
	}
	token, err := randomBytesToken()
	if err != nil {
		return "", err
	}
	if err := s.reloadLocked(false); err != nil {
		return "", err
	}
	s.devices = append(s.devices, Device{Label: cleanLabel(label), Hash: hashToken(token), CreatedAt: now.UTC()})
	if err := s.saveLocked(); err != nil {
		s.devices = s.devices[:len(s.devices)-1]
		return "", err
	}
	s.code, s.bad = "", 0
	return token, nil
}

func randomBytesToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// Verify reports whether token belongs to a paired device.
func (s *Store) Verify(token string) bool {
	if token == "" {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = s.reloadLocked(false) // keep the last good list if the file is mid-write
	want := hashToken(token)
	ok := false
	for _, d := range s.devices {
		if subtle.ConstantTimeCompare([]byte(d.Hash), []byte(want)) == 1 {
			ok = true
		}
	}
	return ok
}

// Label returns the name a token's device was paired under, or "" if the token is unknown.
func (s *Store) Label(token string) string {
	if token == "" {
		return ""
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = s.reloadLocked(false)
	want := hashToken(token)
	for _, d := range s.devices {
		if subtle.ConstantTimeCompare([]byte(d.Hash), []byte(want)) == 1 {
			return d.Label
		}
	}
	return ""
}

// Devices returns paired devices (labels and dates only; never tokens).
func (s *Store) Devices() []Device {
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = s.reloadLocked(false)
	return append([]Device(nil), s.devices...)
}

// Revoke removes every device with this label and returns how many were removed.
func (s *Store) Revoke(label string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.reloadLocked(false); err != nil {
		return 0, err
	}
	kept := s.devices[:0:0]
	for _, d := range s.devices {
		if d.Label != label {
			kept = append(kept, d)
		}
	}
	removed := len(s.devices) - len(kept)
	if removed == 0 {
		return 0, nil
	}
	s.devices = kept
	return removed, s.saveLocked()
}

// BearerToken extracts the token from "Authorization: Bearer <token>".
func BearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}

// Middleware rejects requests that do not carry a paired device's token.
func (s *Store) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.Verify(BearerToken(r)) {
			w.Header().Set("WWW-Authenticate", `Bearer realm="i30ltz-node"`)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"missing or unknown token; pair this device first"}`))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// IsLoopback is true only for requests that came from this machine and were
// not relayed by a proxy.
func IsLoopback(r *http.Request) bool {
	if r.Header.Get("X-Forwarded-For") != "" || r.Header.Get("Forwarded") != "" {
		return false
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
