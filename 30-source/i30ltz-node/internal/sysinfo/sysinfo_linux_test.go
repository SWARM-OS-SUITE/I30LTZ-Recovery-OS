package sysinfo

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const statA = "cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 100 0 100 800 0 0 0 0 0 0\n"
const statB = "cpu  200 0 200 1000 0 0 0 0 0 0\n" // +200 busy, +200 idle => 50%

func TestParseCPUStat(t *testing.T) {
	idle, total, err := parseCPUStat(statA)
	if err != nil || idle != 800 || total != 1000 {
		t.Fatalf("idle=%d total=%d err=%v", idle, total, err)
	}
	if _, _, err := parseCPUStat("intr 1 2 3\n"); err == nil {
		t.Fatal("expected error without a cpu line")
	}
}

func TestParseMeminfo(t *testing.T) {
	total, avail, err := parseMeminfo("MemTotal:       16000000 kB\nMemFree: 1 kB\nMemAvailable:    4000000 kB\n")
	if err != nil || total != 16000000 || avail != 4000000 {
		t.Fatalf("%d %d %v", total, avail, err)
	}
	if _, _, err := parseMeminfo("MemTotal: 5 kB\n"); err == nil {
		t.Fatal("expected error when MemAvailable is missing")
	}
}

func TestParseOSName(t *testing.T) {
	if got := parseOSName("NAME=\"Debian\"\nPRETTY_NAME=\"Debian GNU/Linux 13 (trixie)\"\n"); got != "Debian GNU/Linux 13 (trixie)" {
		t.Fatal(got)
	}
	if got := parseOSName(""); got != "Linux" {
		t.Fatal(got)
	}
}

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func fixtureCollector(t *testing.T) (*Collector, string) {
	root := t.TempDir()
	c := &Collector{ProcRoot: filepath.Join(root, "proc"), SysRoot: filepath.Join(root, "sys"),
		OSReleasePath: filepath.Join(root, "os-release"), StatfsPath: root}
	write(t, filepath.Join(c.ProcRoot, "stat"), statA)
	write(t, filepath.Join(c.ProcRoot, "meminfo"), "MemTotal: 8192000 kB\nMemAvailable: 2048000 kB\n")
	write(t, filepath.Join(c.ProcRoot, "loadavg"), "1.50 1.00 0.50 1/100 999\n")
	write(t, filepath.Join(c.ProcRoot, "uptime"), "3600.55 7000.00\n")
	write(t, c.OSReleasePath, "PRETTY_NAME=\"Test OS\"\n")
	write(t, filepath.Join(c.SysRoot, "class/thermal/thermal_zone0/temp"), "45000\n")
	write(t, filepath.Join(c.SysRoot, "class/thermal/thermal_zone1/temp"), "61500\n")
	write(t, filepath.Join(c.SysRoot, "class/thermal/thermal_zone2/temp"), "-274000\n") // sentinel, ignored
	return c, root
}

func TestSampleFromFixture(t *testing.T) {
	c, _ := fixtureCollector(t)
	first := c.Sample()
	if first.CPUPercent != -1 {
		t.Fatalf("first CPU sample must be -1 (nothing to compare), got %v", first.CPUPercent)
	}
	write(t, filepath.Join(c.ProcRoot, "stat"), statB)
	got := c.Sample()
	if got.CPUPercent != 50 {
		t.Errorf("cpu = %v, want 50", got.CPUPercent)
	}
	if got.RAMTotalMB != 8000 || got.RAMUsedMB != 6000 || got.RAMPercent != 75 {
		t.Errorf("ram = %d/%d MB %.1f%%", got.RAMUsedMB, got.RAMTotalMB, got.RAMPercent)
	}
	if got.Load1 != 1.5 || got.UptimeSeconds != 3600 || got.OS != "Test OS" {
		t.Errorf("load/uptime/os = %v %v %q", got.Load1, got.UptimeSeconds, got.OS)
	}
	if got.TempC == nil || *got.TempC != 61.5 {
		t.Errorf("temp = %v, want 61.5", got.TempC)
	}
	if got.StorageTotalGB <= 0 {
		t.Errorf("storage total = %v", got.StorageTotalGB)
	}
}

func TestMissingFilesGiveMinusOneNotInvention(t *testing.T) {
	c := &Collector{ProcRoot: t.TempDir(), SysRoot: t.TempDir(), OSReleasePath: "/nonexistent", StatfsPath: "/nonexistent"}
	got := c.Sample()
	if got.CPUPercent != -1 || got.RAMPercent != -1 || got.Load1 != -1 || got.UptimeSeconds != -1 ||
		got.StorageTotalGB != -1 || got.TempC != nil {
		t.Fatalf("unmeasurable values must be -1/nil: %+v", got)
	}
}

const userProc = "Name:\tfirefox\nState:\tS (sleeping)\nPid:\t4242\nPPid:\t1000\nUid:\t1000\t1000\t1000\t1000\nVmRSS:\t  2048000 kB\n"
const kernelThread = "Name:\tkworker/0:1\nState:\tI (idle)\nPid:\t77\nPPid:\t2\nUid:\t0\t0\t0\t0\n"

func fixtureProcs(t *testing.T) *Collector {
	c, _ := fixtureCollector(t)
	write(t, filepath.Join(c.ProcRoot, "4242/status"), userProc)
	write(t, filepath.Join(c.ProcRoot, "77/status"), kernelThread)
	write(t, filepath.Join(c.ProcRoot, "5000/status"), "Name:\tsmall\nState:\tR (running)\nPid:\t5000\nPPid:\t1\nUid:\t0\t0\t0\t0\nVmRSS:\t 1024 kB\n")
	write(t, filepath.Join(c.ProcRoot, "self/status"), "ignored")
	return c
}

func TestProcessesSkipKernelThreadsAndSortByMemory(t *testing.T) {
	c := fixtureProcs(t)
	list, err := c.Processes(0)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 2 || list[0].PID != 4242 || list[1].PID != 5000 {
		t.Fatalf("got %+v", list)
	}
	if list[0].MemoryMB != 2000 || list[0].Name != "firefox" {
		t.Errorf("first = %+v", list[0])
	}
	if one, _ := c.Processes(1); len(one) != 1 {
		t.Errorf("limit 1 returned %d", len(one))
	}
}

func TestCanKillGuards(t *testing.T) {
	c := fixtureProcs(t)
	for pid, why := range map[int]string{0: "pid 0", 1: "init", os.Getpid(): "agent itself", 77: "kernel thread", 99999: "missing"} {
		if err := c.CanKill(pid); err == nil {
			t.Errorf("CanKill(%d) should refuse (%s)", pid, why)
		}
	}
	if err := c.CanKill(4242); err != nil {
		t.Errorf("a normal user process should be allowed: %v", err)
	}
}

func TestKillRealChildProcess(t *testing.T) {
	cmd := exec.Command("sleep", "60")
	if err := cmd.Start(); err != nil {
		t.Skipf("cannot start sleep: %v", err)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	c := NewCollector()
	if err := c.Kill(cmd.Process.Pid, false); err != nil {
		t.Fatalf("kill: %v", err)
	}
	select {
	case err := <-done:
		if err == nil || !strings.Contains(err.Error(), "terminated") {
			t.Fatalf("expected the child to die from SIGTERM, got %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("child still running after SIGTERM")
	}
}

func TestRealProcListContainsTestProcess(t *testing.T) {
	list, err := NewCollector().Processes(0)
	if err != nil || len(list) == 0 {
		t.Fatalf("real /proc: %d entries, err %v", len(list), err)
	}
	found := false
	for _, p := range list {
		if p.PID == os.Getpid() {
			found = true
		}
	}
	if !found {
		t.Error("the running test binary should appear in the process list")
	}
}
