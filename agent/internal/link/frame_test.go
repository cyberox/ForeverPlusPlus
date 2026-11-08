package link

import (
	"bytes"
	"fmt"
	"strings"
	"testing"
)

// The same vectors as tests/spec/agentlink.lua, so both sides agree on the format.
var (
	hello = []byte{1, 197, 104, 101, 108, 108, 111, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 220, 174}
	twoA = []byte{1, 92, 80, 124, 97, 49, 98, 50, 124, 48, 124, 49, 124, 112, 105, 110, 103, 32, 97, 99,
		114, 111, 115, 115, 32, 116, 119, 111, 32, 102, 135, 90}
	twoB = []byte{2, 134, 114, 97, 109, 101, 115, 33, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 195, 20}
	idle = make([]byte, Frame)
)

// addOnsTxt writes a frame the way the game would: every helper's line, among other addons.
func addOnsTxt(frame []byte) []byte {
	var b strings.Builder
	b.WriteString("ForeverPlusPlus: enabled\nTwitchEmotes: disabled\n")
	for i := 0; i < Bits; i++ {
		state := "disabled"
		if frame[i/8]&(1<<(i%8)) != 0 {
			state = "enabled"
		}
		fmt.Fprintf(&b, "%s: %s\n", BitName(i), state)
	}
	b.WriteString("Blizzard_ObjectiveTracker: enabled\n")
	return []byte(b.String())
}

func TestChecksumMatchesLua(t *testing.T) {
	for _, f := range [][]byte{hello, twoA, twoB, idle} {
		if !Valid(f) {
			t.Errorf("frame %v: checksum fails", f[:2])
		}
	}
	broken := append([]byte(nil), hello...)
	broken[4] ^= 1
	if Valid(broken) {
		t.Error("a flipped bit passes the checksum")
	}
}

func TestAddOnsRoundTrip(t *testing.T) {
	frame, ok := FrameFromAddOns(addOnsTxt(hello))
	if !ok || !bytes.Equal(frame, hello) {
		t.Fatalf("got %v %v", frame, ok)
	}
	half := addOnsTxt(hello)
	if _, ok := FrameFromAddOns(half[:len(half)/2]); ok {
		t.Error("a half-written file reads as a frame")
	}
}

func TestParseAddOnsCRLF(t *testing.T) {
	states := ParseAddOns([]byte("A: enabled\r\nB: disabled\r\n"))
	if !states["A"] || states["B"] {
		t.Errorf("got %v", states)
	}
}

func TestReaderJoinsFrames(t *testing.T) {
	r := NewReader()
	if _, done, _ := r.Read(idle); done {
		t.Fatal("the first frame seen is news")
	}
	if _, done, _ := r.Read(twoA); done {
		t.Fatal("done after the first of two")
	}
	r.Read(twoA) // seen again: ignored
	msg, done, dropped := r.Read(twoB)
	if !done || dropped || string(msg) != "P|a1b2|0|1|ping across two frames!" {
		t.Fatalf("got %q %v %v", msg, done, dropped)
	}
}

func TestReaderIgnoresLeftover(t *testing.T) {
	r := NewReader()
	if _, done, _ := r.Read(hello); done {
		t.Fatal("a frame from before the program started was read")
	}
	r.Read(idle)
	msg, done, _ := r.Read(hello)
	if !done || string(msg) != "hello" {
		t.Fatalf("got %q %v", msg, done)
	}
}

func TestReaderDropsGap(t *testing.T) {
	r := NewReader()
	r.Read(idle)
	r.Read(twoA)
	skipped := append([]byte(nil), twoB...)
	skipped[0] = 3 // frame 2 was missed
	a, b := Checksum(skipped[:Frame-2])
	skipped[Frame-2], skipped[Frame-1] = a, b
	if _, done, dropped := r.Read(skipped); done || !dropped {
		t.Fatalf("done %v dropped %v", done, dropped)
	}
}
