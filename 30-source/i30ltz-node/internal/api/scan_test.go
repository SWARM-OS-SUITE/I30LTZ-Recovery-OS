package api

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/scan"
	"i30ltz/node/internal/sysinfo"
)

// scriptedScanner stands in for clamscan: it answers --version, and for a scan reports every file in the
// folders it is given, flagging those whose name starts with "evil".
const scriptedScanner = `#!/bin/sh
for a; do [ "$a" = --version ] && { echo 'ClamAV 1.4.3/28146/Tue Oct  7 08:30:04 2026'; exit 0; }; done
rc=0
for p; do
  case "$p" in -*|ClamAV*) continue;; esac
  if [ -d "$p" ]; then files=$(find "$p" -type f); else files="$p"; fi
  for f in $files; do
    case "$(basename "$f")" in
      evil*) echo "$f: Test.Sig FOUND"; rc=1;;
      slow*) sleep 30;;
      *) echo "$f: OK";;
    esac
  done
done
exit $rc`

func newScanServer(t *testing.T, binary string, mod func(*scan.Config)) (*httptest.Server, string, *scan.Manager) {
	t.Helper()
	store, err := auth.Open(filepath.Join(t.TempDir(), "cfg"))
	if err != nil {
		t.Fatal(err)
	}
	cfg := scan.Config{Binary: binary, StateDir: filepath.Join(t.TempDir(), "state"), Home: t.TempDir()}
	if mod != nil {
		mod(&cfg)
	}
	mgr, err := scan.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	q, err := scan.OpenQuarantine(cfg.StateDir)
	if err != nil {
		t.Fatal(err)
	}
	col := sysinfo.NewCollector()
	srv := New(store, col, sysinfo.NewSampler(col, 100*time.Millisecond), "test")
	srv.Scan, srv.Quar = mgr, q
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	t.Cleanup(func() { mgr.Wait() })
	return ts, pairToken(t, ts), mgr
}

func script(t *testing.T, body string) string {
	p := filepath.Join(t.TempDir(), "clamscan")
	if err := os.WriteFile(p, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

func doJSON(t *testing.T, ts *httptest.Server, method, path, token, body string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(method, ts.URL+path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	raw, _ := io.ReadAll(resp.Body)
	_ = json.Unmarshal(raw, &out)
	return resp.StatusCode, out
}

func waitScan(t *testing.T, ts *httptest.Server, token, id string) map[string]any {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		_, r := doJSON(t, ts, "GET", "/v1/scan/"+id, token, "")
		if r["state"] != "running" {
			return r
		}
		time.Sleep(30 * time.Millisecond)
	}
	t.Fatal("scan did not finish")
	return nil
}

func TestScanEndpointsNeedATokenAndExplainWhenNotSetUp(t *testing.T) {
	ts, token := newTerminalServer(t, false, 0) // no scanner configured at all
	for _, p := range []string{"/v1/scan", "/v1/quarantine"} {
		if resp := get(t, ts, p, ""); resp.StatusCode != 401 {
			t.Errorf("%s without token: %d", p, resp.StatusCode)
		}
		if code, body := doJSON(t, ts, "GET", p, token, ""); code != 404 || !strings.Contains(fmt.Sprint(body["error"]), "not set up") {
			t.Errorf("%s: %d %v", p, code, body)
		}
	}
	var caps struct{ Features Features }
	json.NewDecoder(get(t, ts, "/v1/capabilities", token).Body).Decode(&caps)
	if caps.Features.Scan {
		t.Error("capabilities must say scan=false without a scanner")
	}
}

func TestMissingScannerBinaryIsNotImplementedAndScanFalse(t *testing.T) {
	ts, token, _ := newScanServer(t, filepath.Join(t.TempDir(), "no-clamscan"), nil)
	code, body := doJSON(t, ts, "POST", "/v1/scan", token, `{"scope":"home"}`)
	if code != 501 || !strings.Contains(fmt.Sprint(body["error"]), "ClamAV") {
		t.Errorf("%d %v", code, body)
	}
	var caps struct{ Features Features }
	json.NewDecoder(get(t, ts, "/v1/capabilities", token).Body).Decode(&caps)
	if caps.Features.Scan {
		t.Error("scan must be false when clamscan is missing")
	}
}

func TestScanFlowFindingsAndAuditLog(t *testing.T) {
	logs := &syncBuf{}
	log.SetOutput(logs)
	defer log.SetOutput(io.Discard)
	ts, token, _ := newScanServer(t, script(t, scriptedScanner), nil)

	var caps struct{ Features Features }
	json.NewDecoder(get(t, ts, "/v1/capabilities", token).Body).Decode(&caps)
	if !caps.Features.Scan {
		t.Error("capabilities should say scan=true")
	}
	code, st := doJSON(t, ts, "GET", "/v1/scan", token, "")
	engine, _ := st["engine"].(map[string]any)
	if code != 200 || engine["available"] != true || engine["version"] != "1.4.3" || engine["signature_version"] != "28146" {
		t.Errorf("status: %d %v", code, st)
	}

	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "fine.txt"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(dir, "evil-one.bin"), []byte("x"), 0o644)
	code, started := doJSON(t, ts, "POST", "/v1/scan", token, fmt.Sprintf(`{"scope":"path","path":%q}`, dir))
	if code != 202 {
		t.Fatalf("start: %d %v", code, started)
	}
	res := waitScan(t, ts, token, started["id"].(string))
	findings, _ := res["findings"].([]any)
	if res["state"] != "done" || len(findings) != 1 || res["scanned_files"].(float64) != 2 {
		t.Fatalf("%v", res)
	}
	if f := findings[0].(map[string]any); f["path"] != filepath.Join(dir, "evil-one.bin") || f["signature"] != "Test.Sig" {
		t.Errorf("%v", f)
	}
	time.Sleep(50 * time.Millisecond)
	if text := logs.String(); !strings.Contains(text, `"test phone" started a path scan`) || strings.Contains(text, token) {
		t.Errorf("audit log: %q", text)
	}
}

func TestScanInputValidationAndBusyAndCancel(t *testing.T) {
	ts, token, _ := newScanServer(t, script(t, scriptedScanner), nil)
	for _, body := range []string{`not json`, `{"scope":"everything"}`, `{"scope":"path"}`, `{"scope":"path","path":"relative"}`, `{"scope":"path","path":"/no/such/dir"}`} {
		if code, out := doJSON(t, ts, "POST", "/v1/scan", token, body); code != 400 {
			t.Errorf("%s: %d %v", body, code, out)
		}
	}
	if code, _ := doJSON(t, ts, "GET", "/v1/scan/20261007-000000-ffffff", token, ""); code != 404 {
		t.Errorf("unknown scan: %d", code)
	}

	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "slow-file"), []byte("x"), 0o644)
	_, started := doJSON(t, ts, "POST", "/v1/scan", token, fmt.Sprintf(`{"scope":"path","path":%q}`, dir))
	id := started["id"].(string)
	if code, _ := doJSON(t, ts, "POST", "/v1/scan", token, fmt.Sprintf(`{"scope":"path","path":%q}`, dir)); code != 409 {
		t.Errorf("second scan while one runs: %d want 409", code)
	}
	if code, _ := doJSON(t, ts, "POST", "/v1/scan/other-id/cancel", token, ""); code != 409 {
		t.Errorf("cancel of a scan that is not running: %d", code)
	}
	if code, _ := doJSON(t, ts, "POST", "/v1/scan/"+id+"/cancel", token, ""); code != 200 {
		t.Fatalf("cancel: %d", code)
	}
	if _, res := doJSON(t, ts, "GET", "/v1/scan/"+id, token, ""); res["state"] != "cancelled" {
		t.Errorf("state %v", res["state"])
	}
}

func TestQuarantineOnlyOnRequestOnlyForFindingsAndIsReversible(t *testing.T) {
	logs := &syncBuf{}
	log.SetOutput(logs)
	defer log.SetOutput(io.Discard)
	ts, token, _ := newScanServer(t, script(t, scriptedScanner), nil)
	dir := t.TempDir()
	evil, other := filepath.Join(dir, "evil.bin"), filepath.Join(dir, "other.bin")
	os.WriteFile(evil, []byte("payload"), 0o750)
	os.WriteFile(other, []byte("not a finding"), 0o644)
	_, started := doJSON(t, ts, "POST", "/v1/scan", token, fmt.Sprintf(`{"scope":"path","path":%q}`, dir))
	id := started["id"].(string)
	waitScan(t, ts, token, id)

	// finishing a scan changes nothing on disk
	if _, err := os.Stat(evil); err != nil {
		t.Fatal("scanning alone must never move or delete a file")
	}
	q := func(path string) (int, map[string]any) {
		return doJSON(t, ts, "POST", "/v1/scan/"+id+"/quarantine", token, fmt.Sprintf(`{"path":%q}`, path))
	}
	if code, _ := q(other); code != 403 {
		t.Errorf("a file that is not a finding: %d want 403", code)
	}
	if code, _ := q("/etc/passwd"); code != 403 {
		t.Errorf("an arbitrary file: %d want 403", code)
	}
	if code, _ := doJSON(t, ts, "POST", "/v1/scan/"+id+"/quarantine", token, `{}`); code != 400 {
		t.Errorf("no path: %d", code)
	}
	code, item := q(evil)
	if code != 200 || item["signature"] != "Test.Sig" || item["original_path"] != evil {
		t.Fatalf("%d %v", code, item)
	}
	if _, err := os.Stat(evil); !os.IsNotExist(err) {
		t.Error("the finding should have been moved")
	}
	if _, err := os.Stat(other); err != nil {
		t.Error("other files must be untouched")
	}
	resp := get(t, ts, "/v1/quarantine", token)
	var items []map[string]any
	json.NewDecoder(resp.Body).Decode(&items)
	if resp.StatusCode != 200 || len(items) != 1 || items[0]["id"] != item["id"] {
		t.Fatalf("list: %d %v", resp.StatusCode, items)
	}
	qid := item["id"].(string)
	if code, _ := doJSON(t, ts, "POST", "/v1/quarantine/"+qid+"/restore", token, ""); code != 200 {
		t.Fatalf("restore: %d", code)
	}
	if st, err := os.Stat(evil); err != nil || st.Mode().Perm() != 0o750 {
		t.Errorf("restored file: %v %v", st, err)
	}
	if code, _ := doJSON(t, ts, "POST", "/v1/quarantine/"+qid+"/restore", token, ""); code != 404 {
		t.Errorf("restoring twice: %d want 404", code)
	}
	if code, _ := doJSON(t, ts, "DELETE", "/v1/quarantine/..%2f..%2fetc", token, ""); code != 404 {
		t.Errorf("odd id: %d want 404", code)
	}
	time.Sleep(50 * time.Millisecond)
	if text := logs.String(); !strings.Contains(text, `"test phone" quarantined`) || !strings.Contains(text, "restored") || strings.Contains(text, token) {
		t.Errorf("audit log: %q", text)
	}
}

// The same flow against the real engine, when one is available.
func TestRealEngineThroughTheAPI(t *testing.T) {
	bin := os.Getenv("I30LTZ_CLAMSCAN")
	if bin == "" {
		if p, err := exec.LookPath("clamscan"); err == nil {
			bin = p
		} else {
			t.Skip("no clamscan available")
		}
	}
	content := []byte("I30LTZ-NOT-REAL-MALWARE-api-marker-77c1")
	sum := md5.Sum(content)
	db := t.TempDir()
	os.WriteFile(filepath.Join(db, "m.hdb"), []byte(fmt.Sprintf("%s:%d:Api.Test.Marker\n", hex.EncodeToString(sum[:]), len(content))), 0o644)
	ts, token, _ := newScanServer(t, bin, func(c *scan.Config) { c.DBDir = db })

	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "ok.txt"), []byte("fine"), 0o644)
	os.WriteFile(filepath.Join(dir, "bad.bin"), content, 0o644)
	_, started := doJSON(t, ts, "POST", "/v1/scan", token, fmt.Sprintf(`{"scope":"path","path":%q}`, dir))
	id := started["id"].(string)
	res := waitScan(t, ts, token, id)
	findings, _ := res["findings"].([]any)
	if res["state"] != "done" || len(findings) != 1 || !strings.HasPrefix(findings[0].(map[string]any)["signature"].(string), "Api.Test.Marker") {
		t.Fatalf("%v", res)
	}
	if code, _ := doJSON(t, ts, "POST", "/v1/scan/"+id+"/quarantine", token, fmt.Sprintf(`{"path":%q}`, filepath.Join(dir, "bad.bin"))); code != 200 {
		t.Fatalf("quarantine: %d", code)
	}
	if _, err := os.Stat(filepath.Join(dir, "bad.bin")); !os.IsNotExist(err) {
		t.Error("the real finding should be quarantined")
	}
}
