// Package bridge answers Agent Chat: it keeps what each UI session has been sent, reads T3 Code
// for what changed, and fills the inbox the game offers when there's something new.
//
// The game always keeps one inbox open (a reply slot and a signal) and the program fills it only
// with news, so a slot is spent only when something changed. Messages from the game:
//
//	H|session                  a UI session starts: forget what was sent, clear slots and signals
//	O|session|slot|signal      an inbox to fill (signal -1: none left; the game loads it in a second)
//	V|session|handle|open      the thread shown (0 for none) and whether the window is open
//	P|session|id|text          a ping, answered in the next inbox
//
// Threads go to the game with a small handle, so the game's messages stay short; handles last as
// long as the program runs.
package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/t3"
	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/wow"
)

const (
	listLimit    = 40   // threads in the list
	firstItems   = 40   // a thread's latest messages sent when it's first opened in a session
	maxChars     = 8000 // characters of a message; longer ones are cut, with a note
	readPage     = 100
	maxPages     = 60 // pages read at once when a thread is first opened
	projectEvery = time.Minute
)

// MinGap is the least time between two updates the player didn't ask for.
var MinGap = 2 * time.Second

// Bridge is the program's side of Agent Chat.
type Bridge struct {
	In      wow.Install
	Data    string // where the T3 sign-in is saved
	Version string
	Log     func(format string, args ...any)

	// Dial connects to T3; by default with the saved sign-in. Tests give a fake.
	Dial   func(ctx context.Context) (Caller, error)
	client Caller

	// Attachments is the folder T3 Code keeps what's pasted into a message in, "" for none.
	Attachments string

	session string
	inbox   *inbox
	view    int  // handle of the thread shown, 0 for none
	open    bool // whether the window is open

	handles map[string]int // thread id -> handle
	ids     []string       // handle-1 -> thread id

	sentList    string                    // the list as last sent this session
	delivered   map[string]map[int]string // thread id -> position -> version sent this session
	pongs       []map[string]any
	acks        []map[string]any  // how the player's sends, steers, and stops went
	sentQueue   map[string]string // thread id -> its queue as last sent this session
	queued      []queued          // q-1 -> a queued message, for the program's life
	note        string            // what the game should show about the link, when it changes
	sentNote    string
	urgent      bool              // the next fill answers the player, so it doesn't wait for MinGap
	lastFill    time.Time         // when an inbox was last filled
	statuses    map[string]string // thread id -> its state at the last read, for notices
	closedCheck time.Time         // when the states were last read with the window closed

	threads      map[string]*thread // what's been read of each thread, for the program's life
	projects     map[string]string  // project id -> title
	projectsRead time.Time
}

// Caller is what the bridge needs of a T3 connection.
type Caller interface {
	Call(ctx context.Context, name string, args any) (json.RawMessage, error)
	Close() error
}

type inbox struct{ slot, signal int }

type item struct {
	Pos       int
	Role      string
	Text      string
	Status    string
	Truncated bool
	Time      time.Time
	Images    int // attached to it, as attachments() matched them
	Files     int
}

type thread struct {
	items  map[int]*item
	order  []int  // positions, oldest first
	read   bool   // read to the end at least once
	active string // the running turn's id, for steering into; "" when idle
}

// New returns a Bridge for an install.
func New(in wow.Install, data, version string) *Bridge {
	attachments := ""
	if home, err := os.UserHomeDir(); err == nil {
		attachments = filepath.Join(home, ".t3", "userdata", "attachments")
	}
	return &Bridge{
		In: in, Data: data, Version: version, Log: log.Printf, Attachments: attachments,
		handles: map[string]int{}, delivered: map[string]map[int]string{},
		threads: map[string]*thread{}, projects: map[string]string{},
	}
}

// Busy says whether the bridge should check T3 on its own, every second or so: the window is
// open, or a ping or note waits.
func (b *Bridge) Busy() bool {
	return b.inbox != nil // closed, Poll reads only the states, every ClosedEvery
}

// ClosedEvery is how often the threads' states are read while the window is closed, for notices.
var ClosedEvery = 5 * time.Second

// working is a thread state where its agent is busy.
var working = map[string]bool{"running": true, "starting": true, "preparing": true, "queued": true}

// statusEvents compares the threads' states with the last read, and returns a notice for each
// that finished, failed, or now waits for the player; not for the thread the player is reading.
// The first read only learns where things stand.
func (b *Bridge) statusEvents(list []map[string]any) []map[string]any {
	first := b.statuses == nil
	if first {
		b.statuses = map[string]string{}
	}
	var events []map[string]any
	for _, t := range list {
		id, _ := t["id"].(string)
		status, _ := t["status"].(string)
		before, seen := b.statuses[id]
		b.statuses[id] = status
		if first || !seen || before == status || (b.open && t["h"] == b.view) {
			continue
		}
		kind := ""
		switch {
		case status == "waiting":
			kind = "waiting"
		case status == "failed" && working[before]:
			kind = "failed"
		case working[before] && !working[status]:
			kind = "done"
		}
		if kind != "" {
			events = append(events, map[string]any{"id": id, "title": t["title"], "kind": kind})
		}
	}
	return events
}

// Handle takes one message from the game, then answers what it can.
func (b *Bridge) Handle(ctx context.Context, char string, data []byte) {
	parts := strings.SplitN(string(data), "|", 5)
	if len(parts) < 2 {
		b.Log("%s: unknown message %q", char, data)
		return
	}
	kind, session := parts[0], parts[1]
	if kind == "H" {
		b.start(session, true)
		b.Log("%s: session %s started; %d slots and %d signals cleared", char, session, b.In.Slots, b.In.Signals)
		return
	}
	if session != b.session {
		// The program started after the game did: go on with its session, without clearing
		// the slots and signals it's using.
		b.start(session, false)
	}
	switch {
	case kind == "O" && len(parts) >= 4:
		slot, err1 := strconv.Atoi(parts[2])
		signal, err2 := strconv.Atoi(parts[3])
		if err1 != nil || err2 != nil || slot < 0 || slot >= b.In.Slots || signal >= b.In.Signals {
			break
		}
		b.inbox = &inbox{slot, signal}
		if signal < 0 {
			b.Poll(ctx, true) // it loads in a second whatever is there
		} else {
			b.Poll(ctx, false)
		}
		return
	case kind == "V" && len(parts) >= 4:
		b.view, _ = strconv.Atoi(parts[2])
		b.open = parts[3] == "1"
		b.urgent = true // the player is waiting on this one
		b.Poll(ctx, false)
		return
	case kind == "P" && len(parts) >= 3:
		text := strings.Join(parts[3:], "|") // the text may hold | itself
		b.pongs = append(b.pongs, map[string]any{"id": parts[2], "text": text})
		b.Log("%s: ping %s %q", char, parts[2], text)
		b.urgent = true
		b.Poll(ctx, false)
		return
	}
	if b.act(ctx, char, kind, parts) {
		return
	}
	b.Log("%s: unknown message %q", char, data)
}

func (b *Bridge) start(session string, clear bool) {
	b.session, b.inbox, b.view, b.open = session, nil, 0, false
	b.sentList, b.sentNote = "", ""
	b.delivered = map[string]map[int]string{}
	b.sentQueue = map[string]string{}
	b.pongs, b.acks = nil, nil
	// Signals the game hasn't found yet should read as missing; ones it has found read as there
	// to it anyway, so clearing is safe even mid-session. Slots are cleared only at a hello: one
	// filled but not yet loaded would be lost.
	if err := wow.ClearSignals(b.In.SignalsDir(), b.In.Signals); err != nil {
		b.Log("clearing the signals: %v", err)
	}
	if !clear {
		return
	}
	for i := 0; i < b.In.Slots; i++ {
		if err := wow.ClearSlot(b.In.SlotDir(i)); err != nil {
			b.Log("clearing slot %d: %v", i, err)
		}
	}
}

// Poll reads T3 for what the game hasn't been sent, and fills the inbox if anything is new (or
// always, with force).
func (b *Bridge) Poll(ctx context.Context, force bool) {
	if b.inbox == nil {
		return
	}
	// Each fill spends one of the game's slots, so updates (a running thread's) go at most every
	// MinGap; what the player just asked for goes at once.
	if !force && !b.urgent && time.Since(b.lastFill) < MinGap {
		return
	}
	payload := map[string]any{"session": b.session}
	news := false
	var listSig string
	var sentItems map[int]string
	var queueSig string
	var threadID string

	// With the window closed, only the threads' states are read, now and then, for notices.
	if !b.open && time.Since(b.closedCheck) >= ClosedEvery {
		b.closedCheck = time.Now()
		if b.connect(ctx) == nil {
			if list, _, err := b.list(ctx); err != nil {
				b.fail(err)
			} else if events := b.statusEvents(list); len(events) > 0 {
				payload["events"], news = events, true
			}
		}
	}
	if b.open {
		if err := b.connect(ctx); err != nil {
			b.note = err.Error()
		} else if list, sig, err := b.list(ctx); err != nil {
			b.fail(err)
		} else {
			b.note = ""
			if events := b.statusEvents(list); len(events) > 0 {
				payload["events"], news = events, true
			}
			if sig != b.sentList {
				payload["threads"], listSig, news = list, sig, true
			}
			if b.view > 0 && b.view <= len(b.ids) {
				threadID = b.ids[b.view-1]
				items, older, versions, err := b.threadNews(ctx, threadID)
				if err != nil {
					b.fail(err)
				} else if len(items) > 0 {
					payload["thread"] = map[string]any{"id": threadID, "h": b.view, "items": items, "older": older}
					sentItems, news = versions, true
				}
				if queue, sig, err := b.queueNews(ctx, threadID); err != nil {
					b.Log("T3 queue: %v", err) // the conversation still shows without it
				} else if sig != b.sentQueue[threadID] {
					payload["queue"], queueSig, news = queue, sig, true
				}
			}
		}
	}
	if len(b.pongs) > 0 {
		payload["pongs"], news = b.pongs, true
	}
	if len(b.acks) > 0 {
		payload["acks"], news = b.acks, true
	}
	if b.note != b.sentNote {
		payload["note"], news = b.note, true
	}
	if !news && !force {
		return
	}

	start := time.Now()
	if err := wow.FillSlot(b.In.SlotDir(b.inbox.slot), payload); err != nil {
		b.Log("writing slot %d: %v", b.inbox.slot, err)
		return
	}
	if b.inbox.signal >= 0 {
		if err := wow.MakeSignal(b.In.SignalsDir(), b.inbox.signal); err != nil {
			b.Log("making signal %d: %v", b.inbox.signal, err)
			return
		}
	}
	// Sent: remember it.
	if listSig != "" {
		b.sentList = listSig
	}
	if sentItems != nil {
		seen := b.delivered[threadID]
		if seen == nil {
			seen = map[int]string{}
			b.delivered[threadID] = seen
		}
		for pos, v := range sentItems {
			seen[pos] = v
		}
	}
	b.sentNote = b.note
	if queueSig != "" {
		b.sentQueue[threadID] = queueSig
	}
	b.acks = nil
	what := []string{}
	for _, k := range []string{"threads", "thread", "queue", "events", "pongs", "acks", "note"} {
		if _, ok := payload[k]; ok {
			what = append(what, k)
		}
	}
	b.Log("-> slot %d, signal %d: %s (%s)", b.inbox.slot, b.inbox.signal, strings.Join(what, ", "),
		time.Since(start).Round(time.Microsecond))
	b.pongs = nil
	b.inbox = nil
	b.urgent = false
	b.lastFill = time.Now()
}

// fail notes an error from T3; a sign-in problem drops the connection so the next poll retries.
func (b *Bridge) fail(err error) {
	b.Log("T3: %v", err)
	if errors.Is(err, t3.ErrSignIn) || strings.Contains(err.Error(), "401") {
		b.note = t3.ErrSignIn.Error()
		if b.client != nil {
			b.client.Close()
			b.client = nil
		}
		return
	}
	b.note = "T3 Code: " + err.Error()
	if b.client != nil {
		b.client.Close()
		b.client = nil
	}
}

func (b *Bridge) connect(ctx context.Context) error {
	if b.client != nil {
		return nil
	}
	dial := b.Dial
	if dial == nil {
		dial = func(ctx context.Context) (Caller, error) {
			tok, err := t3.LoadToken(b.Data)
			if err != nil {
				return nil, t3.ErrSignIn
			}
			return t3.Connect(ctx, tok, b.Version)
		}
	}
	client, err := dial(ctx)
	if err != nil {
		if errors.Is(err, t3.ErrSignIn) {
			return err
		}
		return fmt.Errorf("can't reach T3 Code (is it running?)")
	}
	b.client = client
	return nil
}

func (b *Bridge) handle(id string) int {
	if h, ok := b.handles[id]; ok {
		return h
	}
	b.ids = append(b.ids, id)
	b.handles[id] = len(b.ids)
	return len(b.ids)
}

// list reads the thread list for the game, and a signature of what it shows.
func (b *Bridge) list(ctx context.Context) ([]map[string]any, string, error) {
	if time.Since(b.projectsRead) > projectEvery {
		var res struct {
			Projects []struct {
				ID    string `json:"id"`
				Title string `json:"title"`
			} `json:"projects"`
		}
		if raw, err := b.client.Call(ctx, "t3_project_list", map[string]any{}); err == nil && json.Unmarshal(raw, &res) == nil {
			for _, p := range res.Projects {
				b.projects[p.ID] = p.Title
			}
			b.projectsRead = time.Now()
		}
	}
	raw, err := b.client.Call(ctx, "t3_thread_list", map[string]any{
		"allProjects": true, "includeSubagents": false, "limit": listLimit,
	})
	if err != nil {
		return nil, "", err
	}
	var res struct {
		Threads []struct {
			ThreadID  string `json:"threadId"`
			Title     string `json:"title"`
			Status    string `json:"status"`
			Model     string `json:"model"`
			ProjectID string `json:"projectId"`
			UpdatedAt string `json:"updatedAt"`
			Settled   bool   `json:"settled"`
		} `json:"threads"`
	}
	if err := json.Unmarshal(raw, &res); err != nil {
		return nil, "", err
	}
	list := make([]map[string]any, 0, len(res.Threads))
	sig := fnv.New64a()
	for _, t := range res.Threads {
		updated := int64(0)
		if at, err := time.Parse(time.RFC3339Nano, t.UpdatedAt); err == nil {
			updated = at.Unix()
		}
		entry := map[string]any{
			"h": b.handle(t.ThreadID), "id": t.ThreadID, "title": t.Title, "status": t.Status,
			"model": t.Model, "project": b.projects[t.ProjectID], "updated": updated, "settled": t.Settled,
		}
		list = append(list, entry)
		// The list goes again when what it shows changes; a running thread's updatedAt ticks
		// constantly, so only to the minute.
		fmt.Fprintf(sig, "%s|%s|%s|%s|%v|%d\n", t.ThreadID, t.Title, t.Status, t.Model, t.Settled, updated/60)
	}
	return list, fmt.Sprint(sig.Sum64()), nil
}

// threadNews reads what's new in a thread and returns the messages the game hasn't been sent in
// their latest form, how many older ones it won't get, and the versions sent.
func (b *Bridge) threadNews(ctx context.Context, id string) ([]map[string]any, int, map[int]string, error) {
	t := b.threads[id]
	if t == nil {
		t = &thread{items: map[int]*item{}}
		b.threads[id] = t
	}
	// Read on from the second to last message, so the last comes again while it's still growing.
	after := -1
	if n := len(t.order); n >= 2 {
		after = t.order[n-2]
	}
	for page := 0; page < maxPages; page++ {
		args := map[string]any{"threadId": id, "view": "messages", "limit": readPage, "maxCharsPerItem": maxChars}
		if after >= 0 {
			args["afterPosition"] = after
		}
		raw, err := b.client.Call(ctx, "t3_thread_read", args)
		if err != nil {
			return nil, 0, nil, err
		}
		var res struct {
			HasMore      bool `json:"hasMore"`
			NextPosition *int `json:"nextPosition"`
			Items        []struct {
				Position      int       `json:"position"`
				Type          string    `json:"type"`
				Text          string    `json:"text"`
				Status        string    `json:"status"`
				TextTruncated bool      `json:"textTruncated"`
				UpdatedAt     time.Time `json:"updatedAt"`
			} `json:"items"`
			Thread *struct {
				ActiveRunID *string `json:"activeRunId"`
			} `json:"thread"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return nil, 0, nil, err
		}
		if res.Thread != nil {
			t.active = ""
			if res.Thread.ActiveRunID != nil {
				t.active = *res.Thread.ActiveRunID
			}
		}
		for _, it := range res.Items {
			if _, ok := t.items[it.Position]; !ok {
				t.order = append(t.order, it.Position)
			}
			t.items[it.Position] = &item{Pos: it.Position, Role: role(it.Type), Text: it.Text,
				Status: it.Status, Truncated: it.TextTruncated, Time: it.UpdatedAt}
		}
		if !res.HasMore || res.NextPosition == nil || len(res.Items) == 0 {
			break
		}
		after = *res.NextPosition
	}
	t.read = true
	b.attachments(id, t)

	seen := b.delivered[id]
	start := 0
	if seen == nil && len(t.order) > firstItems {
		start = len(t.order) - firstItems
	}
	var out []map[string]any
	versions := map[int]string{}
	for _, pos := range t.order[start:] {
		it := t.items[pos]
		v := fmt.Sprintf("%s|%d|%v|%d|%d", it.Status, len(it.Text), it.Truncated, it.Images, it.Files)
		if seen != nil && seen[pos] == v {
			continue
		}
		out = append(out, map[string]any{"pos": it.Pos, "role": it.Role, "text": it.Text,
			"status": it.Status, "cut": it.Truncated, "images": it.Images, "files": it.Files})
		versions[pos] = v
	}
	older := 0
	if seen == nil {
		older = start
	}
	return out, older, versions, nil
}

// attachWindow is how long before a message what's pasted into it can be saved.
const attachWindow = 10 * time.Minute

var imageExt = map[string]bool{".png": true, ".jpg": true, ".jpeg": true, ".gif": true, ".webp": true}

// attachments counts what's attached to each of the player's messages. T3's MCP tools don't say,
// but T3 saves each attachment as <thread id>-<attachment id>.<ext> in its attachments folder the
// moment it's pasted, a few seconds before the message is sent: so each file goes to the first of
// the player's messages sent after it, within attachWindow. Nothing when T3 runs on another
// machine.
func (b *Bridge) attachments(id string, t *thread) {
	var users []*item
	for _, pos := range t.order {
		if it := t.items[pos]; it.Role == "user" && !it.Time.IsZero() {
			it.Images, it.Files = 0, 0
			users = append(users, it)
		}
	}
	if b.Attachments == "" || len(users) == 0 {
		return
	}
	files, _ := filepath.Glob(filepath.Join(b.Attachments, id+"-*"))
	sort.Slice(users, func(i, j int) bool { return users[i].Time.Before(users[j].Time) })
	for _, f := range files {
		info, err := os.Stat(f)
		if err != nil || info.IsDir() {
			continue
		}
		saved := info.ModTime()
		n := sort.Search(len(users), func(i int) bool { return !users[i].Time.Before(saved) })
		if n == len(users) || users[n].Time.Sub(saved) > attachWindow {
			continue
		}
		if imageExt[strings.ToLower(filepath.Ext(f))] {
			users[n].Images++
		} else {
			users[n].Files++
		}
	}
}

func role(kind string) string {
	switch kind {
	case "user_message":
		return "user"
	case "assistant_message":
		return "assistant"
	}
	return strings.TrimSuffix(kind, "_message")
}
