package scan

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	ErrNotAFinding      = errors.New("that file is not one of this scan's findings")
	ErrNoLongerInfected = errors.New("that file no longer matches a malware signature (it changed since the scan); nothing was moved")
	ErrNoSuchItem       = errors.New("no such quarantined item")
	ErrOriginalExists   = errors.New("something already exists at the original path; restore refused so nothing is overwritten")
)

// Item is one quarantined file. The file itself is stored as <ID>.bin (mode 0400, never executable).
type Item struct {
	ID            string    `json:"id"`
	Original      string    `json:"original_path"`
	Signature     string    `json:"signature"`
	ScanID        string    `json:"scan_id"`
	SHA256        string    `json:"sha256"`
	Size          int64     `json:"size"`
	Mode          uint32    `json:"mode"`
	QuarantinedAt time.Time `json:"quarantined_at"`
}

// Quarantine moves detected files out of harm's way, reversibly.
type Quarantine struct {
	dir string
	mu  sync.Mutex
}

func OpenQuarantine(stateDir string) (*Quarantine, error) {
	dir := filepath.Join(stateDir, "quarantine")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	return &Quarantine{dir: dir}, nil
}

func (q *Quarantine) bin(id string) string  { return filepath.Join(q.dir, id+".bin") }
func (q *Quarantine) meta(id string) string { return filepath.Join(q.dir, id+".json") }

func validID(id string) bool {
	if id == "" || len(id) > 64 {
		return false
	}
	for _, c := range id {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c == '-') {
			return false
		}
	}
	return true
}

// Add copies the file into quarantine (hashing it on the way), then removes the original. If the
// original cannot be removed the copy is deleted again, so a failure never leaves two live copies
// or a half-done state.
func (q *Quarantine) Add(path, signature, scanID string) (Item, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	lst, err := os.Lstat(path)
	if err != nil {
		return Item{}, err
	}
	if !lst.Mode().IsRegular() {
		return Item{}, errors.New("only regular files can be quarantined (not links, folders or devices)")
	}
	src, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return Item{}, err
	}
	defer src.Close()
	if st, err := src.Stat(); err != nil || !os.SameFile(lst, st) {
		return Item{}, errors.New("the file changed while it was being opened; nothing was moved")
	}

	it := Item{ID: newID(time.Now()), Original: path, Signature: signature, ScanID: scanID,
		Mode: uint32(lst.Mode().Perm()), QuarantinedAt: time.Now().UTC()}
	dst, err := os.OpenFile(q.bin(it.ID), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o400)
	if err != nil {
		return Item{}, err
	}
	h := sha256.New()
	n, err := io.Copy(io.MultiWriter(dst, h), src)
	if err == nil {
		err = dst.Sync()
	}
	if cerr := dst.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(q.bin(it.ID))
		return Item{}, err
	}
	it.Size, it.SHA256 = n, hex.EncodeToString(h.Sum(nil))
	raw, _ := json.MarshalIndent(it, "", "  ")
	if err := os.WriteFile(q.meta(it.ID), raw, 0o600); err != nil {
		os.Remove(q.bin(it.ID))
		return Item{}, err
	}
	if err := os.Remove(path); err != nil {
		os.Remove(q.bin(it.ID))
		os.Remove(q.meta(it.ID))
		return Item{}, fmt.Errorf("could not remove the original (no permission?); nothing was changed: %w", err)
	}
	return it, nil
}

func (q *Quarantine) load(id string) (Item, error) {
	if !validID(id) {
		return Item{}, ErrNoSuchItem
	}
	raw, err := os.ReadFile(q.meta(id))
	if err != nil {
		return Item{}, ErrNoSuchItem
	}
	var it Item
	if json.Unmarshal(raw, &it) != nil || it.ID != id {
		return Item{}, ErrNoSuchItem
	}
	return it, nil
}

// List returns quarantined items, newest first.
func (q *Quarantine) List() ([]Item, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	files, _ := filepath.Glob(filepath.Join(q.dir, "*.json"))
	items := []Item{}
	for _, f := range files {
		if it, err := q.load(strings.TrimSuffix(filepath.Base(f), ".json")); err == nil {
			items = append(items, it)
		}
	}
	sort.Slice(items, func(i, j int) bool { return items[i].QuarantinedAt.After(items[j].QuarantinedAt) })
	return items, nil
}

// Restore puts the file back exactly where it was, with its old permissions. It never overwrites.
func (q *Quarantine) Restore(id string) (Item, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	it, err := q.load(id)
	if err != nil {
		return Item{}, err
	}
	if _, err := os.Lstat(it.Original); err == nil {
		return Item{}, ErrOriginalExists
	}
	src, err := os.Open(q.bin(id))
	if err != nil {
		return Item{}, err
	}
	defer src.Close()
	dst, err := os.OpenFile(it.Original, os.O_WRONLY|os.O_CREATE|os.O_EXCL, os.FileMode(it.Mode))
	if err != nil {
		return Item{}, err
	}
	_, err = io.Copy(dst, src)
	if cerr := dst.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(it.Original)
		return Item{}, err
	}
	_ = os.Chmod(it.Original, os.FileMode(it.Mode)) // creation applies the umask
	os.Remove(q.bin(id))
	os.Remove(q.meta(id))
	return it, nil
}

// Delete permanently removes a quarantined file.
func (q *Quarantine) Delete(id string) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	if _, err := q.load(id); err != nil {
		return err
	}
	e1, e2 := os.Remove(q.bin(id)), os.Remove(q.meta(id))
	if e1 != nil {
		return e1
	}
	return e2
}

// Quarantine moves one finding of a finished scan into quarantine. It scans the file again first, so
// a clean file that replaced the infected one after the scan is never touched.
func (m *Manager) Quarantine(q *Quarantine, scanID, path string) (Item, error) {
	r, ok := m.Get(scanID)
	if !ok {
		return Item{}, errors.New("unknown scan")
	}
	var sig string
	for _, f := range r.Findings {
		if f.Path == path {
			sig = f.Signature
		}
	}
	if sig == "" || !filepath.IsAbs(path) {
		return Item{}, ErrNotAFinding
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	args := append([]string{"--stdout", "--no-summary", "--follow-file-symlinks=0"}, m.dbArgs()...)
	out, _ := exec.CommandContext(ctx, m.cfg.Binary, append(args, path)...).Output() // exit 1 = found
	if !strings.Contains(string(out), path+": ") || !strings.Contains(string(out), " FOUND") {
		return Item{}, ErrNoLongerInfected
	}
	return q.Add(path, sig, scanID)
}
