// Package term runs a program on a pseudo-terminal and attaches to tmux sessions.
// Linux only, standard library only (raw ioctls instead of cgo or a pty library).
package term

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"sync"
	"syscall"
	"unsafe"
)

// ioctl request numbers for amd64/arm64/riscv64 (the asm-generic values).
const (
	tiocgptn   = 0x80045430
	tiocsptlck = 0x40045431
	tiocswinsz = 0x5414
)

type winsize struct{ rows, cols, x, y uint16 }

func ioctl(fd uintptr, req uintptr, arg unsafe.Pointer) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(arg)); errno != 0 {
		return errno
	}
	return nil
}

// PTY is a child process attached to a pseudo-terminal. Read and Write act on the master side.
type PTY struct {
	master *os.File
	cmd    *exec.Cmd

	closeOnce sync.Once
	waitOnce  sync.Once
	waitErr   error
}

// Start runs cmd with a controlling terminal of the given size. cmd.Stdin/Stdout/Stderr and SysProcAttr are overwritten.
func Start(cmd *exec.Cmd, cols, rows uint16) (*PTY, error) {
	master, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/ptmx: %w", err)
	}
	fail := func(err error) (*PTY, error) { master.Close(); return nil, err }

	var unlock int32
	if err := ioctl(master.Fd(), tiocsptlck, unsafe.Pointer(&unlock)); err != nil {
		return fail(fmt.Errorf("unlock pty: %w", err))
	}
	var n uint32
	if err := ioctl(master.Fd(), tiocgptn, unsafe.Pointer(&n)); err != nil {
		return fail(fmt.Errorf("pty number: %w", err))
	}
	slave, err := os.OpenFile("/dev/pts/"+strconv.FormatUint(uint64(n), 10), os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return fail(fmt.Errorf("open pty slave: %w", err))
	}
	defer slave.Close()

	p := &PTY{master: master, cmd: cmd}
	if err := p.Resize(cols, rows); err != nil {
		return fail(err)
	}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	// Setsid + Setctty make the slave the child's controlling terminal (fd 0), so Ctrl-C and resize signals work.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		return fail(err)
	}
	return p, nil
}

// Read reads terminal output. After the child exits it returns an error (EIO on Linux).
func (p *PTY) Read(b []byte) (int, error) { return p.master.Read(b) }

// Write sends keystrokes to the child.
func (p *PTY) Write(b []byte) (int, error) { return p.master.Write(b) }

// Resize tells the child the terminal size (it receives SIGWINCH).
func (p *PTY) Resize(cols, rows uint16) error {
	if cols == 0 || rows == 0 {
		return errors.New("terminal size must be positive")
	}
	ws := winsize{rows: rows, cols: cols}
	return ioctl(p.master.Fd(), tiocswinsz, unsafe.Pointer(&ws))
}

// Pid is the child's process id.
func (p *PTY) Pid() int { return p.cmd.Process.Pid }

// Wait waits for the child to exit (once) and returns its result.
func (p *PTY) Wait() error {
	p.waitOnce.Do(func() { p.waitErr = p.cmd.Wait() })
	return p.waitErr
}

// Close hangs up the child (SIGHUP to its process group), closes the terminal and reaps the process.
// For a tmux client that detaches it; the tmux session itself keeps running.
func (p *PTY) Close() {
	p.closeOnce.Do(func() {
		if p.cmd.Process != nil {
			_ = syscall.Kill(-p.cmd.Process.Pid, syscall.SIGHUP)
		}
		p.master.Close()
		go p.Wait()
	})
}
