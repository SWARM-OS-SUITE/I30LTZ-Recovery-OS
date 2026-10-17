package scan

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeScanner writes a shell script standing in for clamscan. It records its arguments in args.txt next to it.
func fakeScanner(t *testing.T, body string) (bin, argsFile string) {
	t.Helper()
	dir := t.TempDir()
	argsFile = filepath.Join(dir, "args.txt")
	bin = filepath.Join(dir, "clamscan")
	// --version is answered like the real scanner so Info/Start do not run the scripted body.
	script := "#!/bin/sh\nfor a; do [ \"$a\" = --version ] && { echo 'ClamAV 1.4.3/28146/Tue Oct  7 08:30:04 2026'; exit 0; }; done\n" +
		"printf '%s\\n' \"$@\" > '" + argsFile + "'\n" + body + "\n"
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return bin, argsFile
}

func newManager(t *testing.T, bin string, mod func(*Config)) *Manager {
	t.Helper()
	cfg := Config{Binary: bin, StateDir: filepath.Join(t.TempDir(), "state"), Home: t.TempDir()}
	if mod != nil {
		mod(&cfg)
	}
	m, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func startAndWait(t *testing.T, m *Manager, scope, path string) Result {
	t.Helper()
	id, err := m.Start(scope, path)
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	m.Wait()
	r, _ := m.Get(id)
	return r
}

func TestParseVersion(t *testing.T) {
	v, db, d, ok := parseVersion("ClamAV 1.4.3/28146/Tue Oct  7 08:30:04 2026\n")
	if !ok || v != "1.4.3" || db != "28146" || d.Year() != 2026 || d.Month() != time.October || d.Day() != 7 {
		t.Fatalf("%q %q %v %v", v, db, d, ok)
	}
	if v, db, d, ok := parseVersion("ClamAV 1.4.3"); !ok || v != "1.4.3" || db != "" || !d.IsZero() {
		t.Fatalf("no-signature form: %q %q %v %v", v, db, d, ok)
	}
	if _, _, _, ok := parseVersion("something else"); ok {
		t.Error("garbage must not parse")
	}
}

func TestHandleLineClassifiesClamscanOutput(t *testing.T) {
	m := newManager(t, "/bin/true", nil)
	r := &Result{Findings: []Finding{}, ErrorSamples: []string{}}
	for _, l := range []string{
		"/home/u/a.txt: OK",
		"/home/u/dir: with colon/evil.bin: Win.Test.Sample-1 FOUND", // ": " inside the path
		"/home/u/locked: Permission denied ERROR",
		"/home/u/secret: Access denied", // the real clamscan wording for an unreadable file
		"/home/u/odd: A result nobody has seen before",
		"/home/u/empty: Empty file",
		"/home/u/link: Symbolic link",
		"/proc/self: Excluded",
		"not a result line",
	} {
		m.handleLine(r, l)
	}
	if r.Scanned != 3 || r.Skipped != 2 || r.Errors != 3 {
		t.Errorf("scanned=%d skipped=%d errors=%d", r.Scanned, r.Skipped, r.Errors)
	}
	if len(r.Findings) != 1 || r.Findings[0].Path != "/home/u/dir: with colon/evil.bin" || r.Findings[0].Signature != "Win.Test.Sample-1" {
		t.Errorf("findings %+v", r.Findings)
	}
	if strings.Join(r.ErrorSamples, "|") != "/home/u/locked: Permission denied|/home/u/secret: Access denied|/home/u/odd: A result nobody has seen before" {
		t.Errorf("error samples %q", r.ErrorSamples)
	}
}

func TestScanReportsFindingsAndUnreadableFiles(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "/x/a: OK"; echo "/x/evil: Test.Sig FOUND"; echo "/x/locked: Permission denied ERROR"; exit 1`)
	m := newManager(t, bin, nil)
	dir := t.TempDir()
	r := startAndWait(t, m, "path", dir)
	if r.State != StateDone || r.Scanned != 2 || len(r.Findings) != 1 || r.Errors != 1 || r.Finished == nil {
		t.Fatalf("%+v", r)
	}
	if r.Current != "" {
		t.Error("current must be cleared when finished")
	}
}

func TestACleanScanIsDoneWithNoFindings(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "/x/a: OK"; exit 0`)
	r := startAndWait(t, newManager(t, bin, nil), "path", t.TempDir())
	if r.State != StateDone || len(r.Findings) != 0 || r.Scanned != 1 {
		t.Fatalf("%+v", r)
	}
}

func TestBrokenSignatureDatabaseIsAFailureNotACleanScan(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "LibClamAV Error: cl_load(): No such file or directory: /nope" >&2; echo "ERROR: Can't open file or directory" >&2; exit 2`)
	r := startAndWait(t, newManager(t, bin, nil), "path", t.TempDir())
	if r.State != StateFailed || !strings.Contains(r.Message, "LibClamAV Error") || r.Scanned != 0 {
		t.Fatalf("a scan that checked nothing must not look clean: %+v", r)
	}
}

func TestExitCodeTwoAfterScanningFilesIsDoneWithErrors(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "/x/a: OK"; echo "/x/b: Access denied ERROR"; exit 2`)
	r := startAndWait(t, newManager(t, bin, nil), "path", t.TempDir())
	if r.State != StateDone || r.Errors != 1 {
		t.Fatalf("%+v", r)
	}
}

func TestOnlyOneScanAtATimeAndCancelStopsIt(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "/x/a: OK"; sleep 30`)
	m := newManager(t, bin, nil)
	id, err := m.Start("path", t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := m.Start("path", t.TempDir()); err != ErrBusy {
		t.Fatalf("second start: %v want ErrBusy", err)
	}
	// progress is visible while it runs
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if r, _ := m.Get(id); r.Scanned == 1 && r.State == StateRunning {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if r, _ := m.Get(id); r.Scanned != 1 || r.State != StateRunning {
		t.Fatalf("expected a running scan with 1 file done: %+v", r)
	}
	if m.Cancel("some-other-id") {
		t.Error("cancelling an unknown id must report false")
	}
	start := time.Now()
	if !m.Cancel(id) {
		t.Fatal("cancel should succeed")
	}
	if time.Since(start) > 4*time.Second {
		t.Errorf("cancel took %v", time.Since(start))
	}
	if r, _ := m.Get(id); r.State != StateCancelled {
		t.Fatalf("state %s", r.State)
	}
	id2, err := m.Start("path", t.TempDir())
	if err != nil {
		t.Fatalf("a new scan must be possible after cancelling: %v", err)
	}
	if !m.Cancel(id2) {
		t.Fatal("the second scan should be cancellable too")
	}
}

func TestScopesChooseTheRightFoldersAndFlags(t *testing.T) {
	bin, argsFile := fakeScanner(t, `exit 0`)
	home := t.TempDir()
	dl := filepath.Join(home, "Downloads")
	os.MkdirAll(dl, 0o755)
	m := newManager(t, bin, func(c *Config) {
		c.Home = home
		c.Quick = []string{dl, filepath.Join(home, "missing"), "/tmp"}
		c.DBDir = "/custom/db"
	})

	args := func(scope, path string) string {
		startAndWait(t, m, scope, path)
		raw, _ := os.ReadFile(argsFile)
		return string(raw)
	}
	if a := args("quick", ""); !strings.Contains(a, dl+"\n") || !strings.Contains(a, "/tmp\n") || strings.Contains(a, "missing") {
		t.Errorf("quick: %q", a)
	}
	a := args("home", "")
	for _, want := range []string{"-r\n", "--follow-dir-symlinks=0\n", "--follow-file-symlinks=0\n", "-d\n/custom/db\n", "--stdout\n", home + "\n"} {
		if !strings.Contains(a, want) {
			t.Errorf("home args missing %q in %q", want, a)
		}
	}
	a = args("full", "")
	for _, want := range []string{"--cross-fs=no\n", "--exclude-dir=^/proc/\n", "--exclude-dir=^/sys/\n", "--exclude-dir=^/dev/\n"} {
		if !strings.Contains(a, want) {
			t.Errorf("full args missing %q in %q", want, a)
		}
	}
	if !strings.HasSuffix(a, "\n/\n") {
		t.Errorf("full scan should end with the root path: %q", a)
	}
	if a := args("path", dl+"/../Downloads"); !strings.HasSuffix(a, "\n"+dl+"\n") {
		t.Errorf("path should be cleaned: %q", a)
	}
}

func TestBadScopesAndPathsAreRefusedBeforeAnythingRuns(t *testing.T) {
	bin, argsFile := fakeScanner(t, `exit 0`)
	m := newManager(t, bin, func(c *Config) { c.Quick = []string{"/definitely/not/here"} })
	cases := []struct{ scope, path string }{
		{"everything", ""}, {"", ""}, {"path", ""}, {"path", "relative/dir"}, {"path", "/no/such/dir"},
		{"path", "/tmp\x00/x"}, {"quick", ""},
	}
	for _, c := range cases {
		if _, err := m.Start(c.scope, c.path); err == nil {
			t.Errorf("Start(%q, %q) should fail", c.scope, c.path)
		}
	}
	if _, err := os.Stat(argsFile); err == nil {
		t.Error("the scanner must not have been started for a refused request")
	}
}

func TestNoScannerMeansUnavailableNotAFakeResult(t *testing.T) {
	m := newManager(t, filepath.Join(t.TempDir(), "no-such-clamscan"), nil)
	if m.Available() {
		t.Fatal("should be unavailable")
	}
	if _, err := m.Start("home", ""); err != ErrUnavailable {
		t.Fatalf("got %v", err)
	}
	if info := m.Info(t.Context()); info.Available || info.Reason == "" {
		t.Errorf("%+v", info)
	}
}

func TestInfoReportsSignatureAgeAndStaleness(t *testing.T) {
	bin, _ := fakeScanner(t, `exit 0`) // --version is answered by the harness
	m := newManager(t, bin, nil)
	m.now = func() time.Time { return time.Date(2026, 10, 9, 8, 30, 4, 0, time.UTC) }
	info := m.Info(t.Context())
	if !info.Available || info.Version != "1.4.3" || info.SignatureDB != "28146" || info.SignatureAgeDays != 2 || info.Stale {
		t.Errorf("fresh: %+v", info)
	}
	m.now = func() time.Time { return time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC) }
	if info := m.Info(t.Context()); info.SignatureAgeDays != 12 || !info.Stale {
		t.Errorf("stale: %+v", info)
	}
	noDate := filepath.Join(t.TempDir(), "clamscan")
	os.WriteFile(noDate, []byte("#!/bin/sh\necho 'ClamAV 1.4.3'\n"), 0o755)
	if info := newManager(t, noDate, nil).Info(t.Context()); info.SignatureAgeDays != -1 || info.Stale {
		t.Errorf("unknown age must be -1 and not 'stale': %+v", info)
	}
}

func TestFindingsAreCappedButCounted(t *testing.T) {
	bin, _ := fakeScanner(t, `i=0; while [ $i -lt 1100 ]; do echo "/x/f$i: Test.Sig FOUND"; i=$((i+1)); done; exit 1`)
	r := startAndWait(t, newManager(t, bin, nil), "path", t.TempDir())
	if len(r.Findings) != maxFindings || !r.FindingsCut || r.Scanned != 1100 {
		t.Fatalf("findings=%d cut=%v scanned=%d", len(r.Findings), r.FindingsCut, r.Scanned)
	}
}

func TestResultsSurviveARestartAndOldOnesArePruned(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "/x/a: OK"`)
	state := filepath.Join(t.TempDir(), "state")
	m := newManager(t, bin, func(c *Config) { c.StateDir = state })
	var ids []string
	for i := 0; i < keepResults+3; i++ {
		id, err := m.Start("path", t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		m.Wait()
		ids = append(ids, id)
		time.Sleep(2 * time.Millisecond)
	}
	if n := len(m.List()); n != keepResults {
		t.Errorf("kept %d results, want %d", n, keepResults)
	}
	m2 := newManager(t, bin, func(c *Config) { c.StateDir = state })
	if _, ok := m2.Get(ids[len(ids)-1]); !ok {
		t.Error("the newest scan should be loaded after a restart")
	}
	if _, ok := m2.Get(ids[0]); ok {
		t.Error("the oldest scan should have been pruned")
	}
	files, _ := filepath.Glob(filepath.Join(state, "scans", "*.json"))
	if len(files) != keepResults {
		t.Errorf("%d files on disk", len(files))
	}
	if info, _ := os.Stat(files[0]); info.Mode().Perm() != 0o600 {
		t.Errorf("scan files must be private, got %v", info.Mode().Perm())
	}
}

func TestReturnedResultsAreCopies(t *testing.T) {
	bin, _ := fakeScanner(t, `echo "/x/e: Test.Sig FOUND"; exit 1`)
	m := newManager(t, bin, nil)
	r := startAndWait(t, m, "path", t.TempDir())
	r.Findings[0].Signature = "tampered"
	r.Paths[0] = "tampered"
	again, _ := m.Get(r.ID)
	if again.Findings[0].Signature != "Test.Sig" || again.Paths[0] == "tampered" {
		t.Fatal("callers must not be able to change stored results")
	}
}

func TestIDsLookLikeIDs(t *testing.T) {
	id := newID(time.Date(2026, 10, 7, 23, 14, 55, 0, time.UTC))
	if !strings.HasPrefix(id, "20261007-231455-") || !validID(id) {
		t.Fatalf("%q", id)
	}
	for _, bad := range []string{"", "../x", "a/b", "A", strings.Repeat("a", 65), "a b"} {
		if validID(bad) {
			t.Errorf("%q should be invalid", bad)
		}
	}
	_ = fmt.Sprint
}
