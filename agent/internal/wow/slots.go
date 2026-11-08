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
// per UI session. The game finds addons only when it starts, so Data.lua exists from Install
// on and the program only changes what's in it. The ready files are how the game learns a slot
// is filled without loading it: they exist only while a reply waits. The game looks loose files
// up on disk each time it asks (an empty one counts as there), so each reply's ready files get
// a new name, `ready`, from the game: nothing it saw before can linger. A sound only answers
// while game sound is on, so fonts are tried too; which work is what the ping test measures.

const (
	dataFile  = "Data.lua"
	emptyData = "-- Written by the Forever Agent program. Empty until a reply is waiting.\n"
)

// Fonts every Windows has, for the font check: a small symbol font and a plain one.
var readyFonts = map[string]string{
	"_m.ttf": "marlett.ttf",
	"_a.ttf": "arial.ttf",
}

// ClearSlot empties a slot: no reply, no ready files.
func ClearSlot(dir string) error {
	if err := os.WriteFile(filepath.Join(dir, dataFile), []byte(emptyData), 0o644); err != nil {
		return err
	}
	old, _ := filepath.Glob(filepath.Join(dir, "ready*"))
	for _, f := range old {
		if err := os.Remove(f); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

// FillSlot writes a reply into a slot, then its ready files, named from `ready`. fields become
// the global ForeverPlusPlusAgentInbox table the game reads right after loading the slot.
func FillSlot(dir, ready string, fields map[string]any) error {
	if err := os.WriteFile(filepath.Join(dir, dataFile), []byte(luaInbox(fields)), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, ready+".wav"), silentWAV(), 0o644); err != nil {
		return err
	}
	fonts := filepath.Join(os.Getenv("WINDIR"), "Fonts")
	for suffix, font := range readyFonts {
		data, err := os.ReadFile(filepath.Join(fonts, font))
		if err != nil {
			continue // no such font here: that check just never answers
		}
		if err := os.WriteFile(filepath.Join(dir, ready+suffix), data, 0o644); err != nil {
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
