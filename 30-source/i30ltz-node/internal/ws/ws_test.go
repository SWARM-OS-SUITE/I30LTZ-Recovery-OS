package ws

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAcceptKeyMatchesRFCExample(t *testing.T) {
	// RFC 6455 section 1.3
	if got := acceptKey("dGhlIHNhbXBsZSBub25jZQ=="); got != "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" {
		t.Fatalf("got %s", got)
	}
}

// echoServer echoes every message back until the peer closes.
func echoServer(t *testing.T, idle time.Duration) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := Upgrade(w, r)
		if err != nil {
			return
		}
		if idle > 0 {
			c.SetIdle(idle)
		}
		defer c.Close(CloseNormal, "")
		for {
			op, data, err := c.ReadMessage()
			if err != nil {
				return
			}
			if c.WriteMessage(op, data) != nil {
				return
			}
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func wsURL(ts *httptest.Server) string { return "ws" + strings.TrimPrefix(ts.URL, "http") + "/" }

func TestEchoTextBinaryAndLargeFrames(t *testing.T) {
	ts := echoServer(t, 0)
	c, _, err := Dial(wsURL(ts), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close(CloseNormal, "")
	for _, size := range []int{0, 5, 125, 126, 300, 65535, 65536, 70000} {
		payload := bytes.Repeat([]byte{0xAB}, size)
		if err := c.WriteMessage(OpBinary, payload); err != nil {
			t.Fatalf("size %d write: %v", size, err)
		}
		op, got, err := c.ReadMessage()
		if err != nil || op != OpBinary || !bytes.Equal(got, payload) {
			t.Fatalf("size %d: op=%d len=%d err=%v", size, op, len(got), err)
		}
	}
	_ = c.WriteMessage(OpText, []byte("héllo"))
	if op, got, _ := c.ReadMessage(); op != OpText || string(got) != "héllo" {
		t.Fatalf("text echo: %d %q", op, got)
	}
}

// raw gives byte-level control for protocol edge cases.
type raw struct {
	nc net.Conn
	br *bufio.Reader
}

func rawDial(t *testing.T, ts *httptest.Server) *raw {
	t.Helper()
	nc, err := net.Dial("tcp", strings.TrimPrefix(ts.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { nc.Close() })
	io.WriteString(nc, "GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")
	br := bufio.NewReader(nc)
	resp, err := http.ReadResponse(br, nil)
	if err != nil || resp.StatusCode != 101 {
		t.Fatalf("handshake: %v %v", resp, err)
	}
	if resp.Header.Get("Sec-WebSocket-Accept") != "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" {
		t.Fatal("wrong accept header")
	}
	nc.SetDeadline(time.Now().Add(3 * time.Second))
	return &raw{nc, br}
}

func frame(fin bool, op int, masked bool, payload []byte) []byte {
	b0 := byte(op)
	if fin {
		b0 |= 0x80
	}
	var out []byte
	mb := byte(0)
	if masked {
		mb = 0x80
	}
	switch n := len(payload); {
	case n < 126:
		out = []byte{b0, mb | byte(n)}
	case n <= 0xffff:
		out = append([]byte{b0, mb | 126}, byte(n>>8), byte(n))
	default:
		out = append([]byte{b0, mb | 127}, make([]byte, 8)...)
		binary.BigEndian.PutUint64(out[2:], uint64(n))
	}
	key := []byte{1, 2, 3, 4}
	if masked {
		out = append(out, key...)
	}
	body := append([]byte(nil), payload...)
	if masked {
		for i := range body {
			body[i] ^= key[i%4]
		}
	}
	return append(out, body...)
}

// readServerFrame reads one unmasked frame sent by the server.
func (r *raw) readServerFrame(t *testing.T) (op int, payload []byte) {
	t.Helper()
	var h [2]byte
	if _, err := io.ReadFull(r.br, h[:]); err != nil {
		t.Fatalf("read header: %v", err)
	}
	n := int(h[1] & 0x7f)
	if n == 126 {
		var b [2]byte
		io.ReadFull(r.br, b[:])
		n = int(binary.BigEndian.Uint16(b[:]))
	}
	payload = make([]byte, n)
	io.ReadFull(r.br, payload)
	return int(h[0] & 0x0f), payload
}

func closeCode(payload []byte) int {
	if len(payload) < 2 {
		return -1
	}
	return int(binary.BigEndian.Uint16(payload))
}

func TestFragmentedMessageWithInterleavedPing(t *testing.T) {
	r := rawDial(t, echoServer(t, 0))
	r.nc.Write(frame(false, OpText, true, []byte("he")))
	r.nc.Write(frame(true, OpPing, true, []byte("p")))
	r.nc.Write(frame(false, OpCont, true, []byte("l")))
	r.nc.Write(frame(true, OpCont, true, []byte("lo")))
	if op, p := r.readServerFrame(t); op != OpPong || string(p) != "p" {
		t.Fatalf("expected pong first, got op %d %q", op, p)
	}
	if op, p := r.readServerFrame(t); op != OpText || string(p) != "hello" {
		t.Fatalf("expected reassembled hello, got op %d %q", op, p)
	}
}

func TestUnmaskedClientFrameIsAProtocolError(t *testing.T) {
	r := rawDial(t, echoServer(t, 0))
	r.nc.Write(frame(true, OpText, false, []byte("x")))
	op, p := r.readServerFrame(t)
	if op != OpClose || closeCode(p) != CloseProtocol {
		t.Fatalf("got op %d code %d", op, closeCode(p))
	}
}

func TestProtocolViolationsAreRefused(t *testing.T) {
	cases := map[string][]byte{
		"reserved bit set":            append([]byte{0xC1, 0x80}, 1, 2, 3, 4),
		"fragmented control frame":    frame(false, OpPing, true, nil),
		"oversized control frame":     frame(true, OpPing, true, make([]byte, 126)),
		"continuation without start":  frame(true, OpCont, true, []byte("x")),
		"unknown opcode":              frame(true, 0x3, true, nil),
		"text inside fragmented text": append(frame(false, OpText, true, []byte("a")), frame(true, OpText, true, []byte("b"))...),
	}
	for name, bytes := range cases {
		t.Run(name, func(t *testing.T) {
			r := rawDial(t, echoServer(t, 0))
			r.nc.Write(bytes)
			op, p := r.readServerFrame(t)
			if op != OpClose || closeCode(p) != CloseProtocol {
				t.Fatalf("got op %d code %d, want close %d", op, closeCode(p), CloseProtocol)
			}
		})
	}
}

func TestOversizedMessageIsRefusedBeforeReadingIt(t *testing.T) {
	r := rawDial(t, echoServer(t, 0))
	// Header only: claims 2 MB. The server must answer without waiting for the payload.
	hdr := []byte{0x82, 0x80 | 127, 0, 0, 0, 0, 0, 0x20, 0, 0, 1, 2, 3, 4}
	r.nc.Write(hdr)
	op, p := r.readServerFrame(t)
	if op != OpClose || closeCode(p) != CloseTooBig {
		t.Fatalf("got op %d code %d", op, closeCode(p))
	}
}

func TestFragmentsThatAddUpToTooMuchAreRefused(t *testing.T) {
	r := rawDial(t, echoServer(t, 0))
	chunk := make([]byte, MaxMessage/2+1)
	go func() {
		r.nc.Write(frame(false, OpBinary, true, chunk))
		r.nc.Write(frame(true, OpCont, true, chunk))
	}()
	op, p := r.readServerFrame(t)
	if op != OpClose || closeCode(p) != CloseTooBig {
		t.Fatalf("got op %d code %d", op, closeCode(p))
	}
}

func TestCloseHandshakeEchoesCode(t *testing.T) {
	r := rawDial(t, echoServer(t, 0))
	r.nc.Write(frame(true, OpClose, true, []byte{0x03, 0xE9, 'b', 'y', 'e'})) // 1001 going away
	op, p := r.readServerFrame(t)
	if op != OpClose || closeCode(p) != 1001 {
		t.Fatalf("got op %d code %d", op, closeCode(p))
	}
}

func TestIdleConnectionIsDropped(t *testing.T) {
	ts := echoServer(t, 150*time.Millisecond)
	c, _, err := Dial(wsURL(ts), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close(CloseNormal, "")
	c.idle = 2 * time.Second
	start := time.Now()
	if _, _, err := c.ReadMessage(); err == nil {
		t.Fatal("expected the server to hang up on an idle client")
	}
	if time.Since(start) > time.Second {
		t.Fatalf("server took %v to drop an idle client", time.Since(start))
	}
}

func TestBadHandshakesGetPlainHTTPErrors(t *testing.T) {
	ts := echoServer(t, 0)
	do := func(h map[string]string) int {
		req, _ := http.NewRequest("GET", ts.URL, nil)
		for k, v := range h {
			req.Header.Set(k, v)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		return resp.StatusCode
	}
	if code := do(nil); code != 400 {
		t.Errorf("plain GET: %d", code)
	}
	base := map[string]string{"Upgrade": "websocket", "Connection": "Upgrade", "Sec-WebSocket-Version": "13"}
	good := func() map[string]string {
		m := map[string]string{"Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ=="}
		for k, v := range base {
			m[k] = v
		}
		return m
	}
	noKey := good()
	delete(noKey, "Sec-WebSocket-Key")
	if code := do(noKey); code != 400 {
		t.Errorf("missing key: %d", code)
	}
	shortKey := good()
	shortKey["Sec-WebSocket-Key"] = "c2hvcnQ="
	if code := do(shortKey); code != 400 {
		t.Errorf("short key: %d", code)
	}
	oldVer := good()
	oldVer["Sec-WebSocket-Version"] = "8"
	if code := do(oldVer); code != 426 {
		t.Errorf("old version: %d want 426", code)
	}
}
