// Package sysinfo reads node telemetry and the process list from /proc and /sys.
// Linux only: every supported node OS (Arch, CachyOS, Debian, Recovery OS) is Linux.
package sysinfo

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Telemetry is one snapshot. Fields that could not be measured are -1 (or nil),
// never a plausible-looking default.
type Telemetry struct {
	Hostname       string    `json:"hostname"`
	OS             string    `json:"os"`
	CPUPercent     float64   `json:"cpu_percent"`
	RAMPercent     float64   `json:"ram_percent"`
	RAMTotalMB     int64     `json:"ram_total_mb"`
	RAMUsedMB      int64     `json:"ram_used_mb"`
	StorageTotalGB float64   `json:"storage_total_gb"`
	StorageFreeGB  float64   `json:"storage_free_gb"`
	Load1          float64   `json:"load1"`
	UptimeSeconds  int64     `json:"uptime_seconds"`
	TempC          *float64  `json:"temp_c,omitempty"`
	Time           time.Time `json:"time"`
}

// Collector reads from configurable roots so tests can point it at fixtures.
type Collector struct {
	ProcRoot      string // default /proc
	SysRoot       string // default /sys
	OSReleasePath string // default /etc/os-release
	StatfsPath    string // default /

	mu                  sync.Mutex
	prevIdle, prevTotal uint64
	havePrev            bool
}

func NewCollector() *Collector {
	return &Collector{ProcRoot: "/proc", SysRoot: "/sys", OSReleasePath: "/etc/os-release", StatfsPath: "/"}
}

func readFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	return string(b), err
}

// parseCPUStat returns idle and total jiffies from the aggregate "cpu " line.
func parseCPUStat(stat string) (idle, total uint64, err error) {
	for _, line := range strings.Split(stat, "\n") {
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)[1:]
		if len(fields) < 4 {
			return 0, 0, errors.New("short cpu line")
		}
		for i, f := range fields {
			if i >= 8 { // guest times are already counted in user/nice
				break
			}
			v, err := strconv.ParseUint(f, 10, 64)
			if err != nil {
				return 0, 0, err
			}
			total += v
			if i == 3 || i == 4 { // idle + iowait
				idle += v
			}
		}
		return idle, total, nil
	}
	return 0, 0, errors.New("no aggregate cpu line in stat")
}

// parseMeminfo returns MemTotal and MemAvailable in kB.
func parseMeminfo(mem string) (totalKB, availKB int64, err error) {
	totalKB, availKB = -1, -1
	for _, line := range strings.Split(mem, "\n") {
		name, rest, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		if name != "MemTotal" && name != "MemAvailable" {
			continue
		}
		v, perr := strconv.ParseInt(strings.Fields(rest)[0], 10, 64)
		if perr != nil {
			return 0, 0, perr
		}
		if name == "MemTotal" {
			totalKB = v
		} else {
			availKB = v
		}
	}
	if totalKB < 0 || availKB < 0 {
		return 0, 0, errors.New("MemTotal/MemAvailable missing")
	}
	return totalKB, availKB, nil
}

func parseOSName(release string) string {
	for _, line := range strings.Split(release, "\n") {
		if v, ok := strings.CutPrefix(line, "PRETTY_NAME="); ok {
			return strings.Trim(v, `"'`)
		}
	}
	return "Linux"
}

func (c *Collector) cpuPercent() float64 {
	raw, err := readFile(filepath.Join(c.ProcRoot, "stat"))
	if err != nil {
		return -1
	}
	idle, total, err := parseCPUStat(raw)
	if err != nil {
		return -1
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	pi, pt, have := c.prevIdle, c.prevTotal, c.havePrev
	c.prevIdle, c.prevTotal, c.havePrev = idle, total, true
	if !have || total <= pt || idle < pi {
		return -1 // first sample has nothing to compare with
	}
	busy := float64((total-pt)-(idle-pi)) / float64(total-pt) * 100
	return round1(busy)
}

func round1(v float64) float64 { return float64(int64(v*10+0.5)) / 10 }

func (c *Collector) maxTempC() *float64 {
	matches, _ := filepath.Glob(filepath.Join(c.SysRoot, "class/thermal/thermal_zone*/temp"))
	var best float64
	found := false
	for _, m := range matches {
		raw, err := readFile(m)
		if err != nil {
			continue
		}
		milli, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
		if err != nil || milli <= 0 || milli > 150000 { // ignore sentinel values
			continue
		}
		if !found || milli/1000 > best {
			best, found = milli/1000, true
		}
	}
	if !found {
		return nil
	}
	best = round1(best)
	return &best
}

// Sample takes one snapshot. CPU is -1 until a second sample exists.
func (c *Collector) Sample() Telemetry {
	t := Telemetry{CPUPercent: c.cpuPercent(), RAMPercent: -1, RAMTotalMB: -1, RAMUsedMB: -1,
		StorageTotalGB: -1, StorageFreeGB: -1, Load1: -1, UptimeSeconds: -1, Time: time.Now().UTC()}
	t.Hostname, _ = os.Hostname()
	if raw, err := readFile(c.OSReleasePath); err == nil {
		t.OS = parseOSName(raw)
	} else {
		t.OS = "Linux"
	}
	if raw, err := readFile(filepath.Join(c.ProcRoot, "meminfo")); err == nil {
		if total, avail, err := parseMeminfo(raw); err == nil && total > 0 {
			t.RAMTotalMB = total / 1024
			t.RAMUsedMB = (total - avail) / 1024
			t.RAMPercent = round1(float64(total-avail) / float64(total) * 100)
		}
	}
	var fs syscall.Statfs_t
	if err := syscall.Statfs(c.StatfsPath, &fs); err == nil {
		bs := float64(fs.Bsize)
		t.StorageTotalGB = round1(float64(fs.Blocks) * bs / (1 << 30))
		t.StorageFreeGB = round1(float64(fs.Bavail) * bs / (1 << 30))
	}
	if raw, err := readFile(filepath.Join(c.ProcRoot, "loadavg")); err == nil {
		if f := strings.Fields(raw); len(f) > 0 {
			if v, err := strconv.ParseFloat(f[0], 64); err == nil {
				t.Load1 = v
			}
		}
	}
	if raw, err := readFile(filepath.Join(c.ProcRoot, "uptime")); err == nil {
		if f := strings.Fields(raw); len(f) > 0 {
			if v, err := strconv.ParseFloat(f[0], 64); err == nil {
				t.UptimeSeconds = int64(v)
			}
		}
	}
	t.TempC = c.maxTempC()
	return t
}

// Sampler samples on a fixed interval so CPU% is stable no matter how many
// clients ask, and handlers never trigger their own measurements.
type Sampler struct {
	col      *Collector
	interval time.Duration
	mu       sync.RWMutex
	latest   Telemetry
	have     bool
}

func NewSampler(col *Collector, interval time.Duration) *Sampler {
	return &Sampler{col: col, interval: interval}
}

// Run samples until ctx ends. It takes one sample immediately so CPU is
// available after a single interval.
func (s *Sampler) Run(ctx context.Context) {
	s.store(s.col.Sample())
	t := time.NewTicker(s.interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.store(s.col.Sample())
		}
	}
}

func (s *Sampler) store(t Telemetry) {
	s.mu.Lock()
	s.latest, s.have = t, true
	s.mu.Unlock()
}

// Latest returns the newest snapshot, sampling once if Run has not started yet.
func (s *Sampler) Latest() Telemetry {
	s.mu.RLock()
	t, ok := s.latest, s.have
	s.mu.RUnlock()
	if ok {
		return t
	}
	t = s.col.Sample()
	s.store(t)
	return t
}

// Interval is how often a new snapshot appears.
func (s *Sampler) Interval() time.Duration { return s.interval }

func (t Telemetry) String() string {
	return fmt.Sprintf("%s cpu=%.1f%% ram=%.1f%%", t.Hostname, t.CPUPercent, t.RAMPercent)
}
