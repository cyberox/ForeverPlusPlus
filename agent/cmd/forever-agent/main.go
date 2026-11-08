// Forever Agent: the program on the PC that Forever++'s Agent Chat talks to.
//
// For now it only answers the link test: the game sends a ping through its AddOns.txt, and this
// writes the pong into a reply slot the game loads. See agent/README.md.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/bridge"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/link"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/t3"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/wow"
)

const usage = `Usage: forever-agent <command> [flags]

Commands:
  install     make the helper addons and link them into the game (restart the game after)
  uninstall   remove the links and the helper addons
  run         answer the game
  login       sign in to T3 Code (approve it in the browser)
  t3 tools    list T3's tools and what they take
  t3 call <tool> [json]   call one of T3's tools and print what it returns

Flags:
`

func main() {
	flags := flag.NewFlagSet("forever-agent", flag.ExitOnError)
	game := flags.String("game", defaultGame(), "the game's client folder (or set WOW_DIR)")
	data := flags.String("data", wow.DefaultData(), "where the helper addons live")
	slots := flags.Int("slots", 300, "reply slots: replies per UI session before a /reload")
	signals := flags.Int("signals", 2000, "ready signals: replies per game launch told of at once")
	iface := flags.Int("interface", 16001, "the TOC Interface number")
	server := flags.String("t3", t3.DefaultServer(), "the T3 Code server, for login")
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
	in := wow.Install{Game: *game, Data: *data, Slots: *slots, Signals: *signals, Interface: *iface}
	log.SetFlags(log.Ltime | log.Lmicroseconds)

	var err error
	switch command {
	case "install":
		err = in.Run()
		if err == nil {
			fmt.Printf("Installed %d bit and %d slot helpers, and %d signals.\nRestart the game (not /reload) so it finds them.\n",
				link.Bits, in.Slots, in.Signals)
		}
	case "uninstall":
		err = in.Uninstall()
		if err == nil {
			fmt.Println("Removed. Restart the game to drop them from its list.")
		}
	case "run":
		err = run(in, *data)
	case "login":
		err = login(*data, *server)
	case "t3":
		err = t3Command(*data, flags.Args())
	default:
		flags.Usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "forever-agent:", err)
		os.Exit(1)
	}
}

const version = "0.1.0"

func login(data, server string) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	tok, err := t3.Login(ctx, server, func(u string) {
		fmt.Println("Approve Forever Agent in the browser. If it didn't open, go to:\n  " + u)
	})
	if err != nil {
		return err
	}
	if err := tok.Save(data); err != nil {
		return err
	}
	until := "until T3 ends it"
	if !tok.ExpiresAt.IsZero() {
		until = "until " + tok.ExpiresAt.Local().Format("Jan 2 15:04")
	}
	fmt.Printf("Signed in to %s (%s), %s.\n", tok.Server, tok.Scope, until)
	return nil
}

// t3Command is for finding out what T3 offers: `t3 tools`, and `t3 call <tool> [json]`.
func t3Command(data string, args []string) error {
	if len(args) == 0 {
		return errors.New("t3 tools, or t3 call <tool> [json]")
	}
	tok, err := t3.LoadToken(data)
	if err != nil {
		return t3.ErrSignIn
	}
	ctx := context.Background()
	client, err := t3.Connect(ctx, tok, version)
	if err != nil {
		return err
	}
	defer client.Close()
	switch args[0] {
	case "tools":
		tools, err := client.Tools(ctx)
		if err != nil {
			return err
		}
		for _, tool := range tools {
			fmt.Printf("%s\n  %s\n  %s\n\n", tool.Name, strings.ReplaceAll(tool.Description, "\n", "\n  "), tool.Input)
		}
		return nil
	case "call":
		if len(args) < 2 {
			return errors.New("t3 call <tool> [json]")
		}
		var input any = map[string]any{}
		if len(args) > 2 {
			if err := json.Unmarshal([]byte(args[2]), &input); err != nil {
				return fmt.Errorf("arguments aren't JSON: %w", err)
			}
		}
		out, err := client.Call(ctx, args[1], input)
		if err != nil {
			return err
		}
		var pretty bytes.Buffer
		if json.Indent(&pretty, out, "", "  ") != nil {
			pretty.Write(out)
		}
		fmt.Println(pretty.String())
		return nil
	}
	return errors.New("t3 tools, or t3 call <tool> [json]")
}

func defaultGame() string {
	if dir := os.Getenv("WOW_DIR"); dir != "" {
		return dir
	}
	return `D:\BattleNet\World of Warcraft\_forever_`
}

func run(in wow.Install, data string) error {
	if !in.Load() {
		return errors.New("not installed, or installed by an older version: run `forever-agent install`")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	// The game learns the signals' names only when it starts, so they must all exist then: arm
	// them now if it isn't running, and again each time it closes.
	running := wow.GameRunning(in.Game)
	if !running {
		arm(in)
	} else {
		log.Println("The game is running. The signals are armed when it closes.")
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

	// Everything that touches the bridge runs here, one thing at a time: the game's messages,
	// and a check of T3 every second while the window is open.
	b := bridge.New(in, data, version)
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		select {
		case err := <-done:
			return err
		case m := <-messages:
			b.Handle(ctx, characterOf(m.File), m.Data)
		case <-tick.C:
			if b.Busy() {
				b.Poll(ctx, false)
			}
		}
	}
}

func arm(in wow.Install) {
	if err := in.Arm(); err != nil {
		log.Println("arming the signals:", err)
		return
	}
	log.Printf("Armed %d signals for the next game start.", in.Signals)
}

// characterOf is "Realm/Character" from a path ending in Account\<acct>\<realm>\<char>\AddOns.txt.
func characterOf(path string) string {
	dir := filepath.Dir(path)
	return filepath.Base(filepath.Dir(dir)) + "/" + filepath.Base(dir)
}
