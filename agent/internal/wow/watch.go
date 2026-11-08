package wow

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/link"
)

// Message is one message from the game, with the character file it came through.
type Message struct {
	File string
	Data []byte
	At   time.Time // when its last frame was read
}

// Watch follows every character's AddOns.txt under the game's WTF folder and sends each message
// the game writes. A file event reads the file at once; a slower poll catches anything the
// events miss, and picks up characters made while it runs. warn reports frames that were lost.
func Watch(ctx context.Context, game string, out chan<- Message, warn func(string)) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer watcher.Close()

	type state struct {
		reader  *link.Reader
		modTime time.Time
		size    int64
	}
	files := map[string]*state{}
	watched := map[string]bool{}

	read := func(path string) {
		s := files[path]
		info, err := os.Stat(path)
		if err != nil {
			return
		}
		if s == nil {
			s = &state{reader: link.NewReader()}
			files[path] = s
		} else if info.ModTime().Equal(s.modTime) && info.Size() == s.size {
			return
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return
		}
		frame, ok := link.FrameFromAddOns(data)
		if !ok {
			return // half written, or no helpers here: read again on the next event or poll
		}
		s.modTime, s.size = info.ModTime(), info.Size()
		msg, done, dropped := s.reader.Read(frame)
		if dropped {
			warn("a frame was missed in " + path + "; that message is lost")
		}
		if done {
			out <- Message{File: path, Data: msg, At: time.Now()}
		}
	}

	scan := func() {
		matches, _ := filepath.Glob(filepath.Join(game, "WTF", "Account", "*", "*", "*", "AddOns.txt"))
		for _, path := range matches {
			dir := filepath.Dir(path)
			if !watched[dir] {
				if watcher.Add(dir) == nil {
					watched[dir] = true
				}
			}
			read(path)
		}
	}

	scan()
	poll := time.NewTicker(250 * time.Millisecond)
	defer poll.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev, ok := <-watcher.Events:
			if !ok {
				return nil
			}
			if strings.EqualFold(filepath.Base(ev.Name), "AddOns.txt") && ev.Op&(fsnotify.Write|fsnotify.Create) != 0 {
				read(ev.Name)
			}
		case err, ok := <-watcher.Errors:
			if ok && err != nil {
				warn("watching: " + err.Error())
			}
		case <-poll.C:
			scan()
		}
	}
}
