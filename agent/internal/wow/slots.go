package wow

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// A reply reaches the game through a slot: a load-on-demand helper addon whose Data.lua the
// program writes, and which the game then loads with C_AddOns.LoadAddOn. Each slot loads once
// per UI session; LoadAddOn reads the file as it is then.
//
// A signal tells the game a reply is written, without loading anything: a tiny sound file in
// the FPPAgentSignals helper, which the program makes once the reply is written.
// PlaySoundFile says whether it's there, with game sound off too. What the game showed in tests
// (build 70862):
//   - It knows only files that existed when it started, and never finds a name made later. So
//     every signal must exist when the game starts: Arm makes them all while it's closed.
//   - It checks those on disk each time it asks, across /reload too: one deleted reads as
//     missing, and as there again once made.
//   - Once it has found one, it remembers it until it restarts, even after it's deleted.
// So each signal works once per game launch. The game skips any that already read as there.

const (
	dataFile  = "Data.lua"
	emptyData = "-- Written by the Forever Agent program. Empty until a reply is waiting.\n"
)

func write(dir, name string, data []byte) error {
	return os.WriteFile(filepath.Join(dir, name), data, 0o644)
}

// ClearSlot empties a slot.
func ClearSlot(dir string) error {
	old, _ := filepath.Glob(filepath.Join(dir, "*")) // anything but Data.lua and the TOC is from an earlier test
	for _, f := range old {
		base := filepath.Base(f)
		if base != dataFile && filepath.Ext(base) != ".toc" {
			os.Remove(f)
		}
	}
	return write(dir, dataFile, []byte(emptyData))
}

// FillSlot writes a reply into a slot. fields become the global ForeverPlusPlusAgentInbox
// table the game reads right after loading the slot.
func FillSlot(dir string, fields map[string]any) error {
	return write(dir, dataFile, []byte(luaInbox(fields)))
}

// SignalFile is signal i's file name.
func SignalFile(i int) string {
	return fmt.Sprintf("%04d.wav", i)
}

// MakeSignal makes signal i there.
func MakeSignal(dir string, i int) error {
	return write(dir, SignalFile(i), silentWAV())
}

// ClearSignals deletes every signal, so the ones the game hasn't found yet read as missing.
func ClearSignals(dir string, count int) error {
	for i := 0; i < count; i++ {
		if err := os.Remove(filepath.Join(dir, SignalFile(i))); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
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
