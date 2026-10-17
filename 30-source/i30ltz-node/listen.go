package main

import (
	"context"
	"net"
	"strings"
	"time"
)

// tailscaleAddrs returns the IPv4 addresses of the tailscale0 interface, or nil if it is not up.
func tailscaleAddrs() []string {
	iface, err := net.InterfaceByName("tailscale0")
	if err != nil {
		return nil
	}
	addrs, _ := iface.Addrs()
	var out []string
	for _, a := range addrs {
		if ipn, ok := a.(*net.IPNet); ok && ipn.IP.To4() != nil {
			out = append(out, ipn.IP.String())
		}
	}
	return out
}

// splitListen separates the --listen list into fixed hosts and whether "tailscale" was asked for.
func splitListen(spec string) (hosts []string, wantTailscale bool) {
	for _, item := range strings.Split(spec, ",") {
		switch item = strings.TrimSpace(item); item {
		case "":
		case "tailscale":
			wantTailscale = true
		default:
			hosts = append(hosts, item)
		}
	}
	return hosts, wantTailscale
}

// watchAddrs polls lookup until it returns addresses, then hands them to onFound once. It lets the
// agent start before Tailscale is up (for example at boot) and begin listening as soon as it is.
func watchAddrs(ctx context.Context, lookup func() []string, every time.Duration, onFound func([]string)) {
	for {
		if addrs := lookup(); len(addrs) > 0 {
			onFound(addrs)
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(every):
		}
	}
}
