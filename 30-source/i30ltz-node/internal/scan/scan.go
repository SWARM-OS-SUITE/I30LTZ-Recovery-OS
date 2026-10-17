// Package scan runs ClamAV (clamscan) on this machine and keeps the results.
//
// It never deletes, moves or changes a file by itself: scanning only reports. Quarantine is a
// separate, explicit action (see quarantine.go) that the phone's owner has to ask for.
package scan

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	StateRunning   = "running"
	StateDone      = "done"
	StateFailed    = "failed"
	StateCancelled = "cancelled"

	maxFindings   = 1000
	maxErrorLines = 20
	keepResults   = 20
	// StaleAfterDays: signatures older than this are flagged, because a scan with old signatures
	// says little about new malware.
	StaleAfterDays = 7
)

var (
	ErrBusy        = errors.New("a scan is already running on this node")
	ErrUnavailable = errors.New("no malware scanner is installed on this node (install ClamAV: apt install clamav / pacman -S clamav)")
	ErrBadScope    = errors.New("scope must be quick, home, full or path")
)

// Finding is one file a signature matched.
type Finding struct {
	Path      string `json:"path"`
	Signature string `json:"signature"`
}

// Result is the state of one scan, running or finished.
type Result struct {
	ID            string     `json:"id"`
	State         string     `json:"state"`
	Scope         string     `json:"scope"`
	Paths         []string   `json:"paths"`
	Started       time.Time  `json:"started"`
	Finished      *time.Time `json:"finished,omitempty"`
	Scanned       int        `json:"scanned_files"`
	Skipped       int        `json:"skipped_files"`
	Current       string     `json:"current,omitempty"`
	Findings      []Finding  `json:"findings"`
	FindingsCut   bool       `json:"findings_truncated,omitempty"`
	Errors        int        `json:"errors"`
	ErrorSamples  []string   `json:"error_samples"`
	Message       string     `json:"message,omitempty"`
	EngineVersion string     `json:"engine_version"`
}

// Info describes the engine and its signatures.
type Info struct {
	Available     bool   `json:"available"`
	Engine        string `json:"engine"`
	Version       string `json:"version,omitempty"`
	SignatureDB   string `json:"signature_version,omitempty"`
	SignatureDate string `json:"signature_date,omitempty"`
	// SignatureAgeDays is -1 when it cannot be determined.
	SignatureAgeDays int    `json:"signature_age_days"`
	Stale            bool   `json:"signatures_stale"`
	Running          string `json:"running_scan,omitempty"`
	Reason           string `json:"reason,omitempty"`
}

// Config says where things are. Zero values are fine except StateDir.
type Config struct {
	Binary   string   // path to clamscan; "" means look it up in PATH
	DBDir    string   // signature directory passed as -d; "" means ClamAV's default
	StateDir string   // scans/ and quarantine/ live here (mode 0700)
	Home     string   // for the quick and home scopes; "" means the current user's home
	Quick    []string // overrides the quick-scan folders (tests)
}

type job struct {
	cancel context.CancelFunc
	done   chan struct{}
}

// Manager runs at most one scan at a time.
type Manager struct {
	cfg Config
	now func() time.Time

	mu      sync.Mutex
	results map[string]*Result
	current *Result
	running *job
}

func New(cfg Config) (*Manager, error) {
	if cfg.Binary == "" {
		if p, err := exec.LookPath("clamscan"); err == nil {
			cfg.Binary = p
		}
	}
	if cfg.Home == "" {
		cfg.Home, _ = os.UserHomeDir()
	}
	if err := os.MkdirAll(filepath.Join(cfg.StateDir, "scans"), 0o700); err != nil {
		return nil, err
	}
	m := &Manager{cfg: cfg, now: time.Now, results: map[string]*Result{}}
	m.loadSaved()
	return m, nil
}

// Available reports whether a scanner binary was found.
func (m *Manager) Available() bool {
	if m.cfg.Binary == "" {
		return false
	}
	_, err := os.Stat(m.cfg.Binary)
	return err == nil
}

func (m *Manager) dbArgs() []string {
	if m.cfg.DBDir != "" {
		return []string{"-d", m.cfg.DBDir}
	}
	return nil
}

var versionLine = regexp.MustCompile(`^ClamAV\s+(\S+?)(?:/(\d+)/(.+))?$`)

// parseVersion reads "ClamAV 1.4.3/28146/Tue Oct  7 08:30:04 2026" (the tail is absent without signatures).
func parseVersion(out string) (ver, db string, date time.Time, ok bool) {
	m := versionLine.FindStringSubmatch(strings.TrimSpace(out))
	if m == nil {
		return "", "", time.Time{}, false
	}
	ver, db = m[1], m[2]
	if m[3] != "" {
		for _, layout := range []string{"Mon Jan _2 15:04:05 2006", "Mon Jan 2 15:04:05 2006"} {
			if t, err := time.Parse(layout, strings.TrimSpace(m[3])); err == nil {
				date = t
				break
			}
		}
	}
	return ver, db, date, true
}

// Info asks the scanner for its version and signature date.
func (m *Manager) Info(ctx context.Context) Info {
	info := Info{Engine: "clamav", SignatureAgeDays: -1}
	m.mu.Lock()
	if m.current != nil && m.current.State == StateRunning {
		info.Running = m.current.ID
	}
	m.mu.Unlock()
	if !m.Available() {
		info.Reason = ErrUnavailable.Error()
		return info
	}
	info.Available = true
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, m.cfg.Binary, append(m.dbArgs(), "--version")...).Output()
	if err != nil {
		info.Available = false
		info.Reason = "the scanner did not start: " + err.Error()
		return info
	}
	ver, db, date, ok := parseVersion(string(out))
	if !ok {
		info.Reason = "unrecognised scanner output"
		return info
	}
	info.Version, info.SignatureDB = ver, db
	if !date.IsZero() {
		info.SignatureDate = date.UTC().Format(time.RFC3339)
		info.SignatureAgeDays = int(m.now().Sub(date).Hours() / 24)
		info.Stale = info.SignatureAgeDays > StaleAfterDays
	}
	return info
}

func newID(t time.Time) string {
	var b [3]byte
	_, _ = rand.Read(b[:])
	return t.UTC().Format("20060102-150405") + "-" + hex.EncodeToString(b[:])
}

// quickPaths are the places malware usually lands first.
func (m *Manager) quickPaths() []string {
	cands := m.cfg.Quick
	if cands == nil {
		h := m.cfg.Home
		cands = []string{filepath.Join(h, "Downloads"), "/tmp", "/var/tmp", filepath.Join(h, ".local/bin"),
			filepath.Join(h, "bin"), "/usr/local/bin", filepath.Join(h, ".config/autostart")}
	}
	var out []string
	for _, p := range cands {
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			out = append(out, p)
		}
	}
	return out
}

// resolve turns a scope (and path for "path") into folders to scan and extra clamscan flags.
func (m *Manager) resolve(scope, path string) (paths, extra []string, err error) {
	switch scope {
	case "quick":
		paths = m.quickPaths()
		if len(paths) == 0 {
			return nil, nil, errors.New("none of the quick-scan folders exist on this node")
		}
	case "home":
		if m.cfg.Home == "" {
			return nil, nil, errors.New("this node has no home folder")
		}
		paths = []string{m.cfg.Home}
	case "full":
		paths = []string{"/"}
		// Pseudo file systems hold no files; other mounts (backup drives, archives) are scanned on request via "path".
		extra = []string{"--cross-fs=no", "--exclude-dir=^/proc/", "--exclude-dir=^/sys/", "--exclude-dir=^/dev/", "--exclude-dir=^/run/"}
	case "path":
		if path == "" || strings.ContainsRune(path, 0) || !filepath.IsAbs(path) {
			return nil, nil, errors.New("path must be an absolute folder or file path")
		}
		path = filepath.Clean(path)
		if _, serr := os.Stat(path); serr != nil {
			return nil, nil, fmt.Errorf("cannot read %s: %v", path, serr)
		}
		paths = []string{path}
	default:
		return nil, nil, ErrBadScope
	}
	return paths, extra, nil
}

// Start begins a scan in the background and returns its id.
func (m *Manager) Start(scope, path string) (string, error) {
	if !m.Available() {
		return "", ErrUnavailable
	}
	paths, extra, err := m.resolve(scope, path)
	if err != nil {
		return "", err
	}
	m.mu.Lock()
	busy := m.running != nil
	m.mu.Unlock()
	if busy {
		return "", ErrBusy
	}
	ver := m.Info(context.Background()).Version

	m.mu.Lock()
	if m.running != nil { // another start won the race while we asked for the version
		m.mu.Unlock()
		return "", ErrBusy
	}
	now := m.now()
	r := &Result{ID: newID(now), State: StateRunning, Scope: scope, Paths: paths, Started: now.UTC(),
		Findings: []Finding{}, ErrorSamples: []string{}, EngineVersion: ver}
	ctx, cancel := context.WithCancel(context.Background())
	j := &job{cancel: cancel, done: make(chan struct{})}
	m.results[r.ID], m.current, m.running = r, r, j
	m.mu.Unlock()

	args := append([]string{"--stdout", "--no-summary", "-r", "--follow-dir-symlinks=0", "--follow-file-symlinks=0",
		"--max-filesize=100M", "--max-scansize=400M"}, m.dbArgs()...)
	args = append(append(args, extra...), paths...)
	go m.run(ctx, j, r, args)
	return r.ID, nil
}

// handleLine updates r from one line of clamscan output: "<path>: OK", "<path>: <sig> FOUND",
// "<path>: Access denied" or "<path>: <why> ERROR".
func (m *Manager) handleLine(r *Result, line string) {
	i := strings.LastIndex(line, ": ")
	if i < 0 {
		return
	}
	path, res := line[:i], strings.TrimSpace(line[i+2:])
	m.mu.Lock()
	defer m.mu.Unlock()
	r.Current = path
	switch {
	case res == "OK" || res == "Empty file":
		r.Scanned++
	case strings.HasSuffix(res, " FOUND"):
		r.Scanned++
		if len(r.Findings) < maxFindings {
			r.Findings = append(r.Findings, Finding{Path: path, Signature: strings.TrimSuffix(res, " FOUND")})
		} else {
			r.FindingsCut = true
		}
	case res == "Symbolic link" || res == "Excluded" || res == "Not a regular file":
		r.Skipped++ // known to be harmless: links are not followed on purpose, excluded folders were asked for
	default:
		// "Access denied", "<why> ERROR" and anything this code does not recognise. A file that was not
		// checked must never disappear silently, so unknown results count as errors, not as clean.
		r.Errors++
		if len(r.ErrorSamples) < maxErrorLines {
			r.ErrorSamples = append(r.ErrorSamples, path+": "+strings.TrimSuffix(res, " ERROR"))
		}
	}
}

// engineError picks the first useful complaint out of clamscan's stderr.
func engineError(stderr string) string {
	for _, l := range strings.Split(stderr, "\n") {
		l = strings.TrimSpace(l)
		if strings.HasPrefix(l, "ERROR:") || strings.Contains(l, "LibClamAV Error") {
			if len(l) > 200 {
				l = l[:200]
			}
			return l
		}
	}
	return ""
}

type tailBuf struct {
	mu sync.Mutex
	b  []byte
}

func (t *tailBuf) Write(p []byte) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.b = append(t.b, p...)
	if len(t.b) > 16<<10 {
		t.b = t.b[len(t.b)-16<<10:]
	}
	return len(p), nil
}

func (t *tailBuf) String() string { t.mu.Lock(); defer t.mu.Unlock(); return string(t.b) }

func (m *Manager) run(ctx context.Context, j *job, r *Result, args []string) {
	defer close(j.done)
	state, msg := StateDone, ""
	finish := func() {
		m.mu.Lock()
		t := m.now().UTC()
		r.State, r.Message, r.Finished, r.Current = state, msg, &t, ""
		m.running = nil
		m.mu.Unlock()
		m.save(r)
		m.prune()
	}
	defer finish()

	cmd := exec.CommandContext(ctx, m.cfg.Binary, args...)
	// Own process group, so cancelling reaches anything the scanner started, not just the scanner.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = 5 * time.Second
	stderr := &tailBuf{}
	cmd.Stderr = stderr
	out, err := cmd.StdoutPipe()
	if err == nil {
		err = cmd.Start()
	}
	if err != nil {
		state, msg = StateFailed, "could not start the scanner: "+err.Error()
		return
	}
	// Scanning is background work: keep the machine usable.
	_ = syscall.Setpriority(syscall.PRIO_PROCESS, cmd.Process.Pid, 19)

	// If something keeps the pipe open after a cancel, stop waiting for it.
	go func() {
		<-ctx.Done()
		time.Sleep(3 * time.Second)
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		out.Close()
	}()
	sc := bufio.NewScanner(out)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		m.handleLine(r, sc.Text())
	}
	_, _ = io.Copy(io.Discard, out) // a line over the limit must not leave the scanner blocked on a full pipe
	werr := cmd.Wait()

	m.mu.Lock()
	scanned, findings := r.Scanned, len(r.Findings)
	m.mu.Unlock()
	var ee *exec.ExitError
	switch {
	case ctx.Err() != nil:
		state = StateCancelled
	case werr == nil:
	case errors.As(werr, &ee) && ee.ExitCode() == 1: // 1 = something was found
	case errors.As(werr, &ee) && ee.ExitCode() == 2 && scanned > 0: // some files could not be read
	default:
		state = StateFailed
		msg = engineError(stderr.String())
		if msg == "" {
			msg = "the scanner stopped unexpectedly: " + werr.Error()
		}
	}
	if state == StateDone && scanned == 0 && findings == 0 {
		if e := engineError(stderr.String()); e != "" {
			state, msg = StateFailed, e
		}
	}
}

func cloneResult(r *Result) Result {
	c := *r
	c.Paths = append([]string(nil), r.Paths...)
	c.Findings = append([]Finding{}, r.Findings...)
	c.ErrorSamples = append([]string{}, r.ErrorSamples...)
	return c
}

// Get returns a copy of the scan's current state.
func (m *Manager) Get(id string) (Result, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.results[id]
	if !ok {
		return Result{}, false
	}
	return cloneResult(r), true
}

// List returns recent scans, newest first.
func (m *Manager) List() []Result {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]Result, 0, len(m.results))
	for _, r := range m.results {
		c := cloneResult(r)
		c.Findings = nil // summaries only; fetch one scan for its findings
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Started.After(out[j].Started) })
	return out
}

// Cancel stops a running scan. It reports whether the id was the running scan.
func (m *Manager) Cancel(id string) bool {
	m.mu.Lock()
	j, r := m.running, m.current
	m.mu.Unlock()
	if j == nil || r == nil || r.ID != id {
		return false
	}
	j.cancel()
	<-j.done
	return true
}

// Wait blocks until the running scan (if any) ends. For tests and shutdown.
func (m *Manager) Wait() {
	m.mu.Lock()
	j := m.running
	m.mu.Unlock()
	if j != nil {
		<-j.done
	}
}

func (m *Manager) scanFile(id string) string {
	return filepath.Join(m.cfg.StateDir, "scans", id+".json")
}

func (m *Manager) save(r *Result) {
	m.mu.Lock()
	raw, err := json.Marshal(cloneResult(r))
	m.mu.Unlock()
	if err != nil {
		return
	}
	tmp := m.scanFile(r.ID) + ".tmp"
	if os.WriteFile(tmp, raw, 0o600) == nil {
		_ = os.Rename(tmp, m.scanFile(r.ID))
	}
}

func (m *Manager) loadSaved() {
	files, _ := filepath.Glob(filepath.Join(m.cfg.StateDir, "scans", "*.json"))
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var r Result
		if json.Unmarshal(raw, &r) != nil || r.ID == "" || r.State == StateRunning {
			continue // a scan that was running when the agent stopped has no usable result
		}
		m.results[r.ID] = &r
	}
	m.prune()
}

// prune keeps the newest keepResults finished scans, in memory and on disk.
func (m *Manager) prune() {
	m.mu.Lock()
	defer m.mu.Unlock()
	var done []*Result
	for _, r := range m.results {
		if r.State != StateRunning {
			done = append(done, r)
		}
	}
	sort.Slice(done, func(i, j int) bool { return done[i].Started.After(done[j].Started) })
	for _, r := range done[min(len(done), keepResults):] {
		delete(m.results, r.ID)
		_ = os.Remove(m.scanFile(r.ID))
	}
}
