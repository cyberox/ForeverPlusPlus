// Package background runs Forever Agent as one quiet copy: started without a window, at Windows
// sign-in if the player wants, stopped by asking, and started again when its program file is
// replaced by a new build.
package background

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

// Kernel objects named for this Windows session: one that exists while a copy runs, and one a
// copy waits on to be told to stop.
const (
	runningName = `Local\ForeverPlusPlusAgent.Running`
	stopName    = `Local\ForeverPlusPlusAgent.Stop`
	runKey      = `Software\Microsoft\Windows\CurrentVersion\Run`
	runValue    = "Forever Agent"
)

// ErrRunning means another copy already runs.
var ErrRunning = errors.New("Forever Agent is already running (forever-agent stop ends it)")

// Lock is held by the running copy for its life.
type Lock struct {
	running windows.Handle
	stop    windows.Handle
}

// Acquire makes this the running copy, or returns ErrRunning.
func Acquire() (*Lock, error) {
	name, _ := windows.UTF16PtrFromString(runningName)
	h, err := windows.CreateMutex(nil, false, name)
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		windows.CloseHandle(h)
		return nil, ErrRunning
	}
	if err != nil {
		return nil, err
	}
	stop, err := stopEvent()
	if err != nil {
		windows.CloseHandle(h)
		return nil, err
	}
	windows.ResetEvent(stop) // a stop asked of an earlier copy isn't for this one
	return &Lock{running: h, stop: stop}, nil
}

// Stopped is closed when another command asks this copy to stop.
func (l *Lock) Stopped() <-chan struct{} {
	ch := make(chan struct{})
	go func() {
		windows.WaitForSingleObject(l.stop, windows.INFINITE)
		close(ch)
	}()
	return ch
}

// Release lets another copy run.
func (l *Lock) Release() {
	windows.CloseHandle(l.stop)
	windows.CloseHandle(l.running)
}

func stopEvent() (windows.Handle, error) {
	name, _ := windows.UTF16PtrFromString(stopName)
	h, err := windows.CreateEvent(nil, 1, 0, name)
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		err = nil // the running copy's: the same event
	}
	return h, err
}

// Running says whether a copy runs.
func Running() bool {
	name, _ := windows.UTF16PtrFromString(runningName)
	h, err := windows.CreateMutex(nil, false, name)
	if h != 0 {
		windows.CloseHandle(h)
	}
	return errors.Is(err, windows.ERROR_ALREADY_EXISTS)
}

// Stop asks the running copy to stop, and waits up to `wait` for it to go.
func Stop(wait time.Duration) error {
	if !Running() {
		return errors.New("Forever Agent isn't running")
	}
	stop, err := stopEvent()
	if err != nil {
		return err
	}
	defer windows.CloseHandle(stop)
	if err := windows.SetEvent(stop); err != nil {
		return err
	}
	for end := time.Now().Add(wait); time.Now().Before(end); time.Sleep(100 * time.Millisecond) {
		if !Running() {
			return nil
		}
	}
	return errors.New("Forever Agent was asked to stop but is still running")
}

// WaitForExit waits up to `wait` for process pid to end.
func WaitForExit(pid int, wait time.Duration) {
	h, err := windows.OpenProcess(windows.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return // gone already
	}
	defer windows.CloseHandle(h)
	windows.WaitForSingleObject(h, uint32(wait/time.Millisecond))
}

// Spawn starts the program with args, without a window when hidden, and doesn't wait for it.
func Spawn(exe string, args []string, hidden bool) error {
	cmd := exec.Command(exe, args...)
	if hidden {
		cmd.SysProcAttr = &syscall.SysProcAttr{
			HideWindow:    true,
			CreationFlags: windows.CREATE_NO_WINDOW | windows.CREATE_NEW_PROCESS_GROUP,
		}
	} else {
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr // the same console, which it keeps using
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}

// startupCommand is what Windows runs at sign-in. The program is a console program, which Windows
// would show a terminal window for; conhost --headless gives it a console with no window.
func startupCommand(exe string) string {
	conhost := filepath.Join(os.Getenv("SystemRoot"), "System32", "conhost.exe")
	return fmt.Sprintf(`"%s" --headless "%s" run -background`, conhost, exe)
}

// SetStartup starts the program at sign-in (or stops doing so), for this Windows user only.
func SetStartup(on bool, exe string) error {
	k, err := registry.OpenKey(registry.CURRENT_USER, runKey, registry.SET_VALUE|registry.QUERY_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if !on {
		if err := k.DeleteValue(runValue); err != nil && !errors.Is(err, registry.ErrNotExist) {
			return err
		}
		return nil
	}
	return k.SetStringValue(runValue, startupCommand(exe))
}

// Startup says whether the program starts at sign-in, and for which program file.
func Startup() (bool, string) {
	k, err := registry.OpenKey(registry.CURRENT_USER, runKey, registry.QUERY_VALUE)
	if err != nil {
		return false, ""
	}
	defer k.Close()
	v, _, err := k.GetStringValue(runValue)
	if err != nil {
		return false, ""
	}
	// The program file is the second quoted part: conhost's, then ours.
	parts := strings.Split(v, `"`)
	if len(parts) >= 4 {
		return true, parts[3]
	}
	return true, v
}
