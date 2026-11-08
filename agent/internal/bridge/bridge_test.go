package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/xIGBClutchIx/ForeverPlusPlus/agent/internal/wow"
)

// fakeT3 answers the two calls the bridge makes, from a thread it can change.
type fakeT3 struct {
	status string
	items  []map[string]any
	calls  []string
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
		for _, it := range f.items {
			if it["position"].(int) > after {
				out = append(out, it)
			}
		}
		return json.Marshal(map[string]any{"hasMore": false, "items": out})
	}
	return nil, fmt.Errorf("unexpected %s", name)
}

func msg(pos int, kind, text, status string) map[string]any {
	return map[string]any{"position": pos, "type": kind, "text": text, "status": status}
}

func setup(t *testing.T) (*Bridge, *fakeT3, func(slot int) string) {
	MinGap = 0
	t.Cleanup(func() { MinGap = 2 * time.Second })
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

func TestPingWithoutWindow(t *testing.T) {
	b, fake, read := setup(t)
	ctx := context.Background()
	b.Handle(ctx, "c", []byte("H|s1"))
	b.Handle(ctx, "c", []byte("O|s1|0|0"))
	b.Handle(ctx, "c", []byte("P|s1|7|hello|there"))
	if !strings.Contains(read(0), `text="hello|there"`) || !strings.Contains(read(0), `id="7"`) {
		t.Fatalf("no pong:\n%s", read(0))
	}
	if len(fake.calls) != 0 {
		t.Errorf("asked T3 with the window closed: %v", fake.calls)
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
