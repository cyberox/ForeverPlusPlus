package bridge

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// A new build of the program takes over from the running copy (main.go). The game keeps its
// session and the inbox it offered, and waits on that inbox: a copy that didn't know of it would
// leave the game waiting until it gives up on it (GIVE_UP in AgentChat.lua) and offers another.
// So the old copy hands over what the game expects of it, and the new one carries on from there.

// Handoff is what one copy of the program hands the next.
type Handoff struct {
	At      time.Time `json:"at"`
	Session string    `json:"session"`
	Slot    int       `json:"slot"`   // the inbox offered, if any
	Signal  int       `json:"signal"` // -1: none
	Inbox   bool      `json:"inbox"`
	Filled  [2]int    `json:"filled"` // the inbox last filled: slot, signal
	View    int       `json:"view"`
	Open    bool      `json:"open"`
	IDs     []string  `json:"ids"` // handle-1 -> thread id, as the game knows them
}

// handoffFresh is how old a handoff may be and still be used: the game moves on without it.
const handoffFresh = time.Minute

func handoffPath(data string) string { return filepath.Join(data, "handoff.json") }

// SaveHandoff writes what the next copy needs to carry on with the game's session.
func (b *Bridge) SaveHandoff() error {
	if b.session == "" {
		return nil
	}
	h := Handoff{At: time.Now(), Session: b.session, View: b.view, Open: b.open, IDs: b.ids, Signal: -1,
		Filled: [2]int{b.filled.slot, b.filled.signal}}
	if b.inbox != nil {
		h.Inbox, h.Slot, h.Signal = true, b.inbox.slot, b.inbox.signal
	}
	data, err := json.Marshal(h)
	if err != nil {
		return err
	}
	return os.WriteFile(handoffPath(b.Data), data, 0o600)
}

// Resume picks up a handoff the copy before left, if it's fresh, and says whether it did. The file
// goes either way: it's for the next copy only.
func (b *Bridge) Resume() bool {
	path := handoffPath(b.Data)
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	os.Remove(path)
	var h Handoff
	if json.Unmarshal(data, &h) != nil || h.Session == "" || time.Since(h.At) > handoffFresh {
		return false
	}
	b.start(h.Session, false) // as when joining a session: what it was sent goes again
	b.rejoined = false        // but the game's handles and view still hold
	for _, id := range h.IDs {
		b.handle(id)
	}
	b.view, b.open = h.View, h.Open
	b.filled = inbox{h.Filled[0], h.Filled[1]}
	if h.Inbox && h.Slot >= 0 && h.Slot < b.In.Slots && h.Signal < b.In.Signals {
		b.inbox = &inbox{h.Slot, h.Signal}
	}
	return true
}
