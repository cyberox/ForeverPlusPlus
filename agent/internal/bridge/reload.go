package bridge

import (
	"io/fs"
	"path/filepath"
	"strings"
	"time"
)

// When Forever++'s own files change while the game runs (an agent editing it), the game is told,
// so it can offer a reload. The addon's folder in the game's Interface\AddOns is a link to where
// it's worked on, so its files are watched there, and Agent Chat's (its companion addon) with it.

var watchedAddOns = []string{"ForeverPlusPlus", "ForeverPlusPlus_AgentChat"}

// ReloadSettle is how long the files must stay unchanged before the game is told, so a run of
// edits asks once.
var ReloadSettle = 8 * time.Second

const reloadEvery = 3 * time.Second

var addonFiles = map[string]bool{".lua": true, ".toc": true, ".xml": true}

// addonChanged is when Forever++'s code last changed, zero if it can't be read.
func (b *Bridge) addonChanged() time.Time {
	var newest time.Time
	for _, name := range watchedAddOns {
		dir := filepath.Join(b.In.Game, "Interface", "AddOns", name)
		if real, err := filepath.EvalSymlinks(dir); err == nil {
			dir = real
		}
		filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || !addonFiles[strings.ToLower(filepath.Ext(path))] {
				return nil
			}
			if info, err := d.Info(); err == nil && info.ModTime().After(newest) {
				newest = info.ModTime()
			}
			return nil
		})
	}
	return newest
}

// reloadNews is when the code changed, to send, or zero: once it changed since this UI session
// began, has settled, and hasn't been sent.
func (b *Bridge) reloadNews() time.Time {
	if time.Since(b.reloadCheck) < reloadEvery {
		return time.Time{}
	}
	b.reloadCheck = time.Now()
	newest := b.addonChanged()
	if newest.IsZero() || !newest.After(b.sessionStart) || time.Since(newest) < ReloadSettle ||
		newest.Equal(b.sentReload) {
		return time.Time{}
	}
	return newest
}
