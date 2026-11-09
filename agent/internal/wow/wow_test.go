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

func TestGameTextDropsEmoji(t *testing.T) {
	r := func(code rune) string { return string(code) }
	cases := map[string]string{
		"Hello! " + r(0x1F44B) + " Everything's fine": "Hello! Everything's fine", // waving hand
		"Done " + r(0x2705):                           "Done ",                    // check mark button
		r(0x1F468) + r(0x200D) + r(0x1F4BB) + " code": "code",                     // man, joiner, laptop
		"caf" + r(0xE9) + " " + r(0x2014) + " a | b":  "caf" + r(0xE9) + " " + r(0x2014) + " a | b",
	}
	for in, want := range cases {
		if got := GameText(in); got != want {
			t.Errorf("GameText(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestInstallFillUninstall(t *testing.T) {
	game := t.TempDir()
	if err := os.MkdirAll(filepath.Join(game, "Interface", "AddOns", "ForeverPlusPlus"), 0o755); err != nil {
		t.Fatal(err)
	}
	companion := t.TempDir()
	if err := os.WriteFile(filepath.Join(companion, CompanionName+".toc"), []byte("## Title: test\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	in := Install{Game: game, Data: t.TempDir(), Slots: 3, Signals: 5, Interface: 16001, Companion: companion}
	if err := in.Run(); err != nil {
		t.Fatal(err)
	}
	if err := in.Run(); err != nil {
		t.Fatalf("running install again: %v", err)
	}
	if _, err := os.Stat(filepath.Join(game, "Interface", "AddOns", CompanionName, CompanionName+".toc")); err != nil {
		t.Fatalf("Agent Chat isn't linked into the game: %v", err)
	}
	toc, err := os.ReadFile(filepath.Join(game, "Interface", "AddOns", link.SlotName(2), link.SlotName(2)+".toc"))
	if err != nil {
		t.Fatalf("the slot isn't reachable through the game's folder: %v", err)
	}
	if !strings.Contains(string(toc), "## LoadOnDemand: 1") || !strings.Contains(string(toc), "Data.lua") {
		t.Errorf("slot toc:\n%s", toc)
	}

	signal := func(i int) bool {
		_, err := os.Stat(filepath.Join(game, "Interface", "AddOns", SignalsName, SignalFile(i)))
		return err == nil
	}
	if !signal(0) || !signal(4) || signal(5) {
		t.Error("install doesn't arm exactly the signals asked for")
	}
	loaded := Install{Game: game, Data: in.Data}
	if !loaded.Load() || loaded.Slots != 3 || loaded.Signals != 5 {
		t.Errorf("Load read %d slots, %d signals", loaded.Slots, loaded.Signals)
	}
	if err := ClearSignals(in.SignalsDir(), in.Signals); err != nil {
		t.Fatal(err)
	}
	if signal(0) || signal(4) {
		t.Error("clearing left signals")
	}

	if err := FillSlot(in.SlotDir(1), map[string]any{"kind": "pong", "id": "7", "text": "hi"}); err != nil {
		t.Fatal(err)
	}
	if err := MakeSignal(in.SignalsDir(), 3); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(game, "Interface", "AddOns", link.SlotName(1), "Data.lua"))
	if !strings.Contains(string(data), `text = "hi",`) {
		t.Errorf("Data.lua:\n%s", data)
	}
	if !signal(3) || signal(2) {
		t.Error("making a signal made the wrong one")
	}

	if err := in.Uninstall(); err != nil {
		t.Fatal(err)
	}
	entries, _ := os.ReadDir(filepath.Join(game, "Interface", "AddOns"))
	if len(entries) != 1 || entries[0].Name() != "ForeverPlusPlus" {
		t.Errorf("left behind: %v", entries)
	}
	if _, err := os.Stat(filepath.Join(companion, CompanionName+".toc")); err != nil {
		t.Errorf("uninstall touched the Agent Chat folder itself: %v", err)
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
