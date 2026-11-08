package link

import (
	"bufio"
	"bytes"
	"fmt"
	"strings"
)

// BitName is the helper addon that holds bit i.
func BitName(i int) string {
	return fmt.Sprintf("FPPAgentBit%03d", i)
}

// SlotName is the load-on-demand helper addon a reply is written into.
func SlotName(i int) string {
	return fmt.Sprintf("FPPAgentSlot%03d", i)
}

// ParseAddOns reads AddOns.txt ("Name: enabled" per line) into each addon's state.
func ParseAddOns(data []byte) map[string]bool {
	states := map[string]bool{}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		name, state, ok := strings.Cut(strings.TrimSpace(scanner.Text()), ":")
		if !ok {
			continue
		}
		states[strings.TrimSpace(name)] = strings.TrimSpace(state) == "enabled"
	}
	return states
}

// FrameFromAddOns reads the frame in an AddOns.txt. ok is false when a helper is missing from
// it (not installed for this character, or the file is half written) or the checksum fails.
func FrameFromAddOns(data []byte) (frame []byte, ok bool) {
	states := ParseAddOns(data)
	bits := make([]bool, Bits)
	for i := range bits {
		on, found := states[BitName(i)]
		if !found {
			return nil, false
		}
		bits[i] = on
	}
	frame = FromBits(bits)
	return frame, Valid(frame)
}
