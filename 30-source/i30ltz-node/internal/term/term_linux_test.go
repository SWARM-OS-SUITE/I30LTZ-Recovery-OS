package term

import (
	"os"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"
)

// collector drains a PTY in the background so tests can wait for text to appear.
type collector struct {
	mu  sync.Mutex
	buf strings.Builder
}

func collect(p *PTY) *collector {
	c := &collector{}
	go func() {
		b := make([]byte, 4096)
		for {
			n, err := p.Read(b)
			if n > 0 {
				c.mu.Lock()
				c.buf.Write(b[:n])
				c.mu.Unlock()
			}
			if err != nil {
				return
			}
		}
	}()
	return c
}

func (c *collector) text() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.buf.String()
}

func (c *collector) waitFor(t *testing.T, want string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if strings.Contains(c.text(), want) {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %q; output so far: %q", want, c.text())
}

func TestStartGivesTheChildTheRequestedSize(t *testing.T) {
	p, err := Start(exec.Command("sh", "-c", "stty size"), 100, 30)
	if err != nil {
		t.Fatal(err)
	}
	defer p.Close()
	collect(p).waitFor(t, "30 100")
}

func TestResizeReachesTheChild(t *testing.T) {
	p, err := Start(exec.Command("sh", "-c", "read x; stty size"), 80, 24)
	if err != nil {
		t.Fatal(err)
	}
	defer p.Close()
	out := collect(p)
	if err := p.Resize(120, 40); err != nil {
		t.Fatal(err)
	}
	p.Write([]byte("\n"))
	out.waitFor(t, "40 120")
	if err := p.Resize(0, 10); err == nil {
		t.Error("a zero-width terminal should be refused")
	}
}

func TestKeystrokesAreEchoedAndCtrlCStopsTheChild(t *testing.T) {
	p, err := Start(exec.Command("sleep", "60"), 80, 24)
	if err != nil {
		t.Fatal(err)
	}
	out := collect(p)
	p.Write([]byte("hi"))
	out.waitFor(t, "hi")  // the terminal itself echoes typed characters
	p.Write([]byte{0x03}) // Ctrl-C works only if the pty is the child's controlling terminal
	done := make(chan error, 1)
	go func() { done <- p.Wait() }()
	select {
	case err := <-done:
		if err == nil || !strings.Contains(err.Error(), "interrupt") {
			t.Fatalf("expected SIGINT exit, got %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Ctrl-C did not stop the child")
	}
}

func TestCloseHangsUpTheChild(t *testing.T) {
	p, err := Start(exec.Command("sleep", "60"), 80, 24)
	if err != nil {
		t.Fatal(err)
	}
	p.Close()
	p.Close() // idempotent
	done := make(chan struct{})
	go func() { p.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("child survived Close")
	}
}

func TestParseSessionsSkipsUnacceptableNames(t *testing.T) {
	got := parseSessions([]byte("main\t2\t1\t1700000000\nbad name\t1\t0\t1\n0\t1\t0\t5\nx;y\t1\t0\t1\n"))
	if len(got) != 2 || got[0] != (Session{Name: "main", Windows: 2, Attached: 1, Created: 1700000000}) || got[1].Name != "0" {
		t.Fatalf("got %+v", got)
	}
	if len(parseSessions(nil)) != 0 {
		t.Error("empty output should give an empty list")
	}
}

func TestValidSession(t *testing.T) {
	for _, ok := range []string{"main", "a", "work-1", "A_b", strings.Repeat("x", 32)} {
		if !ValidSession(ok) {
			t.Errorf("%q should be valid", ok)
		}
	}
	for _, bad := range []string{"", "a b", "a;b", "../x", "a.b", "a:b", strings.Repeat("x", 33), "é"} {
		if ValidSession(bad) {
			t.Errorf("%q should be refused", bad)
		}
	}
}

func TestTerminalEnv(t *testing.T) {
	got := TerminalEnv([]string{"PATH=/bin", "TERM=dumb", "TMUX=/tmp/x,1,0", "TMUX_PANE=%1", "HOME=/h"})
	joined := strings.Join(got, "|")
	for _, want := range []string{"PATH=/bin", "HOME=/h", "TERM=xterm-256color", "LANG=C.UTF-8"} {
		if !strings.Contains(joined, want) {
			t.Errorf("missing %s in %s", want, joined)
		}
	}
	for _, bad := range []string{"TERM=dumb", "TMUX=", "TMUX_PANE="} {
		if strings.Contains(joined, bad) {
			t.Errorf("%s should have been removed", bad)
		}
	}
	if joined2 := strings.Join(TerminalEnv([]string{"LANG=de_DE.UTF-8"}), "|"); strings.Contains(joined2, "C.UTF-8") {
		t.Error("an existing locale must be kept")
	}
}

// isolatedTmux points tmux at a private socket directory so tests never touch the real tmux server.
func isolatedTmux(t *testing.T) {
	t.Helper()
	if !Available() {
		t.Skip("tmux not installed")
	}
	t.Setenv("TMUX_TMPDIR", t.TempDir())
	t.Setenv("TMUX", "")
	t.Cleanup(func() { exec.Command("tmux", "kill-server").Run() })
}

func attach(t *testing.T, name string) (*PTY, *collector) {
	t.Helper()
	p, err := Start(AttachCommand(name, "smallest"), 80, 24)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(p.Close)
	return p, collect(p)
}

func TestTmuxAttachCreatesSessionThatSurvivesDetach(t *testing.T) {
	isolatedTmux(t)
	if list, err := Sessions(); err != nil || len(list) != 0 {
		t.Fatalf("no server yet: %v %v", list, err)
	}
	p, out := attach(t, "phone")
	p.Write([]byte("echo $((6*7))\n"))
	out.waitFor(t, "42")

	list, err := Sessions()
	if err != nil || len(list) != 1 || list[0].Name != "phone" || list[0].Attached != 1 {
		t.Fatalf("sessions while attached: %+v %v", list, err)
	}
	if o, _ := exec.Command("tmux", "show-options", "-t", "phone", "window-size").Output(); !strings.Contains(string(o), "smallest") {
		t.Errorf("window-size should be smallest, got %q", o)
	}

	p.Close() // the phone disconnects
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if l, _ := Sessions(); len(l) == 1 && l[0].Attached == 0 {
			return // detached, session still alive
		}
		time.Sleep(50 * time.Millisecond)
	}
	l, _ := Sessions()
	t.Fatalf("session should survive the client leaving with 0 attached, got %+v", l)
}

func TestTwoClientsOnOneSessionSeeEachOthersInput(t *testing.T) {
	isolatedTmux(t)
	a, outA := attach(t, "shared")
	outA.waitFor(t, "$") // shell prompt is up
	b, outB := attach(t, "shared")

	a.Write([]byte("echo typed-on-A\n"))
	outB.waitFor(t, "typed-on-A") // B mirrors what A typed
	b.Write([]byte("echo typed-on-B\n"))
	outA.waitFor(t, "typed-on-B")

	// The "PC" side is simply another tmux client typing into the same pane.
	if err := exec.Command("tmux", "send-keys", "-t", "shared", "echo from-the-pc", "Enter").Run(); err != nil {
		t.Fatal(err)
	}
	outA.waitFor(t, "from-the-pc")
	outB.waitFor(t, "from-the-pc")

	if l, _ := Sessions(); len(l) != 1 || l[0].Attached != 2 {
		t.Errorf("want one session with 2 clients, got %+v", l)
	}
}

func TestMain(m *testing.M) {
	os.Unsetenv("TMUX") // tests may be run from inside tmux
	os.Exit(m.Run())
}

func TestWindowSizeModeIsValidatedAndDefaultsToAnExactMirror(t *testing.T) {
	for _, ok := range []string{"smallest", "latest", "largest"} {
		if !ValidWindowSize(ok) {
			t.Errorf("%s should be valid", ok)
		}
	}
	for _, bad := range []string{"", "manual; kill-server", "Smallest"} {
		if ValidWindowSize(bad) {
			t.Errorf("%q should be refused", bad)
		}
	}
	args := strings.Join(AttachCommand("x", "nonsense").Args, " ")
	if !strings.Contains(args, "window-size smallest") {
		t.Errorf("an invalid mode must fall back to smallest, got %q", args)
	}
}

// With "smallest" a wide client must not make a narrow client see only a slice of the window.
func TestNarrowAndWideClientsSeeTheSameLines(t *testing.T) {
	isolatedTmux(t)
	narrow, outN := attach(t, "same")
	outN.waitFor(t, "$")
	wide, err := Start(AttachCommand("same", "smallest"), 140, 40)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(wide.Close)
	collect(wide)
	time.Sleep(500 * time.Millisecond)
	wide.Write([]byte("echo seen-by-the-narrow-client\n"))
	outN.waitFor(t, "seen-by-the-narrow-client")
	o, _ := exec.Command("tmux", "display-message", "-p", "-t", "same", "#{window_width}x#{window_height}").Output()
	if strings.TrimSpace(string(o)) != "80x23" { // 24 rows minus the tmux status line
		t.Errorf("the window should follow the smallest client (80x23), got %s", o)
	}
	_ = narrow
}

// A systemd user service (or any minimal environment) has no locale. tmux 3.5 then replaces the TAB in `-F` output with
// "_", every line of list-sessions failed to parse, and the phone's session list came back silently empty.
func TestSessionsAreListedWhenTheAgentHasNoLocaleAndNoTerm(t *testing.T) {
	if !Available() {
		t.Skip("tmux is not installed")
	}
	dir, err := os.MkdirTemp("", "tm") // short: tmux's socket path must stay under 108 bytes
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	saved := map[string]string{}
	for _, k := range []string{"LANG", "LC_ALL", "LC_CTYPE", "TERM", "TMUX", "TMUX_PANE", "TMUX_TMPDIR"} {
		if v, ok := os.LookupEnv(k); ok {
			saved[k] = v
		}
		os.Unsetenv(k)
	}
	t.Cleanup(func() {
		for _, k := range []string{"LANG", "LC_ALL", "LC_CTYPE", "TERM", "TMUX", "TMUX_PANE", "TMUX_TMPDIR"} {
			if v, ok := saved[k]; ok {
				os.Setenv(k, v)
			} else {
				os.Unsetenv(k)
			}
		}
	})
	os.Setenv("TMUX_TMPDIR", dir)

	start := exec.Command("tmux", "-u", "new-session", "-d", "-s", "locale-test")
	start.Env = TerminalEnv(os.Environ())
	if out, err := start.CombinedOutput(); err != nil {
		t.Fatalf("could not start tmux: %v: %s", err, out)
	}
	t.Cleanup(func() {
		kill := exec.Command("tmux", "kill-server")
		kill.Env = TerminalEnv(os.Environ())
		kill.Run()
	})

	list, err := Sessions() // runs with the stripped environment set above
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].Name != "locale-test" || list[0].Windows != 1 {
		t.Fatalf("expected the one session %q, got %+v", "locale-test", list)
	}
}
