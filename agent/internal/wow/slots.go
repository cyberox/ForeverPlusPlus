package wow

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// A reply reaches the game through a slot: a load-on-demand helper addon whose Data.lua the
// program writes, and which the game then loads with C_AddOns.LoadAddOn. Each slot loads once
// per UI session.
//
// The ready files are how the game learns a slot is filled without loading it. The game knows
// only the files that existed when it started: it checks those on disk each time it asks (so
// one deleted later reads as missing, and back when it's made again), but never finds a name
// made later. So each slot has fixed ready files, and every one of them must exist when the
// game starts: Arm makes them all, at install and whenever the game closes. Three kinds, while
// the ping test finds which the game notices, with game sound on and off:
//   - ready.wav, a sound, deleted by Clear and made by Fill;
//   - ready.ttf, a font, the same;
//   - check.ttf, a font that always exists: empty after Clear, a real font after Fill.

const (
	dataFile  = "Data.lua"
	readyWAV  = "ready.wav"
	readyTTF  = "ready.ttf"
	checkTTF  = "check.ttf"
	emptyData = "-- Written by the Forever Agent program. Empty until a reply is waiting.\n"
)

// font is a small font every Windows has, for the font checks.
var font = sync.OnceValue(func() []byte {
	data, _ := os.ReadFile(filepath.Join(os.Getenv("WINDIR"), "Fonts", "marlett.ttf"))
	return data
})

func write(dir, name string, data []byte) error {
	return os.WriteFile(filepath.Join(dir, name), data, 0o644)
}

func remove(dir, name string) error {
	if err := os.Remove(filepath.Join(dir, name)); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// ArmSlot makes every ready file exist, so the game knows them when it next starts. The slot
// reads as ready until the game's first hello clears it.
func ArmSlot(dir string) error {
	old, _ := filepath.Glob(filepath.Join(dir, "ready_*")) // an earlier test's per-reply names
	for _, f := range old {
		os.Remove(f)
	}
	if err := write(dir, readyWAV, silentWAV()); err != nil {
		return err
	}
	if err := write(dir, readyTTF, font()); err != nil {
		return err
	}
	return write(dir, checkTTF, nil)
}

// ClearSlot empties a slot: no reply, not ready.
func ClearSlot(dir string) error {
	if err := write(dir, dataFile, []byte(emptyData)); err != nil {
		return err
	}
	for _, name := range []string{readyWAV, readyTTF} {
		if err := remove(dir, name); err != nil {
			return err
		}
	}
	return write(dir, checkTTF, nil)
}

// FillSlot writes a reply into a slot, then marks it ready. fields become the global
// ForeverPlusPlusAgentInbox table the game reads right after loading the slot.
func FillSlot(dir string, fields map[string]any) error {
	if err := write(dir, dataFile, []byte(luaInbox(fields))); err != nil {
		return err
	}
	if err := write(dir, readyWAV, silentWAV()); err != nil {
		return err
	}
	if err := write(dir, readyTTF, font()); err != nil {
		return err
	}
	return write(dir, checkTTF, font())
}

func luaInbox(fields map[string]any) string {
	keys := make([]string, 0, len(fields))
	for k := range fields {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString("-- Written by the Forever Agent program.\nForeverPlusPlusAgentInbox = {\n")
	for _, k := range keys {
		fmt.Fprintf(&b, "    %s = %s,\n", k, luaValue(fields[k]))
	}
	b.WriteString("}\n")
	return b.String()
}

func luaValue(v any) string {
	switch v := v.(type) {
	case string:
		return LuaString(v)
	case bool:
		return fmt.Sprint(v)
	case int, int64, float64:
		return fmt.Sprint(v)
	default:
		return LuaString(fmt.Sprint(v))
	}
}

// LuaString quotes s as a Lua 5.1 string literal: printable ASCII as is, everything else as a
// decimal escape, so any bytes (UTF-8 included) come through unchanged.
func LuaString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"' || c == '\\':
			b.WriteByte('\\')
			b.WriteByte(c)
		case c >= 32 && c < 127:
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, "\\%03d", c)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// silentWAV is a twentieth of a second of silence: 8 kHz, 8-bit, mono.
func silentWAV() []byte {
	const rate, samples = 8000, 400
	b := make([]byte, 44+samples)
	copy(b[0:], "RIFF")
	binary.LittleEndian.PutUint32(b[4:], uint32(36+samples))
	copy(b[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(b[16:], 16)
	binary.LittleEndian.PutUint16(b[20:], 1) // PCM
	binary.LittleEndian.PutUint16(b[22:], 1) // mono
	binary.LittleEndian.PutUint32(b[24:], rate)
	binary.LittleEndian.PutUint32(b[28:], rate) // bytes per second
	binary.LittleEndian.PutUint16(b[32:], 1)    // block align
	binary.LittleEndian.PutUint16(b[34:], 8)    // bits per sample
	copy(b[36:], "data")
	binary.LittleEndian.PutUint32(b[40:], samples)
	for i := 44; i < len(b); i++ {
		b[i] = 128 // silence in 8-bit PCM
	}
	return b
}
