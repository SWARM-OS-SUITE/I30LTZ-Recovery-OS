package term

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// DefaultSession is the shared session name used when none is given.
const DefaultSession = "main"

var sessionName = regexp.MustCompile(`^[A-Za-z0-9_-]{1,32}$`)

// ValidSession reports whether name is safe to pass to tmux (letters, digits, '_' and '-').
func ValidSession(name string) bool { return sessionName.MatchString(name) }

// Available reports whether tmux is installed.
func Available() bool {
	_, err := exec.LookPath("tmux")
	return err == nil
}

// Session is one tmux session on this node.
type Session struct {
	Name     string `json:"name"`
	Windows  int    `json:"windows"`
	Attached int    `json:"attached"` // clients currently attached, e.g. the PC's terminal
	Created  int64  `json:"created"`  // unix seconds
}

// Sessions lists tmux sessions; an empty list when no tmux server is running.
func Sessions() ([]Session, error) {
	// -u and a UTF-8 locale on purpose: with no locale (a systemd user service, a minimal environment) tmux 3.5 prints "_"
	// instead of the TAB between the -F fields, no line parses, and the phone's session list comes back silently empty.
	cmd := exec.Command("tmux", "-u", "list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}")
	cmd.Env = TerminalEnv(os.Environ())
	out, err := cmd.CombinedOutput()
	if err != nil {
		var ee *exec.ExitError
		text := string(out)
		if errors.As(err, &ee) && (strings.Contains(text, "no server running") || strings.Contains(text, "error connecting") || strings.Contains(text, "No such file")) {
			return []Session{}, nil
		}
		return nil, fmt.Errorf("tmux list-sessions: %v: %s", err, strings.TrimSpace(text))
	}
	return parseSessions(out), nil
}

func parseSessions(out []byte) []Session {
	list := []Session{}
	for _, line := range bytes.Split(bytes.TrimSpace(out), []byte("\n")) {
		f := strings.Split(string(line), "\t")
		if len(f) != 4 || !ValidSession(f[0]) {
			continue // skip sessions with names we would not accept back
		}
		w, _ := strconv.Atoi(f[1])
		a, _ := strconv.Atoi(f[2])
		c, _ := strconv.ParseInt(f[3], 10, 64)
		list = append(list, Session{Name: f[0], Windows: w, Attached: a, Created: c})
	}
	return list
}

// WindowSizes are the tmux window-size modes the agent accepts.
//
//	smallest: the window is as small as the smallest attached client, so every client sees exactly the
//	          same thing (a true mirror). The PC's window narrows while the phone is attached.
//	latest:   the window follows whoever typed last. The other client then sees only a slice of it
//	          (tmux pans around the cursor), which makes a narrow phone screen hard to read.
//	largest:  the window is as big as the biggest client; smaller clients see a slice.
var WindowSizes = []string{"smallest", "latest", "largest"}

// DefaultWindowSize is "smallest": mirroring means both sides see the same thing.
const DefaultWindowSize = "smallest"

// ValidWindowSize reports whether mode is one of WindowSizes.
func ValidWindowSize(mode string) bool {
	for _, m := range WindowSizes {
		if m == mode {
			return true
		}
	}
	return false
}

// AttachCommand returns the tmux client command that attaches to the named session, creating it if needed,
// and sets the session's window-size mode (see WindowSizes).
func AttachCommand(name, windowSize string) *exec.Cmd {
	if !ValidWindowSize(windowSize) {
		windowSize = DefaultWindowSize
	}
	cmd := exec.Command("tmux", "-u", "new-session", "-A", "-s", name, ";", "set-option", "-t", name, "window-size", windowSize)
	cmd.Env = TerminalEnv(os.Environ())
	return cmd
}

// TerminalEnv returns env prepared for a terminal client: xterm-256color, a UTF-8 locale, and no
// TMUX variables (the agent may itself have been started inside tmux).
func TerminalEnv(env []string) []string {
	out := make([]string, 0, len(env)+2)
	hasLang := false
	for _, kv := range env {
		switch {
		case strings.HasPrefix(kv, "TERM="), strings.HasPrefix(kv, "TMUX="), strings.HasPrefix(kv, "TMUX_PANE="):
			continue
		case strings.HasPrefix(kv, "LANG="), strings.HasPrefix(kv, "LC_ALL="):
			hasLang = true
		}
		out = append(out, kv)
	}
	out = append(out, "TERM=xterm-256color")
	if !hasLang {
		out = append(out, "LANG=C.UTF-8")
	}
	return out
}
