package main

import (
	"context"
	"reflect"
	"sync/atomic"
	"testing"
	"time"
)

func TestSplitListen(t *testing.T) {
	hosts, ts := splitListen("tailscale, 127.0.0.1 ,,10.0.0.5")
	if !ts || !reflect.DeepEqual(hosts, []string{"127.0.0.1", "10.0.0.5"}) {
		t.Fatalf("%v %v", hosts, ts)
	}
	if hosts, ts := splitListen("127.0.0.1"); ts || len(hosts) != 1 {
		t.Fatalf("%v %v", hosts, ts)
	}
}

func TestWatchAddrsWaitsForTheInterfaceThenReportsOnce(t *testing.T) {
	var calls atomic.Int32
	lookup := func() []string {
		if calls.Add(1) < 4 {
			return nil // tailscale not up yet
		}
		return []string{"100.82.1.19"}
	}
	got := make(chan []string, 2)
	go watchAddrs(context.Background(), lookup, 5*time.Millisecond, func(a []string) { got <- a })
	select {
	case a := <-got:
		if !reflect.DeepEqual(a, []string{"100.82.1.19"}) {
			t.Fatalf("got %v", a)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("never reported the address")
	}
	time.Sleep(50 * time.Millisecond)
	if len(got) != 0 {
		t.Fatal("must report only once")
	}
}

func TestWatchAddrsStopsWhenCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		watchAddrs(ctx, func() []string { return nil }, 5*time.Millisecond, func([]string) {})
		close(done)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("watcher did not stop")
	}
}
