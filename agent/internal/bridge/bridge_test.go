package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/wow"
)

// fakeT3 answers the two calls the bridge makes, from a thread it can change.
type fakeT3 struct {
	status   string
	active   string // the running turn
	items    []map[string]any
	queue    []map[string]any
	calls    []string
	sent     []map[string]any // what t3_thread_send, t3_queue writes, and t3_thread_interrupt got
	reject   string           // when set, t3_thread_send fails with it
	pending  int              // the thread's pendingRequestCount
	requests []string         // question requests waiting
	activity []map[string]any // what the activity view has besides the messages
}

func (f *fakeT3) Close() error { return nil }

func (f *fakeT3) Call(_ context.Context, name string, args any) (json.RawMessage, error) {
	f.calls = append(f.calls, name)
	switch name {
	case "t3_project_list":
		return json.RawMessage(`{"projects":[{"id":"p1","title":"ForeverPlusPlus"}]}`), nil
	case "t3_thread_list":
		return json.Marshal(map[string]any{"threads": []map[string]any{{
			"threadId": "t1", "title": "Agent Chat", "status": f.status, "model": "claude-opus-5-5",
			"projectId": "p1", "updatedAt": "2026-11-07T22:00:00Z",
		}}})
	case "t3_thread_read":
		after := -1
		if v, ok := args.(map[string]any)["afterPosition"]; ok {
			after = v.(int)
		}
		var out []map[string]any
		all := f.items
		if args.(map[string]any)["view"] == "activity" {
			all = append(append([]map[string]any{}, f.items...), f.activity...)
			sort.Slice(all, func(i, j int) bool { return all[i]["position"].(int) < all[j]["position"].(int) })
		}
		for _, it := range all {
			if it["position"].(int) > after {
				out = append(out, it)
			}
		}
		var active any
		if f.active != "" {
			active = f.active
		}
		return json.Marshal(map[string]any{"hasMore": false, "items": out,
			"thread":     map[string]any{"activeRunId": active, "pendingRequestCount": f.pending},
			"recentRuns": []map[string]any{{"runId": f.active, "startedAt": "2026-11-08T16:00:00Z"}}})
	case "t3_pending_request":
		a := args.(map[string]any)
		switch a["action"] {
		case "list":
			return json.Marshal(map[string]any{"requestIds": f.requests})
		case "read":
			return json.RawMessage(`{"requestId":"r1","questions":[
				{"id":"Which color?","header":"Color","question":"Which color?","multiSelect":false,
				 "options":[{"label":"Red","description":"warm"},{"label":"Blue","description":"cool"}]},
				{"id":"Which sizes?","header":"Sizes","question":"Which sizes?","multiSelect":true,
				 "options":[{"label":"Small"},{"label":"Medium"},{"label":"Large"}]}]}`), nil
		}
		f.sent = append(f.sent, a)
		return json.RawMessage(`{"sequence":1}`), nil
	case "t3_queue":
		a := args.(map[string]any)
		if a["action"] == "list" {
			return json.Marshal(map[string]any{"items": f.queue})
		}
		f.sent = append(f.sent, a)
		return json.RawMessage(`{}`), nil
	case "t3_thread_send":
		if f.reject != "" {
			return nil, fmt.Errorf("%s", f.reject)
		}
		f.sent = append(f.sent, args.(map[string]any))
		return json.RawMessage(`{}`), nil
	case "orchestrator_capabilities":
		return json.RawMessage(`{"providers":[
			{"displayName":"Claude Direct","providerInstanceId":"claudeAgent","constraints":[],
			 "models":[{"id":"claude-opus-5-5","label":"Claude Opus 5.5"}]},
			{"displayName":"Off API","providerInstanceId":"off","constraints":["Provider instance is disabled."],
			 "models":[{"id":"x"}]}]}`), nil
	case "t3_thread_launch":
		f.sent = append(f.sent, args.(map[string]any))
		return json.RawMessage(`{"threadId":"t9","status":"preparing"}`), nil
	case "t3_thread_update":
		f.sent = append(f.sent, args.(map[string]any))
		return json.RawMessage(`{}`), nil
	case "t3_thread_interrupt":
		f.sent = append(f.sent, args.(map[string]any))
		return json.RawMessage(`{}`), nil
	}
	return nil, fmt.Errorf("unexpected %s", name)
}

func msg(pos int, kind, text, status string) map[string]any {
	return map[string]any{"position": pos, "type": kind, "text": text, "status": status}
}

func setup(t *testing.T) (*Bridge, *fakeT3, func(slot int) string) {
	MinGap, GrowGap = 0, 0
	t.Cleanup(func() { MinGap, GrowGap = 2*time.Second, 5*time.Second })
	in := wow.Install{Game: t.TempDir(), Data: t.TempDir(), Slots: 4, Signals: 8, Interface: 16001}
	for i := 0; i < in.Slots; i++ {
		os.MkdirAll(in.SlotDir(i), 0o755)
	}
	os.MkdirAll(in.SignalsDir(), 0o755)
	fake := &fakeT3{status: "running", items: []map[string]any{
		msg(0, "user_message", "make it", "completed"),
		msg(3, "assistant_message", "On it", "running"),
	}}
	b := New(in, in.Data, "test")
	b.Log = t.Logf
	b.Dial = func(context.Context) (Caller, error) { return fake, nil }
	b.Attachments = t.TempDir()
	read := func(slot int) string {
		data, _ := os.ReadFile(filepath.Join(in.SlotDir(slot), "Data.lua"))
		return string(data)
	}
	return b, fake, read
}

func TestSendsOnlyNews(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	signal := func(i int) bool {
		_, err := os.Stat(filepath.Join(b.In.SignalsDir(), wow.SignalFile(i)))
		return err == nil
	}

	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|5"))
	if signal(5) {
		t.Fatal("filled with the window closed and nothing to say")
	}
	b.Handle(ctx, "c", []byte("V|s1|0|1")) // window opens, no thread shown
	if !signal(5) || !strings.Contains(read(0), `title="Agent Chat"`) || strings.Contains(read(0), "items=") {
		t.Fatalf("the list didn't come:\n%s", read(0))
	}

	b.Handle(ctx, "c", []byte("O|s1|1|6"))
	b.Poll(ctx, false)
	if signal(6) {
		t.Fatal("filled again with nothing new")
	}
	b.Handle(ctx, "c", []byte("V|s1|1|1")) // thread 1 shown
	if !signal(6) || !strings.Contains(read(1), `text="On it"`) || !strings.Contains(read(1), `text="make it"`) {
		t.Fatalf("the thread didn't come:\n%s", read(1))
	}

	// The running message grows, and a new one comes: only those two go.
	fake.items[1] = msg(3, "assistant_message", "On it, done", "completed")
	fake.items = append(fake.items, msg(5, "user_message", "thanks", "completed"))
	fake.status = "idle"
	b.Handle(ctx, "c", []byte("O|s1|2|7"))
	got := read(2)
	if !signal(7) || strings.Contains(got, "make it") || !strings.Contains(got, "On it, done") ||
		!strings.Contains(got, "thanks") || !strings.Contains(got, `status="idle"`) {
		t.Fatalf("expected only the news:\n%s", got)
	}
}

func TestUpdatesWaitButAnswersDont(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|1|1")) // asked for: goes at once
	if !strings.Contains(read(0), "On it") {
		t.Fatalf("the shown thread didn't come at once:\n%s", read(0))
	}
	MinGap = time.Hour
	fake.items = append(fake.items, msg(5, "assistant_message", "more", "completed"))
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Poll(ctx, false)
	if strings.Contains(read(1), "more") {
		t.Fatal("an update didn't wait for the gap")
	}
	b.Handle(ctx, "c", []byte("P|s1|1|hi")) // a ping is answered at once, with the update
	if !strings.Contains(read(1), "more") || !strings.Contains(read(1), `text="hi"`) {
		t.Fatalf("the ping waited:\n%s", read(1))
	}
}

func TestSendQueueSteerStop(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	fake.active = "run:1"
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))

	// A send queues, with any | in the text kept, and is acked.
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Handle(ctx, "c", []byte("M|s1|1|g7|use a | here"))
	if len(fake.sent) != 1 || fake.sent[0]["mode"] != "queue" || fake.sent[0]["message"] != "use a | here" ||
		fake.sent[0]["threadId"] != "t1" {
		t.Fatalf("sent %v", fake.sent)
	}
	if !strings.Contains(read(1), `id="g7"`) || !strings.Contains(read(1), "ok=true") {
		t.Fatalf("no ack:\n%s", read(1))
	}

	// The queue shows; steering takes it into the running turn.
	fake.queue = []map[string]any{{"queuedRunId": "run:2", "text": "use a | here"}}
	b.Handle(ctx, "c", []byte("O|s1|2|2"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))
	b.Poll(ctx, true)
	if !strings.Contains(read(2), "queue = {") || !strings.Contains(read(2), "q=1") || !strings.Contains(read(2), "active=true") {
		t.Fatalf("no queue:\n%s", read(2))
	}
	b.Handle(ctx, "c", []byte("O|s1|3|3"))
	b.Handle(ctx, "c", []byte("S|s1|1"))
	last := fake.sent[len(fake.sent)-1]
	if last["action"] != "promote_to_steer" || last["queuedRunId"] != "run:2" || last["targetRunId"] != "run:1" {
		t.Fatalf("steer sent %v", last)
	}

	// Stop interrupts; a refused send says why.
	b.Handle(ctx, "c", []byte("O|s1|0|4"))
	b.Handle(ctx, "c", []byte("X|s1|1"))
	if last = fake.sent[len(fake.sent)-1]; last["threadId"] != "t1" || last["action"] != nil {
		t.Fatalf("stop sent %v", last)
	}
	fake.reject = "the thread runs with more access than this sign-in"
	b.Handle(ctx, "c", []byte("O|s1|1|5"))
	b.Handle(ctx, "c", []byte("M|s1|1|g8|hi"))
	if got := read(1); !strings.Contains(got, `id="g8"`) || !strings.Contains(got, "ok=false") ||
		!strings.Contains(got, "more access") {
		t.Fatalf("no refusal:\n%s", got)
	}
}

func TestNotices(t *testing.T) {
	b, fake, read := setup(t)
	ClosedEvery = 0
	t.Cleanup(func() { ClosedEvery = 5 * time.Second })
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0")) // closed: learns the thread runs, nothing to say
	if strings.Contains(read(0), "events") {
		t.Fatalf("a notice from the first look:\n%s", read(0))
	}
	fake.status = "idle"
	b.Poll(ctx, false)
	if got := read(0); !strings.Contains(got, `kind="done"`) || !strings.Contains(got, `title="Agent Chat"`) ||
		strings.Contains(got, "threads =") {
		t.Fatalf("no done notice, or the list came with the window closed:\n%s", got)
	}

	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	fake.status = "waiting"
	b.Poll(ctx, false)
	if !strings.Contains(read(1), `kind="waiting"`) {
		t.Fatalf("no needs-you notice:\n%s", read(1))
	}

	// Reading the thread: no notice for it.
	b.Handle(ctx, "c", []byte("O|s1|2|2"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))
	b.Handle(ctx, "c", []byte("O|s1|3|3"))
	fake.status = "running"
	b.Poll(ctx, true)
	b.Handle(ctx, "c", []byte("O|s1|0|4"))
	fake.status = "completed"
	b.Poll(ctx, true)
	if strings.Contains(read(0), "events") {
		t.Fatalf("a notice for the thread being read:\n%s", read(0))
	}
}

func TestQuestionNeedsYou(t *testing.T) {
	b, fake, read := setup(t)
	ClosedEvery = 0
	t.Cleanup(func() { ClosedEvery = 5 * time.Second })
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0")) // closed: learns the thread runs
	fake.requests = []string{"r1"}         // T3 still calls it running
	b.Poll(ctx, false)
	if !strings.Contains(read(0), `kind="waiting"`) {
		t.Fatalf("no needs-you notice for a question:\n%s", read(0))
	}
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	fake.requests = nil // answered, and the turn goes on: none needs the player, which goes at once
	b.Poll(ctx, false)
	if !strings.Contains(read(1), "waiting=0") {
		t.Fatalf("the chat button's count didn't drop:\n%s", read(1))
	}
	b.Handle(ctx, "c", []byte("O|s1|2|2"))
	fake.status = "idle"
	b.Poll(ctx, false)
	if got := read(2); !strings.Contains(got, `kind="done"`) || strings.Contains(got, `kind="waiting"`) {
		t.Fatalf("no done notice after the answer:\n%s", got)
	}
}

func TestPingWithoutWindow(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("P|s1|7|hello|there"))
	if !strings.Contains(read(0), `text="hello|there"`) || !strings.Contains(read(0), `id="7"`) {
		t.Fatalf("no pong:\n%s", read(0))
	}
	for _, call := range fake.calls {
		if call == "t3_thread_read" || call == "t3_queue" {
			t.Errorf("read a thread with the window closed: %v", fake.calls)
		}
	}
}

func TestAttachments(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	sent := time.Date(2026, 11, 8, 15, 59, 16, 0, time.UTC)
	fake.items[0]["updatedAt"] = sent.Format(time.RFC3339Nano)
	file := func(name string, saved time.Time) {
		path := filepath.Join(b.Attachments, name)
		os.WriteFile(path, []byte("x"), 0o644)
		os.Chtimes(path, saved, saved)
	}
	file("t1-a.png", sent.Add(-7*time.Second))     // pasted just before: this message's
	file("t1-b-html.html", sent.Add(-time.Minute)) // pasted text
	file("t1-c.png", sent.Add(-time.Hour))         // too long before: an older message's
	file("t1-d.png", sent.Add(time.Second))        // after it: a later message's
	file("t2-e.png", sent.Add(-time.Second))       // another thread's

	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))
	if got := read(0); !strings.Contains(got, `files=1,final=false,images=1,pos=0`) ||
		!strings.Contains(got, `files=0,final=true,images=0,pos=3`) {
		t.Fatalf("attachments not counted:\n%s", got)
	}
}

func TestGrowthWaits(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))
	GrowGap = time.Hour
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	fake.items[1]["text"] = "On it, more" // the running message grows
	b.Poll(ctx, false)
	if strings.Contains(read(1), "more") {
		t.Fatal("a growing message didn't wait")
	}
	fake.items = append(fake.items, msg(5, "assistant_message", "a new one", "running"))
	b.Poll(ctx, false)
	if !strings.Contains(read(1), "a new one") || !strings.Contains(read(1), "On it, more") {
		t.Fatalf("a new message waited, or the growth didn't come with it:\n%s", read(1))
	}
}

func TestModelsAndNewThreadModel(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|0|1"))
	if got := read(0); !strings.Contains(got, `instance="claudeAgent"`) || !strings.Contains(got, `label="Claude Opus 5.5"`) ||
		strings.Contains(got, "Off API") {
		t.Fatalf("no models, or a turned-off provider's:\n%s", got)
	}
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Handle(ctx, "c", []byte("N|s1|g5|p1|claudeAgent|claude-opus-5-5|Hello | there"))
	var launch map[string]any
	for _, s := range fake.sent {
		if s["title"] != nil {
			launch = s
		}
	}
	sel, _ := launch["modelSelection"].(map[string]any)
	if launch["message"] != "Hello | there" || sel["instanceId"] != "claudeAgent" || sel["model"] != "claude-opus-5-5" {
		t.Fatalf("launched %v", launch)
	}
	b.Handle(ctx, "c", []byte("O|s1|2|2"))
	b.Handle(ctx, "c", []byte("N|s1|g6|p1|||T3 picks"))
	if last := fake.sent[len(fake.sent)-2]; last["modelSelection"] != nil || last["message"] != "T3 picks" {
		t.Fatalf("a model was picked when none was asked for: %v", last)
	}
}

func TestSteps(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	fake.activity = []map[string]any{
		{"position": 1, "type": "command_execution", "text": "$ go test ./...", "status": "running"},
		{"position": 2, "type": "reasoning", "title": "Thinking", "text": "hmm", "status": "completed"},
	}
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))
	got := read(0)
	if !strings.Contains(got, `kind="ran",pos=1,role="step",text="go test ./..."`) || strings.Contains(got, "pos=2") {
		t.Fatalf("no step, or thinking came as one:\n%s", got)
	}
	// The command fails, and a file is made: both go, nothing else again.
	fake.activity[0]["status"] = "failed"
	fake.activity = append(fake.activity, map[string]any{"position": 4, "type": "file_change",
		"text": "C:\\a\\new.go\n--- /dev/null", "status": "completed"})
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Poll(ctx, true)
	got = read(1)
	if !strings.Contains(got, `failed=true,kind="ran",pos=1`) || !strings.Contains(got, `kind="created",pos=4`) ||
		strings.Contains(got, "make it") {
		t.Fatalf("steps not updated:\n%s", got)
	}
}

func TestFinalAnswerAndStart(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	fake.active = "run:1"
	fake.items[1]["runId"] = "run:1"
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|1|1"))
	if got := read(0); !strings.Contains(got, `final=true,images=0,pos=3`) || !strings.Contains(got, "started=1794153600") {
		t.Fatalf("the only answer isn't final, or no start:\n%s", got)
	}
	// A later message in the same turn: the earlier one becomes a progress note.
	later := msg(5, "assistant_message", "done", "completed")
	later["runId"] = "run:1"
	fake.items = append(fake.items, later)
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Poll(ctx, true)
	if got := read(1); !strings.Contains(got, `final=false,images=0,pos=3`) || !strings.Contains(got, `final=true,images=0,pos=5`) {
		t.Fatalf("finals not moved:\n%s", got)
	}
}

func TestQuestions(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	fake.status, fake.pending, fake.requests = "waiting", 2, []string{"r1"} // a question and an approval
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0")) // closed: the chat button's count goes at once
	if !strings.Contains(read(0), "waiting=1") {
		t.Fatalf("no count for the chat button:\n%s", read(0))
	}
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Handle(ctx, "c", []byte("V|s1|1|1")) // the thread read says what's pending, so they come with it
	got := read(1)
	if !strings.Contains(got, "asks = {") || !strings.Contains(got, `header="Color"`) ||
		!strings.Contains(got, `label="Blue"`) || !strings.Contains(got, "multi=true") || !strings.Contains(got, "approvals=1") {
		t.Fatalf("no questions:\n%s", got)
	}

	// Blue, and Small and Large.
	b.Handle(ctx, "c", []byte("O|s1|2|2"))
	b.Handle(ctx, "c", []byte("A|s1|1|o:2\no:1,3"))
	last := fake.sent[len(fake.sent)-1]
	answers, _ := last["answers"].(map[string]any)
	sizes, _ := answers["Which sizes?"].([]string)
	if last["action"] != "respond" || last["requestId"] != "r1" || answers["Which color?"] != "Blue" ||
		len(sizes) != 2 || sizes[0] != "Small" || sizes[1] != "Large" {
		t.Fatalf("answered %v", last)
	}
	if !strings.Contains(read(2), "ask=1") || !strings.Contains(read(2), "ok=true") {
		t.Fatalf("no ack:\n%s", read(2))
	}

	// Their own words, with a | in them; and a short answer is turned back.
	b.Handle(ctx, "c", []byte("O|s1|3|3"))
	b.Handle(ctx, "c", []byte("A|s1|1|t:green | teal\nt:all"))
	answers, _ = fake.sent[len(fake.sent)-1]["answers"].(map[string]any)
	if answers["Which color?"] != "green | teal" {
		t.Fatalf("typed answer %v", answers)
	}
	b.Handle(ctx, "c", []byte("O|s1|0|4"))
	b.Handle(ctx, "c", []byte("A|s1|1|o:1"))
	if !strings.Contains(read(0), "ok=false") || !strings.Contains(read(0), "every question") {
		t.Fatalf("a short answer went through:\n%s", read(0))
	}
}

func TestNewThreadCountsProjects(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("V|s1|0|1"))
	if got := read(0); !strings.Contains(got, "counts = {waiting=0,working=1,}") ||
		!strings.Contains(got, `{id="p1",title="ForeverPlusPlus",}`) {
		t.Fatalf("no counts or projects:\n%s", got)
	}

	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Handle(ctx, "c", []byte("N|s1|g3|p1|||Make a | thing\nwith details"))
	var launch, rename map[string]any
	for _, s := range fake.sent {
		if s["message"] != nil {
			launch = s
		} else if s["action"] == "regenerate_title" {
			rename = s
		}
	}
	if launch == nil || launch["projectId"] != "p1" || launch["title"] != "Make a | thing" ||
		launch["message"] != "Make a | thing\nwith details" || rename == nil || rename["threadId"] != "t9" {
		t.Fatalf("launched %v, renamed %v", launch, rename)
	}
	got := read(1)
	if !strings.Contains(got, `id="g3"`) || !strings.Contains(got, `thread="t9"`) || !strings.Contains(got, "threads = {") {
		t.Fatalf("no ack, or the list didn't come again:\n%s", got)
	}

	b.Handle(ctx, "c", []byte("O|s1|2|2"))
	b.Handle(ctx, "c", []byte("N|s1|g4||||Scratch it"))
	if last := fake.sent[len(fake.sent)-2]; last["scratch"] != true || last["projectId"] != nil {
		t.Fatalf("no scratch folder: %v", last)
	}
}

func TestReloadWhenAddonChanges(t *testing.T) {
	b, _, read := setup(t)
	ReloadSettle = time.Second
	t.Cleanup(func() { ReloadSettle = 8 * time.Second })
	ctx := context.Background()
	dir := filepath.Join(b.In.Game, "Interface", "AddOns", "ForeverPlusPlus")
	os.MkdirAll(dir, 0o755)
	file := filepath.Join(dir, "Core.lua")
	os.WriteFile(file, []byte("-- loaded"), 0o644)
	os.Chtimes(file, time.Now().Add(-time.Hour), time.Now().Add(-time.Hour)) // from before the UI loaded

	b.Handle(ctx, "c", []byte("H|s1"))
	b.sessionStart = time.Now().Add(-time.Minute) // the UI loaded a minute ago
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	if strings.Contains(read(0), "reload") {
		t.Fatalf("asked to reload for what the UI already has:\n%s", read(0))
	}
	changed := time.Now().Add(-2 * time.Second) // edited, and settled since
	os.Chtimes(file, changed, changed)
	b.reloadCheck = time.Time{}
	b.Poll(ctx, false)
	if !strings.Contains(read(0), "reload = ") {
		t.Fatalf("no reload asked:\n%s", read(0))
	}
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.reloadCheck = time.Time{}
	b.Handle(ctx, "c", []byte("P|s1|1|x"))
	if strings.Contains(read(1), "reload") {
		t.Fatalf("asked twice for one change:\n%s", read(1))
	}
}

func TestSignInExpiry(t *testing.T) {
	b, _, read := setup(t)
	ctx := context.Background()
	b.expires = time.Date(2026, 12, 8, 16, 59, 0, 0, time.UTC)
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("P|s1|1|x"))
	if !strings.Contains(read(0), "expires = 1796749140") {
		t.Fatalf("no expiry:\n%s", read(0))
	}
	b.Handle(ctx, "c", []byte("O|s1|1|1"))
	b.Handle(ctx, "c", []byte("P|s1|2|y"))
	if strings.Contains(read(1), "expires") {
		t.Fatalf("the expiry went twice:\n%s", read(1))
	}
}

func TestProgramStartedLate(t *testing.T) {
	b, _, read := setup(t)
	ctx := context.Background()
	// No hello: the game's session is taken up as it is.
	b.Handle(ctx, "c", []byte("O|s9|2|1"))
	b.Handle(ctx, "c", []byte("P|s9|1|x"))
	if !strings.Contains(read(2), `session = "s9"`) || !strings.Contains(read(2), `text="x"`) {
		t.Fatalf("got:\n%s", read(2))
	}
}
