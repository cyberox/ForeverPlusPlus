// Forever Agent: the program on the PC that Forever++'s Agent Chat talks to. It reads what the
// game writes through its AddOns.txt, asks T3 Code, and writes the answers into reply slots the
// game loads. See agent/README.md.
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
	"runtime/debug"
	"strings"
	"sync/atomic"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/background"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/bridge"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/link"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/t3"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/wow"
)

const usage = `Usage: forever-agent <command> [flags]

Commands:
  install     make the helper addons and link them into the game (restart the game after)
  uninstall   remove the links and the helper addons
  run         answer the game, in this window
  start       answer the game in the background, with no window (its log: agent.log)
  stop        stop the copy running in the background
  status      say whether it runs, and whether it starts at sign-in
  startup on|off   start it in the background when you sign in to Windows
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
	quiet := flags.Bool("background", false, "run with no window, logging to agent.log (what start does)")
	after := flags.Int("after", 0, "wait for this process to end first (an update taking over)")
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
		err = run(in, *data, *quiet, *after)
	case "start":
		err = start()
	case "stop":
		err = background.Stop(15 * time.Second)
		if err == nil {
			fmt.Println("Stopped.")
		}
	case "status":
		status(*data)
	case "startup":
		err = startup(flags.Args())
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

const version = "0.2.0"

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

// start runs the program again in the background, with no window, and returns.
func start() error {
	if background.Running() {
		return background.ErrRunning
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := background.Spawn(exe, append([]string{"run", "-background"}, passedFlags()...), true); err != nil {
		return err
	}
	for end := time.Now().Add(5 * time.Second); time.Now().Before(end); time.Sleep(100 * time.Millisecond) {
		if background.Running() {
			fmt.Println("Running in the background. forever-agent stop ends it.")
			return nil
		}
	}
	return errors.New("it didn't start; see agent.log in " + wow.DefaultData())
}

func status(data string) {
	if background.Running() {
		fmt.Println("Running.")
	} else {
		fmt.Println("Not running.")
	}
	if on, exe := background.Startup(); on {
		fmt.Println("Starts when you sign in to Windows, from " + exe)
	} else {
		fmt.Println("Doesn't start at sign-in (forever-agent startup on).")
	}
	fmt.Println("Log: " + logPath(data))
}

func startup(args []string) error {
	if len(args) != 1 || (args[0] != "on" && args[0] != "off") {
		return errors.New("startup on, or startup off")
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := background.SetStartup(args[0] == "on", exe); err != nil {
		return err
	}
	if args[0] == "on" {
		fmt.Println("It starts in the background when you sign in to Windows, from " + exe)
	} else {
		fmt.Println("It no longer starts at sign-in.")
	}
	return nil
}

// passedFlags is the flags this copy was started with (not -background or -after), for the copy
// that takes over after an update.
func passedFlags() []string {
	var out []string
	args := os.Args[2:]
	for i := 0; i < len(args); i++ {
		a := strings.TrimLeft(args[i], "-")
		name := strings.SplitN(a, "=", 2)[0]
		switch {
		case name == "background":
		case name == "after":
			if !strings.Contains(a, "=") {
				i++ // its value
			}
		default:
			out = append(out, args[i])
		}
	}
	return out
}

func logPath(data string) string { return filepath.Join(data, "agent.log") }

// logToFile sends the log to agent.log, starting it afresh past a few megabytes (the last one kept
// as agent.old.log).
func logToFile(data string) (*os.File, error) {
	path := logPath(data)
	if info, err := os.Stat(path); err == nil && info.Size() > 4<<20 {
		os.Rename(path, filepath.Join(data, "agent.old.log"))
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, err
	}
	log.SetOutput(f)
	// A crash would print to a console nobody sees; it goes in the log instead.
	debug.SetCrashOutput(f, debug.CrashOptions{})
	return f, nil
}

// watchForUpdate calls update once the program file is replaced (go build writes a new one where
// it was) and the new one has stopped changing.
func watchForUpdate(ctx context.Context, exe string, update func()) {
	first, err := os.Stat(exe)
	if err != nil {
		return
	}
	var last os.FileInfo
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		info, err := os.Stat(exe)
		if err != nil || (info.ModTime().Equal(first.ModTime()) && info.Size() == first.Size()) {
			last = nil
			continue
		}
		// Changed: wait for two looks the same, so a build still writing it isn't started.
		if last != nil && info.ModTime().Equal(last.ModTime()) && info.Size() == last.Size() {
			update()
			return
		}
		last = info
	}
}

func run(in wow.Install, data string, quiet bool, after int) error {
	if quiet {
		f, err := logToFile(data)
		if err != nil {
			return err
		}
		defer f.Close()
	}
	if !in.Load() {
		return errors.New("not installed, or installed by an older version: run `forever-agent install`")
	}
	if after > 0 {
		background.WaitForExit(after, 15*time.Second) // the copy this update replaces
	}
	lock, err := background.Acquire()
	if err != nil {
		return err
	}
	defer lock.Release()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	go func() {
		select {
		case <-lock.Stopped():
			log.Println("Asked to stop.")
			stop()
		case <-ctx.Done():
		}
	}()

	// A new build of the program file takes over: it starts once this copy has gone, and picks up
	// the game's session as it is, as when the program starts after the game.
	var updated atomic.Bool
	if exe, err := os.Executable(); err == nil {
		go watchForUpdate(ctx, exe, func() {
			args := append([]string{"run", "-after", fmt.Sprint(os.Getpid())}, passedFlags()...)
			if quiet {
				args = append(args, "-background")
			}
			if err := background.Spawn(exe, args, quiet); err != nil {
				log.Println("starting the new build:", err)
				return
			}
			log.Println("A new build is in place; it takes over now.")
			updated.Store(true)
			stop()
		})
	}
	defer func() {
		if !updated.Load() {
			log.Println("Stopped.")
		}
	}()

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
	if quiet {
		log.Printf("Watching %s in the background (version %s).", filepath.Join(in.Game, "WTF"), version)
	} else {
		log.Printf("Watching %s (version %s). Ctrl+C to stop.", filepath.Join(in.Game, "WTF"), version)
	}

	// Everything that touches the bridge runs here, one thing at a time: the game's messages,
	// and a check of T3 every second while the window is open.
	b := bridge.New(in, data, version)
	if after > 0 && b.Resume() {
		log.Println("Carried on with the game's session from the copy before.")
	}
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			if updated.Load() {
				if err := b.SaveHandoff(); err != nil {
					log.Println("handing over to the new build:", err)
				}
			}
			return nil
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
