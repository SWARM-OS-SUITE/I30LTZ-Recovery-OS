package ws

import (
	"bufio"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"time"
)

// Dial opens a client connection to a ws:// URL. It exists so the agent's own
// tests can talk to the server; the phone app uses OkHttp.
func Dial(rawURL string, header http.Header) (*Conn, *http.Response, error) {
	u, err := url.Parse(rawURL)
	if err != nil || u.Scheme != "ws" {
		return nil, nil, errors.New("only ws:// URLs are supported")
	}
	nc, err := net.DialTimeout("tcp", u.Host, 5*time.Second)
	if err != nil {
		return nil, nil, err
	}
	var k [16]byte
	_, _ = rand.Read(k[:])
	key := base64.StdEncoding.EncodeToString(k[:])
	req := fmt.Sprintf("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n",
		u.RequestURI(), u.Host, key)
	for name, vals := range header {
		for _, v := range vals {
			req += name + ": " + v + "\r\n"
		}
	}
	_ = nc.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := nc.Write([]byte(req + "\r\n")); err != nil {
		nc.Close()
		return nil, nil, err
	}
	br := bufio.NewReader(nc)
	resp, err := http.ReadResponse(br, &http.Request{Method: "GET"})
	if err != nil {
		nc.Close()
		return nil, nil, err
	}
	if resp.StatusCode != http.StatusSwitchingProtocols || resp.Header.Get("Sec-WebSocket-Accept") != acceptKey(key) {
		nc.Close()
		return nil, resp, fmt.Errorf("handshake refused: HTTP %d", resp.StatusCode)
	}
	_ = nc.SetDeadline(time.Time{})
	return &Conn{c: nc, br: br, isClient: true, idle: defaultIdleFor}, resp, nil
}
