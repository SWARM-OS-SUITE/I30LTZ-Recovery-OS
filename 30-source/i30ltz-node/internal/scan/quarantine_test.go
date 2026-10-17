package scan

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newQuarantine(t *testing.T) *Quarantine {
	t.Helper()
	q, err := OpenQuarantine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return q
}

func TestQuarantineMovesHashesAndRestoresExactly(t *testing.T) {
	q := newQuarantine(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "evil.sh")
	content := []byte("#!/bin/sh\necho pretend-malware\n")
	os.WriteFile(path, content, 0o755)

	it, err := q.Add(path, "Test.Sig", "scan-1")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(path); !os.IsNotExist(err) {
		t.Fatal("the original must be gone")
	}
	sum := sha256.Sum256(content)
	if it.SHA256 != hex.EncodeToString(sum[:]) || it.Size != int64(len(content)) || it.Mode != 0o755 || it.Original != path {
		t.Errorf("%+v", it)
	}
	st, err := os.Stat(q.bin(it.ID))
	if err != nil || st.Mode().Perm() != 0o400 {
		t.Fatalf("quarantined copy must be read-only and not executable: %v %v", st, err)
	}
	if st, _ := os.Stat(q.dir); st.Mode().Perm() != 0o700 {
		t.Errorf("quarantine dir mode %v", st.Mode().Perm())
	}
	if items, _ := q.List(); len(items) != 1 || items[0].ID != it.ID {
		t.Fatalf("list: %+v", items)
	}

	if _, err := q.Restore(it.ID); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(path)
	st, _ = os.Stat(path)
	if string(got) != string(content) || st.Mode().Perm() != 0o755 {
		t.Errorf("restore must give back the same bytes and mode: %q %v", got, st.Mode().Perm())
	}
	if items, _ := q.List(); len(items) != 0 {
		t.Error("restored items leave quarantine")
	}
}

func TestRestoreNeverOverwrites(t *testing.T) {
	q := newQuarantine(t)
	path := filepath.Join(t.TempDir(), "f")
	os.WriteFile(path, []byte("old"), 0o644)
	it, _ := q.Add(path, "Test.Sig", "s")
	os.WriteFile(path, []byte("someone put a new file here"), 0o644)
	if _, err := q.Restore(it.ID); err != ErrOriginalExists {
		t.Fatalf("got %v", err)
	}
	if got, _ := os.ReadFile(path); string(got) != "someone put a new file here" {
		t.Error("the existing file was changed")
	}
	if items, _ := q.List(); len(items) != 1 {
		t.Error("a refused restore must keep the item")
	}
}

func TestDeleteIsPermanentAndExplicit(t *testing.T) {
	q := newQuarantine(t)
	path := filepath.Join(t.TempDir(), "f")
	os.WriteFile(path, []byte("x"), 0o644)
	it, _ := q.Add(path, "Test.Sig", "s")
	if err := q.Delete(it.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(q.bin(it.ID)); !os.IsNotExist(err) {
		t.Error("the stored copy must be gone")
	}
	if err := q.Delete(it.ID); err != ErrNoSuchItem {
		t.Errorf("second delete: %v", err)
	}
}

func TestQuarantineRefusesLinksFoldersAndOddIDs(t *testing.T) {
	q := newQuarantine(t)
	dir := t.TempDir()
	target := filepath.Join(dir, "real")
	os.WriteFile(target, []byte("x"), 0o644)
	link := filepath.Join(dir, "link")
	os.Symlink(target, link)
	if _, err := q.Add(link, "S", "s"); err == nil {
		t.Error("a symlink must not be quarantined")
	}
	if _, err := os.Stat(target); err != nil {
		t.Error("the link's target must be untouched")
	}
	if _, err := q.Add(dir, "S", "s"); err == nil {
		t.Error("a folder must not be quarantined")
	}
	if _, err := q.Add(filepath.Join(dir, "missing"), "S", "s"); err == nil {
		t.Error("a missing file must be an error")
	}
	for _, id := range []string{"../../etc/passwd", "a/b", "", "X"} {
		if _, err := q.Restore(id); err != ErrNoSuchItem {
			t.Errorf("Restore(%q): %v", id, err)
		}
		if err := q.Delete(id); err != ErrNoSuchItem {
			t.Errorf("Delete(%q): %v", id, err)
		}
	}
}

func TestIfTheOriginalCannotBeRemovedNothingChanges(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can remove anything")
	}
	q := newQuarantine(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "stuck")
	os.WriteFile(path, []byte("x"), 0o644)
	os.Chmod(dir, 0o500) // no write permission: unlink fails
	defer os.Chmod(dir, 0o700)
	if _, err := q.Add(path, "S", "s"); err == nil || !strings.Contains(err.Error(), "nothing was changed") {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Error("the original must still be there")
	}
	entries, _ := os.ReadDir(q.dir)
	if len(entries) != 0 {
		t.Errorf("no half-finished copy may be left behind: %v", entries)
	}
}

// With a scanner that only says FOUND while the file still contains EVIL, the quarantine step must
// re-check, refuse files that are not findings, and refuse a clean file that replaced an infected one.
func TestQuarantineRechecksAndOnlyTouchesFindings(t *testing.T) {
	bin, _ := fakeScanner(t, `
for last; do :; done
case "$*" in *--no-summary*--follow-file-symlinks=0*"$last") ;; esac
if [ -f "$last" ] && grep -q EVIL "$last" 2>/dev/null; then echo "$last: Test.Sig FOUND"; exit 1; fi
echo "$last: OK"; exit 0`)
	m := newManager(t, bin, nil)
	q := newQuarantine(t)
	dir := t.TempDir()
	bad, other := filepath.Join(dir, "bad"), filepath.Join(dir, "other")
	os.WriteFile(bad, []byte("EVIL"), 0o644)
	os.WriteFile(other, []byte("EVIL"), 0o644)
	// fabricate a finished scan whose only finding is "bad"
	r := &Result{ID: "20261007-000000-aaaaaa", State: StateDone, Findings: []Finding{{Path: bad, Signature: "Test.Sig"}}}
	m.results[r.ID] = r

	if _, err := m.Quarantine(q, r.ID, other); err != ErrNotAFinding {
		t.Errorf("file outside the findings: %v", err)
	}
	if _, err := m.Quarantine(q, r.ID, "relative"); err != ErrNotAFinding {
		t.Errorf("relative path: %v", err)
	}
	if _, err := m.Quarantine(q, "20261007-000000-bbbbbb", bad); err == nil {
		t.Error("unknown scan must fail")
	}
	os.WriteFile(bad, []byte("now harmless"), 0o644) // replaced after the scan
	if _, err := m.Quarantine(q, r.ID, bad); err != ErrNoLongerInfected {
		t.Errorf("clean replacement: %v", err)
	}
	if got, _ := os.ReadFile(bad); string(got) != "now harmless" {
		t.Error("the clean file must not be touched")
	}
	os.WriteFile(bad, []byte("EVIL again"), 0o644)
	it, err := m.Quarantine(q, r.ID, bad)
	if err != nil || it.Signature != "Test.Sig" || it.ScanID != r.ID {
		t.Fatalf("%+v %v", it, err)
	}
	if _, err := os.Stat(bad); !os.IsNotExist(err) {
		t.Error("the confirmed finding must have been moved")
	}
	if _, err := os.Stat(other); err != nil {
		t.Error("other files must be untouched")
	}
}
