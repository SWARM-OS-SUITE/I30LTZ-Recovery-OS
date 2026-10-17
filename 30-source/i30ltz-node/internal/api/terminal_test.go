package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/sysinfo"
	"i30ltz/node/internal/term"
	"i30ltz/node/internal/ws"
)

func newTerminalServer(t *testing.T, enable bool, max int) (*httptest.Server, string) {
	t.Helper()
	store, err := auth.Open(filepath.Join(t.TempDir(), "cfg"))
	if err != nil {
		t.Fatal(err)
	}
	col := sysinfo.NewCollector()
	srv := New(store, col, sysinfo.NewSampler(col, 100*time.Millisecond), "test")
	if enable {
		srv.EnableTerminal(max, "smallest")
	}
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return ts, pairToken(t, ts)
}

func isolatedTmux(t *testing.T) {
	t.Helper()
	if !term.Available() {
		t.Skip("tmux not installed")
	}
	t.Setenv("TMUX_TMPDIR", t.TempDir())
	t.Setenv("TMUX", "")
	t.Cleanup(func() { exec.Command("tmux", "kill-server").Run() })
}

func dialTerminal(t *testing.T, ts *httptest.Server, token, query string) *ws.Conn {
	t.Helper()
	c, resp, err := ws.Dial("ws"+strings.TrimPrefix(ts.URL, "http")+"/v1/terminal"+query, http.Header{"Authorization": {"Bearer " + token}})
	if err != nil {
		code := 0
		if resp != nil {
			code = resp.StatusCode
		}
		t.Fatalf("dial: %v (HTTP %d)", err, code)
	}
	c.SetIdle(5 * time.Second)
	t.Cleanup(func() { c.Close(ws.CloseNormal, "") })
	return c
}

// syncBuf is a log sink that the test can read while the server goroutine is still writing.
type syncBuf struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuf) Write(p []byte) (int, error) { s.mu.Lock(); defer s.mu.Unlock(); return s.b.Write(p) }
func (s *syncBuf) String() string              { s.mu.Lock(); defer s.mu.Unlock(); return s.b.String() }

// screen accumulates what a client receives so tests can wait for text.
type screen struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func watch(c *ws.Conn) *screen {
	s := &screen{}
	go func() {
		for {
			op, data, err := c.ReadMessage()
			if err != nil {
				return
			}
			if op == ws.OpBinary {
				s.mu.Lock()
				s.buf.Write(data)
				s.mu.Unlock()
			}
		}
	}()
	return s
}

func (s *screen) waitFor(t *testing.T, want string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		s.mu.Lock()
		ok := strings.Contains(s.buf.String(), want)
		s.mu.Unlock()
		if ok {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	t.Fatalf("timed out waiting for %q; got %q", want, s.buf.String())
}

func TestTerminalIsOffByDefault(t *testing.T) {
	ts, token := newTerminalServer(t, false, 0)
	for _, path := range []string{"/v1/terminal", "/v1/terminal/sessions"} {
		resp := get(t, ts, path, token)
		var body struct{ Error string }
		json.NewDecoder(resp.Body).Decode(&body)
		if resp.StatusCode != 404 || !strings.Contains(body.Error, "--terminal") {
			t.Errorf("%s: %d %q", path, resp.StatusCode, body.Error)
		}
	}
	var caps struct{ Features Features }
	json.NewDecoder(get(t, ts, "/v1/capabilities", token).Body).Decode(&caps)
	if caps.Features.Terminal {
		t.Error("capabilities must say terminal=false when not enabled")
	}
}

func TestTerminalNeedsAToken(t *testing.T) {
	ts, _ := newTerminalServer(t, true, 4)
	for _, path := range []string{"/v1/terminal", "/v1/terminal/sessions"} {
		if resp := get(t, ts, path, ""); resp.StatusCode != 401 {
			t.Errorf("%s without token: %d want 401", path, resp.StatusCode)
		}
	}
}

func TestTerminalRejectsBadInputBeforeUpgrading(t *testing.T) {
	isolatedTmux(t)
	ts, token := newTerminalServer(t, true, 4)
	for _, q := range []string{"?session=a;rm%20-rf", "?session=../x", "?session=" + strings.Repeat("x", 33), "?cols=abc", "?rows=1.5"} {
		if resp := get(t, ts, "/v1/terminal"+q, token); resp.StatusCode != 400 {
			t.Errorf("%s: %d want 400", q, resp.StatusCode)
		}
	}
	// A valid request that is not a WebSocket upgrade is refused by the upgrade step, not run.
	if resp := get(t, ts, "/v1/terminal?session=ok", token); resp.StatusCode != 400 {
		t.Errorf("plain GET: %d want 400", resp.StatusCode)
	}
	var caps struct{ Features Features }
	json.NewDecoder(get(t, ts, "/v1/capabilities", token).Body).Decode(&caps)
	if !caps.Features.Terminal {
		t.Error("capabilities should say terminal=true when enabled and tmux exists")
	}
}

func TestTypedCommandRoundTripAndResize(t *testing.T) {
	isolatedTmux(t)
	ts, token := newTerminalServer(t, true, 4)
	c := dialTerminal(t, ts, token, "?session=phone&cols=100&rows=30")
	out := watch(c)

	c.WriteMessage(ws.OpBinary, []byte("echo $((6*7))\n"))
	out.waitFor(t, "42")

	c.WriteMessage(ws.OpText, []byte(`{"type":"resize","cols":120,"rows":40}`))
	c.WriteMessage(ws.OpText, []byte(`not json, ignored`))
	deadline := time.Now().Add(5 * time.Second)
	for {
		o, _ := exec.Command("tmux", "list-clients", "-t", "phone", "-F", "#{client_width}x#{client_height}").Output()
		if strings.TrimSpace(string(o)) == "120x40" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("client size never became 120x40, last %q", o)
		}
		time.Sleep(50 * time.Millisecond)
	}

	resp := get(t, ts, "/v1/terminal/sessions", token)
	var list []term.Session
	json.NewDecoder(resp.Body).Decode(&list)
	if len(list) != 1 || list[0].Name != "phone" || list[0].Attached != 1 {
		t.Errorf("sessions: %+v", list)
	}
}

func TestPhoneAndPCMirrorEachOther(t *testing.T) {
	isolatedTmux(t)
	ts, token := newTerminalServer(t, true, 4)
	phone1 := dialTerminal(t, ts, token, "?session=shared")
	out1 := watch(phone1)
	out1.waitFor(t, "$")
	phone2 := dialTerminal(t, ts, token, "?session=shared")
	out2 := watch(phone2)

	phone1.WriteMessage(ws.OpBinary, []byte("echo from-phone-one\n"))
	out2.waitFor(t, "from-phone-one") // a second client sees what the first typed

	// The PC is just another tmux client typing into the same pane.
	if err := exec.Command("tmux", "send-keys", "-t", "shared", "echo from-the-pc", "Enter").Run(); err != nil {
		t.Fatal(err)
	}
	out1.waitFor(t, "from-the-pc")
	out2.waitFor(t, "from-the-pc")
}

func TestSessionSurvivesDisconnectAndAuditLogHasNoContent(t *testing.T) {
	isolatedTmux(t)
	logs := &syncBuf{}
	log.SetOutput(logs)
	defer log.SetOutput(io.Discard)

	ts, token := newTerminalServer(t, true, 4)
	c := dialTerminal(t, ts, token, "?session=keep")
	out := watch(c)
	c.WriteMessage(ws.OpBinary, []byte("echo SECRET-MARKER-9\n"))
	out.waitFor(t, "SECRET-MARKER-9")
	c.Close(ws.CloseNormal, "")

	deadline := time.Now().Add(5 * time.Second)
	for {
		o, _ := exec.Command("tmux", "list-sessions", "-F", "#{session_name}:#{session_attached}").Output()
		if strings.TrimSpace(string(o)) == "keep:0" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("session should survive with 0 clients, got %q", o)
		}
		time.Sleep(50 * time.Millisecond)
	}
	// Give the handler a moment to write its "left" line.
	for i := 0; i < 100 && !strings.Contains(logs.String(), "left session"); i++ {
		time.Sleep(20 * time.Millisecond)
	}
	text := logs.String()
	if !strings.Contains(text, `"test phone" attached to tmux session "keep"`) || !strings.Contains(text, "left session") {
		t.Errorf("audit lines missing: %q", text)
	}
	if strings.Contains(text, "SECRET-MARKER-9") || strings.Contains(text, token) {
		t.Errorf("the log must not contain typed text or the token: %q", text)
	}
}

func TestTooManyTerminalsAreRefused(t *testing.T) {
	isolatedTmux(t)
	ts, token := newTerminalServer(t, true, 2)
	dialTerminal(t, ts, token, "?session=a")
	dialTerminal(t, ts, token, "?session=b")
	if resp := get(t, ts, "/v1/terminal?session=c", token); resp.StatusCode != 429 {
		t.Fatalf("third terminal: %d want 429", resp.StatusCode)
	}
}

func TestPairingAttemptsAndRejectionsAreLoggedWithoutSecrets(t *testing.T) {
	logs := &syncBuf{}
	log.SetOutput(logs)
	defer log.SetOutput(io.Discard)
	ts, token := newTerminalServer(t, false, 0)

	// An unpaired caller is told no, and the log says who asked for what (once per minute).
	for i := 0; i < 3; i++ {
		if resp := get(t, ts, "/v1/telemetry", ""); resp.StatusCode != 401 {
			t.Fatalf("status %d", resp.StatusCode)
		}
	}
	if n := strings.Count(logs.String(), "asked for /v1/telemetry without a valid token"); n != 1 {
		t.Errorf("a repeated rejection must be logged once, got %d: %q", n, logs.String())
	}
	if resp := get(t, ts, "/v1/processes", "not-a-real-token"); resp.StatusCode != 401 {
		t.Fatal("bad token must be refused")
	}
	if text := logs.String(); !strings.Contains(text, "/v1/processes") || strings.Contains(text, "not-a-real-token") {
		t.Errorf("a different path is logged separately and the offered token never is: %q", text)
	}

	// A paired caller is not logged as rejected.
	before := logs.String()
	get(t, ts, "/v1/telemetry", token)
	if logs.String() != before {
		t.Error("a valid request must not produce a rejection line")
	}

	// A wrong pairing code is logged without the code.
	resp, _ := http.Post(ts.URL+"/v1/pair", "application/json", strings.NewReader(`{"code":"ZZZZ-9999","label":"x"}`))
	resp.Body.Close()
	if text := logs.String(); !strings.Contains(text, "with a wrong or expired code") || strings.Contains(text, "ZZZZ-9999") {
		t.Errorf("pairing failure log: %q", text)
	}
	if !strings.Contains(logs.String(), `pair: "test phone" paired from`) {
		t.Errorf("the earlier successful pairing should be logged too: %q", logs.String())
	}
}
