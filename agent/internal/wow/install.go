// Package wow is the game side of the bridge: the helper addons, the reply slots, and watching
// each character's AddOns.txt.
//
// The helper addons live in the program's own folder (%LOCALAPPDATA%\ForeverPlusPlus\Agent).
// The game's Interface\AddOns only gets a junction to each, made once by Install, so everything
// written while the game runs lands outside the game's folder.
package wow

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/link"
)

// Install describes where things go.
type Install struct {
	Game      string // the client folder, e.g. D:\...\_forever_
	Data      string // the program's own folder for the helper addons
	Slots     int    // reply slots: how many replies a UI session can take before a /reload
	Interface int    // the TOC Interface number
}

// DefaultData is %LOCALAPPDATA%\ForeverPlusPlus\Agent.
func DefaultData() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base, _ = os.UserCacheDir()
	}
	return filepath.Join(base, "ForeverPlusPlus", "Agent")
}

func (in Install) addonsDir() string { return filepath.Join(in.Data, "addons") }
func (in Install) gameAddOns() string {
	return filepath.Join(in.Game, "Interface", "AddOns")
}

// SlotDir is where slot i's files are.
func (in Install) SlotDir(i int) string {
	return filepath.Join(in.addonsDir(), link.SlotName(i))
}

// names is every helper addon, bits then slots.
func (in Install) names() []string {
	names := make([]string, 0, link.Bits+in.Slots)
	for i := 0; i < link.Bits; i++ {
		names = append(names, link.BitName(i))
	}
	for i := 0; i < in.Slots; i++ {
		names = append(names, link.SlotName(i))
	}
	return names
}

// toc is a helper's TOC. Group puts it under Forever++ in the game's AddOns list.
func (in Install) toc(name string, files ...string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "## Interface: %d\n", in.Interface)
	fmt.Fprintf(&b, "## Title: |cff808080Forever++ Agent link: %s|r\n", name)
	b.WriteString("## Notes: Part of the link between Forever++'s Agent Chat and the Forever Agent program on this PC.\n")
	b.WriteString("## Group: ForeverPlusPlus\n")
	b.WriteString("## LoadOnDemand: 1\n")
	for _, f := range files {
		b.WriteString(f + "\n")
	}
	return b.String()
}

// Run makes the helper addons and links them into the game. Safe to run again: it rewrites the
// helpers and keeps links that already point at them. The game finds new addons only when it
// starts, so it must be restarted (not /reload) after the first run.
func (in Install) Run() error {
	if _, err := os.Stat(in.gameAddOns()); err != nil {
		return fmt.Errorf("no Interface\\AddOns in %s: %w", in.Game, err)
	}
	for _, name := range in.names() {
		dir := filepath.Join(in.addonsDir(), name)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		var files []string
		if strings.HasPrefix(name, "FPPAgentSlot") {
			files = []string{"Data.lua"}
		}
		if err := os.WriteFile(filepath.Join(dir, name+".toc"), []byte(in.toc(name, files...)), 0o644); err != nil {
			return err
		}
		if err := in.link(name, dir); err != nil {
			return err
		}
	}
	for i := 0; i < in.Slots; i++ {
		if err := ClearSlot(in.SlotDir(i)); err != nil {
			return err
		}
	}
	return nil
}

// link makes the game's Interface\AddOns\<name> a junction to dir, unless it already is one.
func (in Install) link(name, dir string) error {
	path := filepath.Join(in.gameAddOns(), name)
	if target, err := os.Readlink(path); err == nil {
		if samePath(target, dir) {
			return nil
		}
		return fmt.Errorf("%s already links somewhere else (%s)", path, target)
	} else if _, statErr := os.Lstat(path); statErr == nil {
		return fmt.Errorf("%s already exists and isn't ours; not touching it", path)
	}
	out, err := exec.Command("cmd", "/c", "mklink", "/J", path, dir).CombinedOutput()
	if err != nil {
		return fmt.Errorf("mklink %s: %v: %s", name, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// Uninstall removes the links from the game and the helper addons. It only removes a link that
// points into Data, never a real folder.
func (in Install) Uninstall() error {
	var errs []error
	entries, err := os.ReadDir(in.gameAddOns())
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), "FPPAgent") {
			continue
		}
		path := filepath.Join(in.gameAddOns(), e.Name())
		target, err := os.Readlink(path)
		if err != nil || !strings.HasPrefix(strings.ToLower(filepath.Clean(target)), strings.ToLower(filepath.Clean(in.addonsDir()))) {
			errs = append(errs, fmt.Errorf("%s isn't one of our links; left alone", path))
			continue
		}
		if err := os.Remove(path); err != nil {
			errs = append(errs, err)
		}
	}
	if err := os.RemoveAll(in.addonsDir()); err != nil {
		errs = append(errs, err)
	}
	return errors.Join(errs...)
}

func samePath(a, b string) bool {
	clean := func(p string) string {
		return strings.ToLower(filepath.Clean(strings.TrimPrefix(p, `\\?\`)))
	}
	return clean(a) == clean(b)
}
