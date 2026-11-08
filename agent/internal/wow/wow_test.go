package wow

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/link"
)

func TestLuaString(t *testing.T) {
	got := LuaString("a\"b\\c\nd é|")
	want := `"a\"b\\c\010d \195\169|"`
	if got != want {
		t.Errorf("got %s want %s", got, want)
	}
}

func TestInstallFillUninstall(t *testing.T) {
	game := t.TempDir()
	if err := os.MkdirAll(filepath.Join(game, "Interface", "AddOns", "ForeverPlusPlus"), 0o755); err != nil {
		t.Fatal(err)
	}
	in := Install{Game: game, Data: t.TempDir(), Slots: 3, Interface: 16001}
	if err := in.Run(); err != nil {
		t.Fatal(err)
	}
	if err := in.Run(); err != nil {
		t.Fatalf("running install again: %v", err)
	}
	toc, err := os.ReadFile(filepath.Join(game, "Interface", "AddOns", link.SlotName(2), link.SlotName(2)+".toc"))
	if err != nil {
		t.Fatalf("the slot isn't reachable through the game's folder: %v", err)
	}
	if !strings.Contains(string(toc), "## LoadOnDemand: 1") || !strings.Contains(string(toc), "Data.lua") {
		t.Errorf("slot toc:\n%s", toc)
	}

	size := func(slot int, name string) int64 {
		info, err := os.Stat(filepath.Join(in.SlotDir(slot), name))
		if err != nil {
			return -1
		}
		return info.Size()
	}
	if size(2, readyWAV) <= 0 || size(2, readyTTF) <= 0 || size(2, checkTTF) != 0 {
		t.Error("install doesn't leave every slot armed")
	}
	if err := ClearSlot(in.SlotDir(1)); err != nil {
		t.Fatal(err)
	}
	if size(1, readyWAV) != -1 || size(1, readyTTF) != -1 || size(1, checkTTF) != 0 {
		t.Error("a cleared slot still reads as ready")
	}
	if err := FillSlot(in.SlotDir(1), map[string]any{"kind": "pong", "id": "7", "text": "hi"}); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(game, "Interface", "AddOns", link.SlotName(1), "Data.lua"))
	if !strings.Contains(string(data), `text = "hi",`) {
		t.Errorf("Data.lua:\n%s", data)
	}
	if size(1, readyWAV) <= 0 || size(1, readyTTF) <= 0 || size(1, checkTTF) <= 0 {
		t.Error("a filled slot doesn't read as ready")
	}

	if err := in.Uninstall(); err != nil {
		t.Fatal(err)
	}
	entries, _ := os.ReadDir(filepath.Join(game, "Interface", "AddOns"))
	if len(entries) != 1 || entries[0].Name() != "ForeverPlusPlus" {
		t.Errorf("left behind: %v", entries)
	}
}

// writeFrame writes an AddOns.txt the way the game's SaveAddOns would.
func writeFrame(t *testing.T, path string, frame []byte) {
	var b strings.Builder
	b.WriteString("ForeverPlusPlus: enabled\n")
	for i := 0; i < link.Bits; i++ {
		state := "disabled"
		if frame[i/8]&(1<<(i%8)) != 0 {
			state = "enabled"
		}
		fmt.Fprintf(&b, "%s: %s\n", link.BitName(i), state)
	}
	if err := os.WriteFile(path, []byte(b.String()), 0o644); err != nil {
		t.Fatal(err)
	}
}

func frameOf(seq, flags byte, payload string) []byte {
	f := make([]byte, link.Frame)
	f[0], f[1] = seq, flags|byte(len(payload))
	copy(f[2:], payload)
	f[30], f[31] = link.Checksum(f[:30])
	return f
}

func TestWatchReadsFrames(t *testing.T) {
	game := t.TempDir()
	dir := filepath.Join(game, "WTF", "Account", "1#1", "91", "Clutch-Pew")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "AddOns.txt")
	writeFrame(t, path, make([]byte, link.Frame)) // left from an earlier session

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	out := make(chan Message, 4)
	go Watch(ctx, game, out, func(s string) { t.Log(s) })
	time.Sleep(300 * time.Millisecond)

	for _, f := range [][]byte{
		make([]byte, link.Frame), // idle starts the session
		frameOf(1, link.First, "P|s|0|1|ping across two fr"),
		frameOf(2, link.Last, "ames"),
	} {
		writeFrame(t, path, f)
		time.Sleep(100 * time.Millisecond)
	}
	select {
	case m := <-out:
		if string(m.Data) != "P|s|0|1|ping across two frames" {
			t.Errorf("got %q", m.Data)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no message")
	}
}
