package api

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/sysinfo"
)

func newTestServer(t *testing.T) (*httptest.Server, *auth.Store) {
	t.Helper()
	store, err := auth.Open(filepath.Join(t.TempDir(), "cfg"))
	if err != nil {
		t.Fatal(err)
	}
	col := sysinfo.NewCollector()
	srv := New(store, col, sysinfo.NewSampler(col, 100*time.Millisecond), "test")
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return ts, store
}

func pairToken(t *testing.T, ts *httptest.Server) string {
	t.Helper()
	resp, err := http.Get(ts.URL + "/v1/pairing/new")
	if err != nil {
		t.Fatal(err)
	}
	var code struct{ Code string }
	json.NewDecoder(resp.Body).Decode(&code)
	resp.Body.Close()
	if resp.StatusCode != 200 || code.Code == "" {
		t.Fatalf("pairing/new: %d %q", resp.StatusCode, code.Code)
	}
	body := fmt.Sprintf(`{"code":%q,"label":"test phone"}`, code.Code)
	resp, err = http.Post(ts.URL+"/v1/pair", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out struct{ Token string }
	json.NewDecoder(resp.Body).Decode(&out)
	if resp.StatusCode != 200 || out.Token == "" {
		t.Fatalf("pair: %d", resp.StatusCode)
	}
	return out.Token
}

func get(t *testing.T, ts *httptest.Server, path, token string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("GET", ts.URL+path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func TestEverythingExceptPairingNeedsAToken(t *testing.T) {
	ts, _ := newTestServer(t)
	for _, p := range []string{"/v1/capabilities", "/v1/telemetry", "/v1/events", "/v1/processes"} {
		if resp := get(t, ts, p, ""); resp.StatusCode != 401 {
			t.Errorf("%s without token: %d, want 401", p, resp.StatusCode)
		}
	}
	resp, _ := http.Post(ts.URL+"/v1/processes/123/kill", "application/json", nil)
	if resp.StatusCode != 401 {
		t.Errorf("kill without token: %d, want 401", resp.StatusCode)
	}
}

func TestPairingCodeOnlyFromLoopback(t *testing.T) {
	store, _ := auth.Open(filepath.Join(t.TempDir(), "c"))
	col := sysinfo.NewCollector()
	h := New(store, col, sysinfo.NewSampler(col, time.Second), "t").Handler()
	for addr, want := range map[string]int{"127.0.0.1:1": 200, "100.82.1.20:1": 403} {
		req := httptest.NewRequest("GET", "/v1/pairing/new", nil)
		req.RemoteAddr = addr
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != want {
			t.Errorf("from %s: %d want %d", addr, rec.Code, want)
		}
		if want == 403 && strings.Contains(rec.Body.String(), "code\":\"") {
			t.Error("a refused request must not leak a code")
		}
	}
}

func TestPairBadCodeAndLockout(t *testing.T) {
	ts, _ := newTestServer(t)
	var last int
	for i := 0; i < 5; i++ {
		resp, _ := http.Post(ts.URL+"/v1/pair", "application/json", strings.NewReader(`{"code":"AAAA-AAAA"}`))
		last = resp.StatusCode
		if i < 4 && last != 401 {
			t.Fatalf("attempt %d: %d want 401", i+1, last)
		}
	}
	if last != 429 {
		t.Fatalf("5th wrong code: %d want 429", last)
	}
	if resp, _ := http.Post(ts.URL+"/v1/pair", "application/json", strings.NewReader(`not json`)); resp.StatusCode != 400 {
		t.Errorf("bad body: %d want 400", resp.StatusCode)
	}
}

func TestPairedFlow(t *testing.T) {
	ts, _ := newTestServer(t)
	token := pairToken(t, ts)

	var caps struct {
		Agent    string
		API      int
		Features Features
	}
	json.NewDecoder(get(t, ts, "/v1/capabilities", token).Body).Decode(&caps)
	if caps.Agent != "i30ltz-node" || caps.API != APIVersion {
		t.Fatalf("capabilities: %+v", caps)
	}
	f := caps.Features
	if !(f.Telemetry && f.Events && f.Processes && f.Kill) {
		t.Errorf("implemented features should be true: %+v", f)
	}
	if f.Scan || f.Optimize || f.Terminal || f.Jobs {
		t.Errorf("unimplemented features must be reported false: %+v", f)
	}

	var tel sysinfo.Telemetry
	json.NewDecoder(get(t, ts, "/v1/telemetry", token).Body).Decode(&tel)
	if tel.Hostname == "" || tel.RAMTotalMB <= 0 {
		t.Errorf("telemetry looks empty: %+v", tel)
	}

	var procs []sysinfo.Process
	json.NewDecoder(get(t, ts, "/v1/processes?limit=5", token).Body).Decode(&procs)
	if len(procs) == 0 || len(procs) > 5 {
		t.Errorf("processes limit: got %d", len(procs))
	}
	if resp := get(t, ts, "/v1/processes?limit=abc", token); resp.StatusCode != 400 {
		t.Errorf("bad limit: %d", resp.StatusCode)
	}
}

func post(t *testing.T, ts *httptest.Server, path, token string) *http.Response {
	req, _ := http.NewRequest("POST", ts.URL+path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func TestKillEndpoint(t *testing.T) {
	ts, _ := newTestServer(t)
	token := pairToken(t, ts)

	if r := post(t, ts, "/v1/processes/abc/kill", token); r.StatusCode != 400 {
		t.Errorf("non-numeric pid: %d", r.StatusCode)
	}
	if r := post(t, ts, "/v1/processes/1/kill", token); r.StatusCode != 403 {
		t.Errorf("pid 1: %d want 403", r.StatusCode)
	}
	if r := post(t, ts, fmt.Sprintf("/v1/processes/%d/kill", os.Getpid()), token); r.StatusCode != 403 {
		t.Errorf("agent's own pid: %d want 403", r.StatusCode)
	}
	if r := post(t, ts, "/v1/processes/2147483000/kill", token); r.StatusCode != 403 {
		t.Errorf("missing pid: %d want 403", r.StatusCode)
	}

	cmd := exec.Command("sleep", "60")
	if err := cmd.Start(); err != nil {
		t.Skip("cannot start sleep")
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	r := post(t, ts, fmt.Sprintf("/v1/processes/%d/kill", cmd.Process.Pid), token)
	if r.StatusCode != 200 {
		t.Fatalf("kill child: %d", r.StatusCode)
	}
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("child survived the kill endpoint")
	}
}

func TestEventsStreamTelemetry(t *testing.T) {
	ts, _ := newTestServer(t)
	token := pairToken(t, ts)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", ts.URL+"/v1/events", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Fatalf("content-type %q", ct)
	}
	sc := bufio.NewScanner(resp.Body)
	events := 0
	for sc.Scan() && events < 2 {
		line := sc.Text()
		if data, ok := strings.CutPrefix(line, "data: "); ok {
			var tel sysinfo.Telemetry
			if err := json.Unmarshal([]byte(data), &tel); err != nil || tel.Hostname == "" {
				t.Fatalf("bad event payload %q: %v", data, err)
			}
			events++
		}
	}
	if events < 2 {
		t.Fatalf("expected 2 telemetry events (initial + one tick), got %d (%v)", events, sc.Err())
	}
}
