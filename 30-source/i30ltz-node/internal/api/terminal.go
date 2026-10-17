package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/term"
	"i30ltz/node/internal/ws"
)

const (
	pingEvery = 25 * time.Second
	minCols   = 10
	maxCols   = 500
	minRows   = 5
	maxRows   = 200
)

// terminalOK answers the request itself and returns false if shell access is not available.
func (s *Server) terminalOK(w http.ResponseWriter) bool {
	switch {
	case !s.terminalEnabled:
		writeErr(w, http.StatusNotFound, "the terminal is not enabled on this node; start the agent with --terminal")
	case !term.Available():
		writeErr(w, http.StatusNotFound, "tmux is not installed on this node")
	default:
		return true
	}
	return false
}

func (s *Server) terminalSessions(w http.ResponseWriter, _ *http.Request) {
	if !s.terminalOK(w) {
		return
	}
	list, err := term.Sessions()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "cannot list tmux sessions")
		return
	}
	writeJSON(w, http.StatusOK, list)
}

func sizeParam(r *http.Request, name string, def, lo, hi int) (int, bool) {
	v := r.URL.Query().Get(name)
	if v == "" {
		return def, true
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return 0, false
	}
	return min(max(n, lo), hi), true
}

// terminal attaches a WebSocket to a tmux session. Binary messages carry raw terminal bytes in both
// directions; a text message {"type":"resize","cols":N,"rows":M} resizes. Because the other side of
// the session is an ordinary tmux client, whatever is typed here shows up on the node's own screen
// and vice versa.
func (s *Server) terminal(w http.ResponseWriter, r *http.Request) {
	if !s.terminalOK(w) {
		return
	}
	name := r.URL.Query().Get("session")
	if name == "" {
		name = term.DefaultSession
	}
	cols, okc := sizeParam(r, "cols", 80, minCols, maxCols)
	rows, okr := sizeParam(r, "rows", 24, minRows, maxRows)
	if !term.ValidSession(name) || !okc || !okr {
		writeErr(w, http.StatusBadRequest, "session must be 1-32 letters, digits, '_' or '-'; cols and rows must be numbers")
		return
	}
	if s.activeTerminals.Add(1) > s.maxTerminals {
		s.activeTerminals.Add(-1)
		writeErr(w, http.StatusTooManyRequests, "too many open terminals on this node")
		return
	}
	defer s.activeTerminals.Add(-1)

	label := s.Auth.Label(auth.BearerToken(r))
	conn, err := ws.Upgrade(w, r)
	if err != nil {
		return
	}
	defer conn.Close(ws.CloseNormal, "")

	p, err := term.Start(term.AttachCommand(name, s.windowSize), uint16(cols), uint16(rows))
	if err != nil {
		log.Printf("terminal: could not start tmux for %q: %v", label, err)
		conn.Close(ws.CloseInternal, "could not start tmux")
		return
	}
	started := time.Now()
	// Who and which session only; never what was typed or shown.
	log.Printf("terminal: %q attached to tmux session %q from %s", label, name, conn.RemoteAddr())
	defer func() {
		log.Printf("terminal: %q left session %q after %s", label, name, time.Since(started).Round(time.Second))
	}()
	defer p.Close()

	done := make(chan struct{})
	go func() { // terminal output -> phone
		defer close(done)
		buf := make([]byte, 32<<10)
		for {
			n, err := p.Read(buf)
			if n > 0 && conn.WriteMessage(ws.OpBinary, buf[:n]) != nil {
				return
			}
			if err != nil {
				conn.Close(ws.CloseNormal, "session ended")
				return
			}
		}
	}()
	go func() { // keep NAT / Tailscale paths open while the terminal is quiet
		t := time.NewTicker(pingEvery)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
				if conn.Ping() != nil {
					return
				}
			}
		}
	}()

	for { // phone -> terminal
		op, data, err := conn.ReadMessage()
		if err != nil {
			break
		}
		switch op {
		case ws.OpBinary:
			if _, err := p.Write(data); err != nil {
				return
			}
		case ws.OpText:
			var msg struct {
				Type string `json:"type"`
				Cols int    `json:"cols"`
				Rows int    `json:"rows"`
			}
			if json.Unmarshal(data, &msg) == nil && msg.Type == "resize" {
				_ = p.Resize(uint16(min(max(msg.Cols, minCols), maxCols)), uint16(min(max(msg.Rows, minRows), maxRows)))
			}
		}
	}
	p.Close()
	<-done
}
