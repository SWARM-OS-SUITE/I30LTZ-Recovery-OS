// Package ws is a small RFC 6455 WebSocket implementation (server side plus a
// test-friendly client). Standard library only, so the agent stays one static
// binary. It supports text/binary messages, fragmentation, ping/pong and the
// close handshake. It does not support extensions (no compression).
package ws

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	OpCont   = 0x0
	OpText   = 0x1
	OpBinary = 0x2
	OpClose  = 0x8
	OpPing   = 0x9
	OpPong   = 0xA

	// MaxMessage bounds one reassembled message. Terminal frames are tiny; this stops memory abuse.
	MaxMessage = 1 << 20

	CloseNormal    = 1000
	CloseProtocol  = 1002
	CloseTooBig    = 1009
	CloseInternal  = 1011
	handshakeGUID  = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	writeTimeout   = 10 * time.Second
	defaultIdleFor = 75 * time.Second
)

var (
	ErrClosed   = errors.New("websocket closed")
	ErrProtocol = errors.New("websocket protocol error")
)

// Conn is one WebSocket connection. Reads must come from a single goroutine;
// writes may come from many.
type Conn struct {
	c        net.Conn
	br       *bufio.Reader
	isClient bool // client frames are masked, server frames are not

	wmu       sync.Mutex
	closeOnce sync.Once
	idle      time.Duration
}

func acceptKey(key string) string {
	sum := sha1.Sum([]byte(key + handshakeGUID))
	return base64.StdEncoding.EncodeToString(sum[:])
}

func headerHas(h http.Header, name, token string) bool {
	for _, v := range h.Values(name) {
		for _, part := range strings.Split(v, ",") {
			if strings.EqualFold(strings.TrimSpace(part), token) {
				return true
			}
		}
	}
	return false
}

// Upgrade performs the server handshake. On failure it has already answered the
// request with an error status.
func Upgrade(w http.ResponseWriter, r *http.Request) (*Conn, error) {
	key := r.Header.Get("Sec-WebSocket-Key")
	raw, kerr := base64.StdEncoding.DecodeString(key)
	switch {
	case r.Method != http.MethodGet,
		!headerHas(r.Header, "Connection", "upgrade"),
		!headerHas(r.Header, "Upgrade", "websocket"),
		kerr != nil || len(raw) != 16:
		http.Error(w, "expected a WebSocket upgrade request", http.StatusBadRequest)
		return nil, ErrProtocol
	case r.Header.Get("Sec-WebSocket-Version") != "13":
		w.Header().Set("Sec-WebSocket-Version", "13")
		http.Error(w, "unsupported WebSocket version", http.StatusUpgradeRequired)
		return nil, ErrProtocol
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "cannot take over this connection", http.StatusInternalServerError)
		return nil, errors.New("ResponseWriter is not a Hijacker")
	}
	conn, rw, err := hj.Hijack()
	if err != nil {
		return nil, err
	}
	// The http.Server's per-request deadlines still apply to a hijacked conn.
	_ = conn.SetDeadline(time.Time{})
	resp := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " +
		acceptKey(key) + "\r\n\r\n"
	_ = conn.SetWriteDeadline(time.Now().Add(writeTimeout))
	if _, err := io.WriteString(conn, resp); err != nil {
		conn.Close()
		return nil, err
	}
	_ = conn.SetWriteDeadline(time.Time{})
	return &Conn{c: conn, br: rw.Reader, idle: defaultIdleFor}, nil
}

// SetIdle sets how long a read may wait for the next frame (any frame, including pongs).
func (c *Conn) SetIdle(d time.Duration) { c.idle = d }

func (c *Conn) RemoteAddr() string { return c.c.RemoteAddr().String() }

func (c *Conn) readFrame() (fin bool, op int, payload []byte, err error) {
	if c.idle > 0 {
		_ = c.c.SetReadDeadline(time.Now().Add(c.idle))
	}
	var h [2]byte
	if _, err = io.ReadFull(c.br, h[:]); err != nil {
		return
	}
	fin = h[0]&0x80 != 0
	op = int(h[0] & 0x0f)
	if h[0]&0x70 != 0 { // RSV bits: no extension was negotiated
		return fin, op, nil, ErrProtocol
	}
	masked := h[1]&0x80 != 0
	if masked == c.isClient { // server must receive masked frames; client must receive unmasked
		return fin, op, nil, ErrProtocol
	}
	n := uint64(h[1] & 0x7f)
	switch n {
	case 126:
		var b [2]byte
		if _, err = io.ReadFull(c.br, b[:]); err != nil {
			return
		}
		n = uint64(binary.BigEndian.Uint16(b[:]))
	case 127:
		var b [8]byte
		if _, err = io.ReadFull(c.br, b[:]); err != nil {
			return
		}
		n = binary.BigEndian.Uint64(b[:])
		if n>>63 != 0 {
			return fin, op, nil, ErrProtocol
		}
	}
	if op >= OpClose && (!fin || n > 125) { // control frames: unfragmented, short
		return fin, op, nil, ErrProtocol
	}
	if n > MaxMessage {
		return fin, op, nil, errTooBig
	}
	var key [4]byte
	if masked {
		if _, err = io.ReadFull(c.br, key[:]); err != nil {
			return
		}
	}
	payload = make([]byte, n)
	if _, err = io.ReadFull(c.br, payload); err != nil {
		return
	}
	if masked {
		for i := range payload {
			payload[i] ^= key[i%4]
		}
	}
	return fin, op, payload, nil
}

var errTooBig = errors.New("websocket message too big")

// ReadMessage returns the next text or binary message. Pings are answered and
// pongs swallowed. A close from the peer is answered and reported as ErrClosed.
func (c *Conn) ReadMessage() (op int, data []byte, err error) {
	var msgOp int
	var buf []byte
	for {
		fin, opcode, payload, ferr := c.readFrame()
		if ferr != nil {
			switch ferr {
			case ErrProtocol:
				c.Close(CloseProtocol, "protocol error")
			case errTooBig:
				c.Close(CloseTooBig, "message too big")
			}
			return 0, nil, ferr
		}
		switch opcode {
		case OpPing:
			if werr := c.write(OpPong, payload); werr != nil {
				return 0, nil, werr
			}
		case OpPong:
		case OpClose:
			code := CloseNormal
			if len(payload) >= 2 {
				code = int(binary.BigEndian.Uint16(payload))
			}
			c.Close(code, "")
			return 0, nil, ErrClosed
		case OpText, OpBinary:
			if msgOp != 0 {
				c.Close(CloseProtocol, "new message inside a fragmented one")
				return 0, nil, ErrProtocol
			}
			msgOp, buf = opcode, payload
			if fin {
				return msgOp, buf, nil
			}
		case OpCont:
			if msgOp == 0 {
				c.Close(CloseProtocol, "unexpected continuation")
				return 0, nil, ErrProtocol
			}
			if len(buf)+len(payload) > MaxMessage {
				c.Close(CloseTooBig, "message too big")
				return 0, nil, errTooBig
			}
			buf = append(buf, payload...)
			if fin {
				return msgOp, buf, nil
			}
		default:
			c.Close(CloseProtocol, "unknown opcode")
			return 0, nil, ErrProtocol
		}
	}
}

func (c *Conn) write(op int, payload []byte) error {
	var hdr [14]byte
	hdr[0] = 0x80 | byte(op)
	n := len(payload)
	h := 2
	maskBit := byte(0)
	if c.isClient {
		maskBit = 0x80
	}
	switch {
	case n < 126:
		hdr[1] = maskBit | byte(n)
	case n <= 0xffff:
		hdr[1] = maskBit | 126
		binary.BigEndian.PutUint16(hdr[2:], uint16(n))
		h = 4
	default:
		hdr[1] = maskBit | 127
		binary.BigEndian.PutUint64(hdr[2:], uint64(n))
		h = 10
	}
	body := payload
	if c.isClient {
		key := [4]byte{0x37, 0xfa, 0x21, 0x3d}
		copy(hdr[h:], key[:])
		h += 4
		body = make([]byte, n)
		for i := range payload {
			body[i] = payload[i] ^ key[i%4]
		}
	}
	frame := make([]byte, 0, h+len(body))
	frame = append(append(frame, hdr[:h]...), body...)

	c.wmu.Lock()
	defer c.wmu.Unlock()
	_ = c.c.SetWriteDeadline(time.Now().Add(writeTimeout))
	_, err := c.c.Write(frame)
	return err
}

// WriteMessage sends one text or binary message.
func (c *Conn) WriteMessage(op int, data []byte) error {
	if op != OpText && op != OpBinary {
		return ErrProtocol
	}
	return c.write(op, data)
}

// Ping sends a keep-alive ping.
func (c *Conn) Ping() error { return c.write(OpPing, nil) }

// Close sends a close frame (best effort) and closes the connection. Safe to call many times.
func (c *Conn) Close(code int, reason string) {
	c.closeOnce.Do(func() {
		if len(reason) > 100 {
			reason = reason[:100]
		}
		payload := make([]byte, 2+len(reason))
		binary.BigEndian.PutUint16(payload, uint16(code))
		copy(payload[2:], reason)
		_ = c.write(OpClose, payload)
		_ = c.c.Close()
	})
}
