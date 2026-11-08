package wow

import (
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// GameRunning says whether this client folder's Wow.exe is running with a window. A Wow.exe
// without one is a hung leftover (seen: one ten hours old, after the game had closed) and
// doesn't count, nor does another client's.
func GameRunning(game string) bool {
	exe := strings.ToLower(filepath.Clean(filepath.Join(game, "Wow.exe")))
	pids := map[uint32]bool{}
	snap, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return false
	}
	defer windows.CloseHandle(snap)
	var entry windows.ProcessEntry32
	entry.Size = uint32(unsafe.Sizeof(entry))
	for err = windows.Process32First(snap, &entry); err == nil; err = windows.Process32Next(snap, &entry) {
		if strings.EqualFold(windows.UTF16ToString(entry.ExeFile[:]), "Wow.exe") &&
			strings.ToLower(processPath(entry.ProcessID)) == exe {
			pids[entry.ProcessID] = true
		}
	}
	if len(pids) == 0 {
		return false
	}
	found := false
	callback := syscall.NewCallback(func(hwnd windows.HWND, _ uintptr) uintptr {
		var pid uint32
		windows.GetWindowThreadProcessId(hwnd, &pid)
		if pids[pid] && windows.IsWindowVisible(hwnd) {
			found = true
			return 0 // stop
		}
		return 1
	})
	windows.EnumWindows(callback, nil)
	return found
}

func processPath(pid uint32) string {
	h, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return ""
	}
	defer windows.CloseHandle(h)
	buf := make([]uint16, windows.MAX_PATH)
	size := uint32(len(buf))
	if err := windows.QueryFullProcessImageName(h, 0, &buf[0], &size); err != nil {
		return ""
	}
	return filepath.Clean(windows.UTF16ToString(buf[:size]))
}
