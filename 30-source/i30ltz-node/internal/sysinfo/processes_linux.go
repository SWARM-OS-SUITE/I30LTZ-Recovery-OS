package sysinfo

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

// Process is one user-space process. Kernel threads are left out: they have no
// memory of their own and cannot be killed.
type Process struct {
	PID      int     `json:"pid"`
	Name     string  `json:"name"`
	User     string  `json:"user"`
	MemoryMB float64 `json:"memory_mb"`
	State    string  `json:"state"`
}

type procStatus struct {
	Process
	PPID  int
	HasMM bool // has a VmRSS line, i.e. is a user-space process
}

// parseStatus reads the text of /proc/<pid>/status.
func parseStatus(text string, lookupUser func(uid string) string) (procStatus, bool) {
	var p procStatus
	gotPID := false
	for _, line := range strings.Split(text, "\n") {
		key, val, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		val = strings.TrimSpace(val)
		switch key {
		case "Name":
			p.Name = val
		case "State":
			p.State = val
		case "Pid":
			if n, err := strconv.Atoi(val); err == nil {
				p.PID, gotPID = n, true
			}
		case "PPid":
			p.PPID, _ = strconv.Atoi(val)
		case "Uid":
			if f := strings.Fields(val); len(f) > 0 {
				p.User = lookupUser(f[0])
			}
		case "VmRSS":
			if f := strings.Fields(val); len(f) > 0 {
				if kb, err := strconv.ParseFloat(f[0], 64); err == nil {
					p.MemoryMB = float64(int64(kb/1024*10+0.5)) / 10
					p.HasMM = true
				}
			}
		}
	}
	return p, gotPID && p.Name != ""
}

var (
	userMu    sync.Mutex
	userCache = map[string]string{}
)

func lookupUser(uid string) string {
	userMu.Lock()
	defer userMu.Unlock()
	if name, ok := userCache[uid]; ok {
		return name
	}
	name := uid
	if u, err := user.LookupId(uid); err == nil {
		name = u.Username
	}
	userCache[uid] = name
	return name
}

// Processes lists user-space processes, largest memory first. limit <= 0 means all.
func (c *Collector) Processes(limit int) ([]Process, error) {
	entries, err := os.ReadDir(c.ProcRoot)
	if err != nil {
		return nil, err
	}
	var out []Process
	for _, e := range entries {
		if _, err := strconv.Atoi(e.Name()); err != nil {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(c.ProcRoot, e.Name(), "status"))
		if err != nil {
			continue // process exited while we were listing
		}
		p, ok := parseStatus(string(raw), lookupUser)
		if !ok || !p.HasMM {
			continue
		}
		out = append(out, p.Process)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].MemoryMB != out[j].MemoryMB {
			return out[i].MemoryMB > out[j].MemoryMB
		}
		return out[i].PID < out[j].PID
	})
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

// CanKill refuses targets that would break the node or the agent itself.
func (c *Collector) CanKill(pid int) error {
	switch {
	case pid <= 1:
		return fmt.Errorf("refusing to signal pid %d (init)", pid)
	case pid == os.Getpid():
		return fmt.Errorf("refusing to signal the agent itself")
	}
	raw, err := os.ReadFile(filepath.Join(c.ProcRoot, strconv.Itoa(pid), "status"))
	if err != nil {
		return fmt.Errorf("no such process: %d", pid)
	}
	p, ok := parseStatus(string(raw), func(s string) string { return s })
	if !ok {
		return fmt.Errorf("cannot read process %d", pid)
	}
	if !p.HasMM || p.PPID == 2 {
		return fmt.Errorf("pid %d is a kernel thread", pid)
	}
	return nil
}

// Kill sends SIGTERM (force=false) or SIGKILL (force=true) after CanKill passes.
func (c *Collector) Kill(pid int, force bool) error {
	if err := c.CanKill(pid); err != nil {
		return err
	}
	sig := syscall.SIGTERM
	if force {
		sig = syscall.SIGKILL
	}
	if err := syscall.Kill(pid, sig); err != nil {
		return fmt.Errorf("signal %d to pid %d failed: %w", sig, pid, err)
	}
	return nil
}
