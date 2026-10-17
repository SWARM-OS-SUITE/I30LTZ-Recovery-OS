package scan

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// These tests run the real ClamAV. Set I30LTZ_CLAMSCAN to a clamscan binary (or have one in PATH);
// without one they are skipped. I30LTZ_CLAM_FULL_DB (a directory holding the official signatures)
// enables the last test.
func realClamscan(t *testing.T) string {
	t.Helper()
	if p := os.Getenv("I30LTZ_CLAMSCAN"); p != "" {
		return p
	}
	if p, err := exec.LookPath("clamscan"); err == nil {
		return p
	}
	t.Skip("no clamscan available")
	return ""
}

// signatureDir makes a signature database that knows exactly one file content, by hash.
func signatureDir(t *testing.T, name string, content []byte) string {
	t.Helper()
	dir := t.TempDir()
	sum := md5.Sum(content)
	line := fmt.Sprintf("%s:%d:%s\n", hex.EncodeToString(sum[:]), len(content), name)
	if err := os.WriteFile(filepath.Join(dir, "marker.hdb"), []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

const markerSig = "I30LTZ.Test.Marker"

var markerContent = []byte("I30LTZ-NOT-REAL-MALWARE-test-marker-3f9a1c")

func realManager(t *testing.T, db string) *Manager {
	t.Helper()
	return newManager(t, realClamscan(t), func(c *Config) { c.DBDir = db })
}

func TestRealClamAVFindsOnlyWhatTheSignatureMatches(t *testing.T) {
	m := realManager(t, signatureDir(t, markerSig, markerContent))
	root := t.TempDir()
	scanned := filepath.Join(root, "scanned")
	outside := filepath.Join(root, "outside")
	os.MkdirAll(filepath.Join(scanned, "sub", "deeper"), 0o755)
	os.MkdirAll(outside, 0o755)
	os.WriteFile(filepath.Join(scanned, "clean.txt"), []byte("hello world"), 0o644)
	os.WriteFile(filepath.Join(scanned, "sub", "infected.bin"), markerContent, 0o644)
	os.WriteFile(filepath.Join(scanned, "sub", "deeper", "also infected.bin"), markerContent, 0o644)
	os.WriteFile(filepath.Join(outside, "elsewhere.bin"), markerContent, 0o644)
	os.Symlink(filepath.Join(outside, "elsewhere.bin"), filepath.Join(scanned, "link-to-infected"))
	os.Symlink(outside, filepath.Join(scanned, "link-to-folder"))
	locked := filepath.Join(scanned, "locked")
	os.WriteFile(locked, markerContent, 0o000)
	defer os.Chmod(locked, 0o600)

	r := startAndWait(t, m, "path", scanned)
	if r.State != StateDone {
		t.Fatalf("%+v", r)
	}
	var got []string
	for _, f := range r.Findings {
		// ClamAV marks signatures from a user-supplied database as UNOFFICIAL; we report the name as the engine gives it.
		if f.Signature != markerSig+".UNOFFICIAL" {
			t.Errorf("signature %q", f.Signature)
		}
		got = append(got, strings.TrimPrefix(f.Path, scanned+"/"))
	}
	sort.Strings(got)
	want := []string{"sub/deeper/also infected.bin", "sub/infected.bin"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("findings %v, want exactly %v (links must not be followed)", got, want)
	}
	if r.Scanned < 3 {
		t.Errorf("scanned %d", r.Scanned)
	}
	if os.Geteuid() != 0 && (r.Errors != 1 || !strings.Contains(r.ErrorSamples[0], "locked: Access denied")) {
		t.Errorf("the unreadable file should be reported as an error, not skipped silently: errors=%d %v", r.Errors, r.ErrorSamples)
	}
	if info := m.Info(t.Context()); !info.Available || info.Version == "" {
		t.Errorf("%+v", info)
	}
}

func TestRealClamAVQuarantineRechecksWithTheRealEngine(t *testing.T) {
	m := realManager(t, signatureDir(t, markerSig, markerContent))
	q := newQuarantine(t)
	dir := t.TempDir()
	bad, bad2 := filepath.Join(dir, "bad.bin"), filepath.Join(dir, "bad2.bin")
	os.WriteFile(bad, markerContent, 0o640)
	os.WriteFile(bad2, markerContent, 0o644)
	r := startAndWait(t, m, "path", dir)
	if len(r.Findings) != 2 {
		t.Fatalf("%+v", r)
	}

	it, err := m.Quarantine(q, r.ID, bad)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(bad); !os.IsNotExist(err) {
		t.Error("the finding should be quarantined")
	}
	if _, err := os.Stat(bad2); err != nil {
		t.Error("the other file is untouched until it is asked for")
	}
	os.WriteFile(bad2, []byte("replaced by a clean file after the scan"), 0o644)
	if _, err := m.Quarantine(q, r.ID, bad2); err != ErrNoLongerInfected {
		t.Fatalf("a replaced file must be re-checked: %v", err)
	}
	if got, _ := os.ReadFile(bad2); string(got) != "replaced by a clean file after the scan" {
		t.Error("clean file touched")
	}
	if _, err := q.Restore(it.ID); err != nil {
		t.Fatal(err)
	}
	if st, _ := os.Stat(bad); st == nil || st.Mode().Perm() != 0o640 {
		t.Errorf("restored with wrong mode: %v", st)
	}
}

func TestRealClamAVWithoutSignaturesIsAFailureNotAllClear(t *testing.T) {
	m := realManager(t, t.TempDir()) // an empty signature directory
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "f"), []byte("x"), 0o644)
	r := startAndWait(t, m, "path", dir)
	if r.State != StateFailed || r.Message == "" {
		t.Fatalf("a scan with no signatures must fail loudly, got %+v", r)
	}
}

// Official signatures + the standard EICAR test file (assembled here so no file in this repo contains it).
func TestRealClamAVOfficialSignaturesDetectEICAR(t *testing.T) {
	db := os.Getenv("I30LTZ_CLAM_FULL_DB")
	if db == "" {
		t.Skip("I30LTZ_CLAM_FULL_DB not set")
	}
	m := realManager(t, db)
	dir := t.TempDir()
	eicar := "X5O!P%@AP[4\\PZX54(P^)7CC)7}$" + "EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
	os.WriteFile(filepath.Join(dir, "eicar.com"), []byte(eicar), 0o644)
	os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("just some notes"), 0o644)
	r := startAndWait(t, m, "path", dir)
	if r.State != StateDone || len(r.Findings) != 1 || !strings.Contains(r.Findings[0].Signature, "Eicar") {
		t.Fatalf("%+v", r)
	}
	info := m.Info(t.Context())
	t.Logf("engine %s, signatures %s (%d days old), scan state %s, %d files", info.Version, info.SignatureDB, info.SignatureAgeDays, r.State, r.Scanned)
	if info.SignatureAgeDays < 0 {
		t.Error("the official database carries a date; the age should be known")
	}
}
