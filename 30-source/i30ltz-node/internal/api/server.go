// Package api is the node agent's HTTP surface (API version 1).
//
//	POST /v1/pair                  trade a one-time code for a token (no auth)
//	GET  /v1/pairing/new           make a pairing code (loopback only)
//	GET  /v1/capabilities          what this node can really do
//	GET  /v1/telemetry             latest snapshot
//	GET  /v1/events                telemetry as Server-Sent Events
//	GET  /v1/processes             user-space processes, largest memory first
//	POST /v1/processes/{pid}/kill  ?force=1 for SIGKILL
//	GET  /v1/terminal/sessions     tmux sessions on this node (only with --terminal)
//	GET  /v1/terminal              WebSocket attached to a tmux session (only with --terminal)
//	GET  /v1/scan                  scanner status and recent scans
//	POST /v1/scan                  start a scan {"scope":"quick|home|full|path","path":"/abs"}
//	GET  /v1/scan/{id}             progress and findings; POST /v1/scan/{id}/cancel
//	POST /v1/scan/{id}/quarantine  move one finding into quarantine (explicit, reversible)
//	GET  /v1/quarantine            quarantined files; POST .../{id}/restore; DELETE .../{id}
//
// Everything except pairing requires "Authorization: Bearer <token>".
package api

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/scan"
	"i30ltz/node/internal/sysinfo"
	"i30ltz/node/internal/term"
)

const APIVersion = 1

// Features is reported honestly: false means "not built on this node yet",
// so the app can say so instead of pretending.
type Features struct {
	Telemetry bool `json:"telemetry"`
	Events    bool `json:"events"`
	Processes bool `json:"processes"`
	Kill      bool `json:"kill"`
	Scan      bool `json:"scan"`
	Optimize  bool `json:"optimize"`
	Terminal  bool `json:"terminal"`
	Jobs      bool `json:"jobs"`
}

type Server struct {
	Auth     *auth.Store
	Col      *sysinfo.Collector
	Sampler  *sysinfo.Sampler
	Version  string
	Features Features

	Scan *scan.Manager
	Quar *scan.Quarantine

	rejectMu    sync.Mutex
	rejectedLog map[string]time.Time // remote+path -> last time we logged a rejection (rate limit)

	terminalEnabled bool
	windowSize      string
	maxTerminals    int32
	activeTerminals atomic.Int32
}

// EnableTerminal turns on the shell endpoints. It is off unless the operator asks for it,
// because a paired phone then gets a shell as the user the agent runs as.
func (s *Server) EnableTerminal(maxSessions int, windowSize string) {
	s.terminalEnabled = true
	s.maxTerminals = int32(maxSessions)
	s.windowSize = windowSize
}

func (s *Server) terminalReady() bool { return s.terminalEnabled && term.Available() }

func New(store *auth.Store, col *sysinfo.Collector, sampler *sysinfo.Sampler, version string) *Server {
	return &Server{Auth: store, Col: col, Sampler: sampler, Version: version,
		Features: Features{Telemetry: true, Events: true, Processes: true, Kill: true}}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	protected := s.protect

	mux.HandleFunc("POST /v1/pair", s.pair)
	mux.HandleFunc("GET /v1/pairing/new", s.newPairingCode)
	mux.Handle("GET /v1/capabilities", protected(http.HandlerFunc(s.capabilities)))
	mux.Handle("GET /v1/telemetry", protected(http.HandlerFunc(s.telemetry)))
	mux.Handle("GET /v1/events", protected(http.HandlerFunc(s.events)))
	mux.Handle("GET /v1/processes", protected(http.HandlerFunc(s.processes)))
	mux.Handle("POST /v1/processes/{pid}/kill", protected(http.HandlerFunc(s.kill)))
	mux.Handle("GET /v1/terminal/sessions", protected(http.HandlerFunc(s.terminalSessions)))
	mux.Handle("GET /v1/terminal", protected(http.HandlerFunc(s.terminal)))
	mux.Handle("GET /v1/scan", protected(http.HandlerFunc(s.scanStatus)))
	mux.Handle("POST /v1/scan", protected(http.HandlerFunc(s.scanStart)))
	mux.Handle("GET /v1/scan/{id}", protected(http.HandlerFunc(s.scanGet)))
	mux.Handle("POST /v1/scan/{id}/cancel", protected(http.HandlerFunc(s.scanCancel)))
	mux.Handle("POST /v1/scan/{id}/quarantine", protected(http.HandlerFunc(s.scanQuarantine)))
	mux.Handle("GET /v1/quarantine", protected(http.HandlerFunc(s.quarantineList)))
	mux.Handle("POST /v1/quarantine/{id}/restore", protected(http.HandlerFunc(s.quarantineRestore)))
	mux.Handle("DELETE /v1/quarantine/{id}", protected(http.HandlerFunc(s.quarantineDelete)))
	return mux
}

// remoteHost is the caller's address without the port.
func remoteHost(r *http.Request) string {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

// protect requires a paired device's token and logs (at most once a minute per caller and path) who
// was turned away, so "connection failed" on a phone can be diagnosed from the agent's log. It logs
// no tokens and no request contents.
func (s *Server) protect(next http.Handler) http.Handler {
	guarded := s.Auth.Middleware(next)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.Auth.Verify(auth.BearerToken(r)) {
			s.noteRejected(remoteHost(r), r.URL.Path)
		}
		guarded.ServeHTTP(w, r)
	})
}

func (s *Server) noteRejected(host, path string) {
	key := host + " " + path
	now := time.Now()
	s.rejectMu.Lock()
	if s.rejectedLog == nil {
		s.rejectedLog = map[string]time.Time{}
	}
	last, seen := s.rejectedLog[key]
	if !seen || now.Sub(last) > time.Minute {
		s.rejectedLog[key] = now
		if len(s.rejectedLog) > 500 { // bound memory if someone sweeps paths
			s.rejectedLog = map[string]time.Time{key: now}
		}
		s.rejectMu.Unlock()
		log.Printf("auth: %s asked for %s without a valid token (pair the device first)", host, path)
		return
	}
	s.rejectMu.Unlock()
}

func (s *Server) pair(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<10)
	var req struct {
		Code  string `json:"code"`
		Label string `json:"label"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "send JSON {\"code\":\"XXXX-XXXX\",\"label\":\"my phone\"}")
		return
	}
	token, err := s.Auth.Pair(req.Code, req.Label)
	switch err {
	case nil:
		log.Printf("pair: %q paired from %s", req.Label, remoteHost(r))
		host, _ := os.Hostname()
		writeJSON(w, http.StatusOK, map[string]any{"token": token, "hostname": host, "api": APIVersion})
	case auth.ErrLocked:
		log.Printf("pair: attempt from %s refused, too many wrong codes (locked for a minute)", remoteHost(r))
		w.Header().Set("Retry-After", "60")
		writeErr(w, http.StatusTooManyRequests, err.Error())
	case auth.ErrBadCode:
		log.Printf("pair: attempt from %s with a wrong or expired code", remoteHost(r))
		writeErr(w, http.StatusUnauthorized, err.Error())
	default:
		writeErr(w, http.StatusInternalServerError, "could not save pairing")
	}
}

func (s *Server) newPairingCode(w http.ResponseWriter, r *http.Request) {
	if !auth.IsLoopback(r) {
		writeErr(w, http.StatusForbidden, "pairing codes can only be created on the node itself")
		return
	}
	code, valid, err := s.Auth.NewCode()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "could not create code")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"code": code, "valid_seconds": int(valid.Seconds())})
}

func (s *Server) capabilities(w http.ResponseWriter, _ *http.Request) {
	t := s.Sampler.Latest()
	features := s.Features
	features.Terminal = s.terminalReady()
	features.Scan = s.Scan != nil && s.Scan.Available()
	writeJSON(w, http.StatusOK, map[string]any{
		"agent": "i30ltz-node", "version": s.Version, "api": APIVersion,
		"hostname": t.Hostname, "os": t.OS, "features": features,
	})
}

func (s *Server) telemetry(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.Sampler.Latest())
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErr(w, http.StatusInternalServerError, "streaming not supported")
		return
	}
	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	send := func() bool {
		raw, err := json.Marshal(s.Sampler.Latest())
		if err != nil {
			return false
		}
		_, err = fmt.Fprintf(w, "event: telemetry\ndata: %s\n\n", raw)
		flusher.Flush()
		return err == nil
	}
	if !send() {
		return
	}
	tick := time.NewTicker(s.Sampler.Interval())
	ping := time.NewTicker(15 * time.Second)
	defer tick.Stop()
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-tick.C:
			if !send() {
				return
			}
		case <-ping.C:
			if _, err := fmt.Fprint(w, ": ping\n\n"); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}

func (s *Server) processes(w http.ResponseWriter, r *http.Request) {
	limit := 200
	if v := r.URL.Query().Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 5000 {
			writeErr(w, http.StatusBadRequest, "limit must be 1-5000")
			return
		}
		limit = n
	}
	list, err := s.Col.Processes(limit)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "cannot read process list")
		return
	}
	if list == nil {
		list = []sysinfo.Process{}
	}
	writeJSON(w, http.StatusOK, list)
}

func (s *Server) kill(w http.ResponseWriter, r *http.Request) {
	pid, err := strconv.Atoi(r.PathValue("pid"))
	if err != nil {
		writeErr(w, http.StatusBadRequest, "pid must be a number")
		return
	}
	force := r.URL.Query().Get("force") == "1"
	if err := s.Col.CanKill(pid); err != nil {
		writeErr(w, http.StatusForbidden, err.Error())
		return
	}
	if err := s.Col.Kill(pid, force); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "pid": pid, "force": force})
}
