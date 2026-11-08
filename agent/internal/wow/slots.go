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
// per UI session. The game finds files only when it starts, so every file a slot uses exists
// from Install on; the program only changes what's in them. The two ready files are how the
// game learns a slot is filled without loading it: empty means not yet, a valid sound and image
// mean ready. (Which of the two the game notices while running is what the ping test measures.)

const (
	dataFile  = "Data.lua"
	readySFX  = "ready.wav"
	readyTGA  = "ready.tga"
	emptyData = "-- Written by the Forever Agent program. Empty until a reply is waiting.\n"
)

// ClearSlot empties a slot: no reply, not ready.
func ClearSlot(dir string) error {
	if err := os.WriteFile(filepath.Join(dir, dataFile), []byte(emptyData), 0o644); err != nil {
		return err
	}
	for _, f := range []string{readySFX, readyTGA} {
		if err := os.WriteFile(filepath.Join(dir, f), nil, 0o644); err != nil {
			return err
		}
	}
	return nil
}

// FillSlot writes a reply into a slot, then marks it ready. fields become the global
// ForeverPlusPlusAgentInbox table the game reads right after loading the slot.
func FillSlot(dir string, fields map[string]any) error {
	if err := os.WriteFile(filepath.Join(dir, dataFile), []byte(luaInbox(fields)), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, readySFX), silentWAV(), 0o644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, readyTGA), pixelTGA(), 0o644)
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

// pixelTGA is a 2x2 uncompressed 32-bit image.
func pixelTGA() []byte {
	b := make([]byte, 18+2*2*4)
	b[2] = 2 // uncompressed true color
	binary.LittleEndian.PutUint16(b[12:], 2)
	binary.LittleEndian.PutUint16(b[14:], 2)
	b[16] = 32
	b[17] = 8 | 0x20 // 8 alpha bits, top-left origin
	for i := 18; i < len(b); i++ {
		b[i] = 255
	}
	return b
}
