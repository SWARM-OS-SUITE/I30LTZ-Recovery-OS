// Command i30ltz-node is the per-machine agent the I30LTZ Companion talks to.
//
//	i30ltz-node serve   [--listen tailscale,127.0.0.1] [--port 7437] [--config-dir DIR] [--terminal]
//	i30ltz-node shell   [SESSION]           open (or join) the tmux session the phone mirrors
//	i30ltz-node pair    [--port 7437]       print a one-time pairing code (run on the node)
//	i30ltz-node devices [--config-dir DIR]  list paired phones
//	i30ltz-node revoke LABEL [--config-dir DIR]
//	i30ltz-node version
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"i30ltz/node/internal/api"
	"i30ltz/node/internal/auth"
	"i30ltz/node/internal/scan"
	"i30ltz/node/internal/sysinfo"
	"i30ltz/node/internal/term"
)

const defaultPort = 7437

var version = "0.3.2"

func defaultConfigDir() string {
	if os.Geteuid() == 0 {
		return "/etc/i30ltz-node"
	}
	if d, err := os.UserConfigDir(); err == nil {
		return filepath.Join(d, "i30ltz-node")
	}
	return ".i30ltz-node"
}

func main() {
	args := os.Args[1:]
	cmd := "serve"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		cmd, args = args[0], args[1:]
	}
	var err error
	switch cmd {
	case "serve":
		err = runServe(args)
	case "shell":
		err = runShell(args)
	case "pair":
		err = runPair(args)
	case "devices":
		err = runDevices(args)
	case "revoke":
		err = runRevoke(args)
	case "version":
		fmt.Println("i30ltz-node", version)
	default:
		err = fmt.Errorf("unknown command %q (serve, shell, pair, devices, revoke, version)", cmd)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "i30ltz-node:", err)
		os.Exit(1)
	}
}

func runServe(args []string) error {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	listen := fs.String("listen", "tailscale,127.0.0.1", "comma list of addresses; 'tailscale' = tailscale0 IPv4")
	port := fs.Int("port", defaultPort, "TCP port")
	dir := fs.String("config-dir", defaultConfigDir(), "where paired.json lives (mode 0600)")
	terminal := fs.Bool("terminal", false, "let paired phones open a shell (tmux) on this node")
	maxTerm := fs.Int("max-terminals", 4, "most phone terminals open at once (with --terminal)")
	clamscan := fs.String("clamscan", "", "path to clamscan (default: found in PATH); enables malware scanning")
	clamDB := fs.String("clam-db", "", "ClamAV signature directory (default: ClamAV's own)")
	winSize := fs.String("window-size", term.DefaultWindowSize, "tmux window-size for phone sessions: smallest (exact mirror), latest, largest")
	_ = fs.Parse(args)

	store, err := auth.Open(*dir)
	if err != nil {
		return fmt.Errorf("config dir %s: %w", *dir, err)
	}
	col := sysinfo.NewCollector()
	sampler := sysinfo.NewSampler(col, 2*time.Second)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go sampler.Run(ctx)

	apiServer := api.New(store, col, sampler, version)
	scanner, err := scan.New(scan.Config{Binary: *clamscan, DBDir: *clamDB, StateDir: *dir})
	if err != nil {
		return fmt.Errorf("scan state in %s: %w", *dir, err)
	}
	quarantine, err := scan.OpenQuarantine(*dir)
	if err != nil {
		return fmt.Errorf("quarantine in %s: %w", *dir, err)
	}
	apiServer.Scan, apiServer.Quar = scanner, quarantine
	if scanner.Available() {
		log.Printf("malware scanning ready (ClamAV). Findings are only reported; nothing is deleted without a request from a paired phone.")
	} else {
		log.Printf("malware scanning unavailable: clamscan not found (install ClamAV)")
	}
	if *terminal {
		if !term.Available() {
			return errors.New("--terminal needs tmux; install it first (apt install tmux / pacman -S tmux)")
		}
		if !term.ValidWindowSize(*winSize) {
			return fmt.Errorf("--window-size must be one of %s", strings.Join(term.WindowSizes, ", "))
		}
		apiServer.EnableTerminal(*maxTerm, *winSize)
		log.Printf("terminal ENABLED: paired phones get a shell as user %d. Join from this machine with `i30ltz-node shell`.", os.Getuid())
	}
	srv := &http.Server{
		Handler:           apiServer.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		IdleTimeout:       60 * time.Second,
		// No WriteTimeout: /v1/events is a long-lived stream.
	}
	serve := func(host string) bool {
		ln, err := net.Listen("tcp", net.JoinHostPort(host, strconv.Itoa(*port)))
		if err != nil {
			log.Printf("cannot listen on %s: %v", host, err)
			return false
		}
		log.Printf("i30ltz-node %s listening on %s (config %s)", version, ln.Addr(), *dir)
		go func() {
			if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Printf("serve: %v", err)
			}
		}()
		return true
	}
	fixed, wantTailscale := splitListen(*listen)
	var started int
	for _, host := range fixed {
		if serve(host) {
			started++
		}
	}
	if wantTailscale {
		// Tailscale may come up after us (boot order): keep watching instead of giving up.
		go watchAddrs(ctx, tailscaleAddrs, 3*time.Second, func(addrs []string) {
			for _, a := range addrs {
				serve(a)
			}
		})
		if started == 0 {
			log.Printf("waiting for tailscale0 to come up…")
		}
	} else if started == 0 {
		return errors.New("no address to listen on; check --listen")
	}
	log.Printf("%d paired device(s). Run `i30ltz-node pair` on this machine to add one.", len(store.Devices()))
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return srv.Shutdown(shutdown)
}

// runShell replaces this process with a tmux client on the shared session, so what you type here
// is what the phone sees, and the other way round.
func runShell(args []string) error {
	name := term.DefaultSession
	if len(args) > 0 {
		name = args[0]
	}
	if !term.ValidSession(name) {
		return errors.New("session name must be 1-32 letters, digits, '_' or '-'")
	}
	path, err := exec.LookPath("tmux")
	if err != nil {
		return errors.New("tmux is not installed")
	}
	argv := []string{"tmux", "-u", "new-session", "-A", "-s", name}
	return syscall.Exec(path, argv, os.Environ())
}

func runPair(args []string) error {
	fs := flag.NewFlagSet("pair", flag.ExitOnError)
	port := fs.Int("port", defaultPort, "port the local agent listens on")
	_ = fs.Parse(args)
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%d/v1/pairing/new", *port))
	if err != nil {
		return fmt.Errorf("agent not reachable on 127.0.0.1:%d (is `i30ltz-node serve` running?): %w", *port, err)
	}
	defer resp.Body.Close()
	var out struct {
		Code         string `json:"code"`
		ValidSeconds int    `json:"valid_seconds"`
	}
	if resp.StatusCode != http.StatusOK || json.NewDecoder(resp.Body).Decode(&out) != nil {
		return fmt.Errorf("agent refused to create a pairing code (HTTP %d)", resp.StatusCode)
	}
	fmt.Printf("Pairing code: %s   (valid %d minutes, works once)\n", out.Code, out.ValidSeconds/60)
	fmt.Println("In the app: Nodes -> Add node -> I30LTZ agent -> enter this code.")
	return nil
}

func runDevices(args []string) error {
	fs := flag.NewFlagSet("devices", flag.ExitOnError)
	dir := fs.String("config-dir", defaultConfigDir(), "config directory")
	_ = fs.Parse(args)
	store, err := auth.Open(*dir)
	if err != nil {
		return err
	}
	list := store.Devices()
	if len(list) == 0 {
		fmt.Println("no paired devices")
	}
	for _, d := range list {
		fmt.Printf("%-24s paired %s\n", d.Label, d.CreatedAt.Local().Format("2006-01-02 15:04"))
	}
	return nil
}

func runRevoke(args []string) error {
	fs := flag.NewFlagSet("revoke", flag.ExitOnError)
	dir := fs.String("config-dir", defaultConfigDir(), "config directory")
	if len(args) == 0 || strings.HasPrefix(args[0], "-") {
		return errors.New("usage: i30ltz-node revoke LABEL [--config-dir DIR]")
	}
	label := args[0]
	_ = fs.Parse(args[1:])
	store, err := auth.Open(*dir)
	if err != nil {
		return err
	}
	n, err := store.Revoke(label)
	if err != nil {
		return err
	}
	fmt.Printf("revoked %d device(s) named %q\n", n, label)
	return nil
}
