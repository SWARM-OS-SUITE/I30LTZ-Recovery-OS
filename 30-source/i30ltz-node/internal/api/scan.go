package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/scan"
)

// scanOK answers the request itself and returns false if scanning is not set up on this node.
func (s *Server) scanOK(w http.ResponseWriter) bool {
	if s.Scan == nil || s.Quar == nil {
		writeErr(w, http.StatusNotFound, "malware scanning is not set up on this node")
		return false
	}
	return true
}

func (s *Server) scanStatus(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"engine": s.Scan.Info(r.Context()), "scans": s.Scan.List()})
}

func (s *Server) scanStart(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4<<10)
	var req struct {
		Scope string `json:"scope"`
		Path  string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, `send JSON {"scope":"quick|home|full|path","path":"/absolute/path"}`)
		return
	}
	id, err := s.Scan.Start(req.Scope, req.Path)
	switch {
	case err == nil:
		log.Printf("scan: %q started a %s scan (%s)", s.Auth.Label(auth.BearerToken(r)), req.Scope, id)
		writeJSON(w, http.StatusAccepted, map[string]string{"id": id})
	case errors.Is(err, scan.ErrBusy):
		writeErr(w, http.StatusConflict, err.Error())
	case errors.Is(err, scan.ErrUnavailable):
		writeErr(w, http.StatusNotImplemented, err.Error())
	default:
		writeErr(w, http.StatusBadRequest, err.Error())
	}
}

func (s *Server) scanGet(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	res, ok := s.Scan.Get(r.PathValue("id"))
	if !ok {
		writeErr(w, http.StatusNotFound, "no such scan")
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) scanCancel(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	if !s.Scan.Cancel(r.PathValue("id")) {
		writeErr(w, http.StatusConflict, "that scan is not running")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"cancelled": true})
}

func (s *Server) scanQuarantine(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 8<<10)
	var req struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Path == "" {
		writeErr(w, http.StatusBadRequest, `send JSON {"path":"/file/from/this/scan's/findings"}`)
		return
	}
	item, err := s.Scan.Quarantine(s.Quar, r.PathValue("id"), req.Path)
	switch {
	case err == nil:
		log.Printf("scan: %q quarantined %q (%s)", s.Auth.Label(auth.BearerToken(r)), item.Original, item.Signature)
		writeJSON(w, http.StatusOK, item)
	case errors.Is(err, scan.ErrNotAFinding):
		writeErr(w, http.StatusForbidden, err.Error())
	case errors.Is(err, scan.ErrNoLongerInfected):
		writeErr(w, http.StatusConflict, err.Error())
	default:
		writeErr(w, http.StatusInternalServerError, err.Error())
	}
}

func (s *Server) quarantineList(w http.ResponseWriter, _ *http.Request) {
	if !s.scanOK(w) {
		return
	}
	items, err := s.Quar.List()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "cannot read the quarantine")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (s *Server) quarantineRestore(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	item, err := s.Quar.Restore(r.PathValue("id"))
	switch {
	case err == nil:
		log.Printf("scan: %q restored %q from quarantine", s.Auth.Label(auth.BearerToken(r)), item.Original)
		writeJSON(w, http.StatusOK, item)
	case errors.Is(err, scan.ErrNoSuchItem):
		writeErr(w, http.StatusNotFound, err.Error())
	case errors.Is(err, scan.ErrOriginalExists):
		writeErr(w, http.StatusConflict, err.Error())
	default:
		writeErr(w, http.StatusInternalServerError, err.Error())
	}
}

func (s *Server) quarantineDelete(w http.ResponseWriter, r *http.Request) {
	if !s.scanOK(w) {
		return
	}
	switch err := s.Quar.Delete(r.PathValue("id")); {
	case err == nil:
		log.Printf("scan: %q permanently deleted quarantined item %s", s.Auth.Label(auth.BearerToken(r)), r.PathValue("id"))
		writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
	case errors.Is(err, scan.ErrNoSuchItem):
		writeErr(w, http.StatusNotFound, err.Error())
	default:
		writeErr(w, http.StatusInternalServerError, err.Error())
	}
}
