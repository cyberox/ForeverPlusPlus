// Forever Agent: the program on the PC that Forever++'s Agent Chat talks to.
//
// For now it only answers the link test: the game sends a ping through its AddOns.txt, and this
// writes the pong into a reply slot the game loads. See agent/README.md.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/link"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/wow"
)

const usage = `Usage: forever-agent <command> [flags]

Commands:
  install     make the helper addons and link them into the game (restart the game after)
  uninstall   remove the links and the helper addons
  run         answer the game

Flags:
`

func main() {
	flags := flag.NewFlagSet("forever-agent", flag.ExitOnError)
	game := flags.String("game", defaultGame(), "the game's client folder (or set WOW_DIR)")
	data := flags.String("data", wow.DefaultData(), "where the helper addons live")
	slots := flags.Int("slots", 100, "reply slots: replies per UI session before a /reload")
	iface := flags.Int("interface", 16001, "the TOC Interface number")
	flags.Usage = func() {
		fmt.Fprint(os.Stderr, usage)
		flags.PrintDefaults()
	}
	if len(os.Args) < 2 {
		flags.Usage()
		os.Exit(2)
	}
	command := os.Args[1]
	flags.Parse(os.Args[2:])
	in := wow.Install{Game: *game, Data: *data, Slots: *slots, Interface: *iface}
	log.SetFlags(log.Ltime | log.Lmicroseconds)

	var err error
	switch command {
	case "install":
		err = in.Run()
		if err == nil {
			fmt.Printf("Installed %d bit and %d slot helpers.\nRestart the game (not /reload) so it finds them.\n", link.Bits, in.Slots)
		}
	case "uninstall":
		err = in.Uninstall()
		if err == nil {
			fmt.Println("Removed. Restart the game to drop them from its list.")
		}
	case "run":
		err = run(in)
	default:
		flags.Usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "forever-agent:", err)
		os.Exit(1)
	}
}

func defaultGame() string {
	if dir := os.Getenv("WOW_DIR"); dir != "" {
		return dir
	}
	return `D:\BattleNet\World of Warcraft\_forever_`
}

func run(in wow.Install) error {
	in.Slots = in.InstalledSlots()
	if in.Slots == 0 {
		return errors.New("not installed: run `forever-agent install` first")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	// The game learns the ready files' names only when it starts, so they must all exist then:
	// arm them now if it isn't running, and again each time it closes.
	running := wow.GameRunning(in.Game)
	if !running {
		arm(in)
	} else {
		log.Println("The game is running. Its ready files are armed when it closes.")
	}
	go func() {
		tick := time.NewTicker(2 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
				now := wow.GameRunning(in.Game)
				if running && !now {
					arm(in)
				}
				running = now
			}
		}
	}()

	messages := make(chan wow.Message, 16)
	done := make(chan error, 1)
	go func() {
		done <- wow.Watch(ctx, in.Game, messages, func(s string) { log.Println("warning:", s) })
	}()
	log.Printf("Watching %s. Ctrl+C to stop.", filepath.Join(in.Game, "WTF"))

	for {
		select {
		case err := <-done:
			return err
		case m := <-messages:
			handle(in, m)
		}
	}
}

// handle answers one message. H|session|slots starts a UI session: every slot is cleared, since
// the game starts again at slot 0. P|session|slot|id|text is a ping: the pong goes into the slot.
func handle(in wow.Install, m wow.Message) {
	char := characterOf(m.File)
	parts := strings.SplitN(string(m.Data), "|", 5)
	switch parts[0] {
	case "H":
		if len(parts) < 3 {
			break
		}
		count, _ := strconv.Atoi(parts[2])
		for i := 0; i < count; i++ {
			if err := wow.ClearSlot(in.SlotDir(i)); err != nil {
				log.Printf("clearing slot %d: %v", i, err)
			}
		}
		log.Printf("%s: session %s started, %d slots cleared", char, parts[1], count)
		return
	case "P":
		if len(parts) < 5 {
			break
		}
		slot, err := strconv.Atoi(parts[2])
		if err != nil || slot < 0 {
			break
		}
		start := time.Now()
		err = wow.FillSlot(in.SlotDir(slot), map[string]any{
			"kind": "pong", "session": parts[1], "id": parts[3], "text": parts[4],
		})
		if err != nil {
			log.Printf("%s: ping %s: writing slot %d: %v", char, parts[3], slot, err)
			return
		}
		log.Printf("%s: ping %s %q -> slot %d (written in %s)", char, parts[3], parts[4], slot,
			time.Since(start).Round(time.Microsecond))
		return
	}
	log.Printf("%s: unknown message %q", char, m.Data)
}

func arm(in wow.Install) {
	if err := in.Arm(); err != nil {
		log.Println("arming the ready files:", err)
		return
	}
	log.Printf("Armed %d slots' ready files for the next game start.", in.Slots)
}

// characterOf is "Realm/Character" from a path ending in Account\<acct>\<realm>\<char>\AddOns.txt.
func characterOf(path string) string {
	dir := filepath.Dir(path)
	return filepath.Base(filepath.Dir(dir)) + "/" + filepath.Base(dir)
}
