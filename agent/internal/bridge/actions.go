package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"strconv"
	"strings"
)

// What the player does from the game, and the shown thread's queue:
//
//	M|session|handle|id|text   send text to a thread, queued (T3's "queue" mode: an idle thread
//	                           starts a turn, a busy one runs it next); id is the game's, for the ack
//	S|session|q                steer queued message q into the running turn now
//	D|session|q                cancel queued message q
//	X|session|handle           stop the thread's running turn
//	A|session|a|answers        answer a question the agent asked (asks.go)
//	N|session|id|project|text  start a thread in a project (its T3 id, or none for a scratch
//	                           folder) with text as its first message; the ack has its id
//
// Each is answered in the next inbox, as an ack ({ id, ok, error }) for a send and a note for the
// rest when they fail. Queued messages go to the game with a small number, q, like threads.

type queued struct {
	thread string
	run    string
}

func (b *Bridge) act(ctx context.Context, char, kind string, parts []string) bool {
	switch {
	case kind == "M" && len(parts) >= 5:
		h, _ := strconv.Atoi(parts[2])
		id, text := parts[3], parts[4]
		ack := map[string]any{"id": id, "ok": true}
		if err := b.send(ctx, h, text); err != nil {
			ack["ok"], ack["error"] = false, err.Error()
			b.Log("%s: send to %d failed: %v", char, h, err)
		} else {
			b.Log("%s: sent %d chars to thread %d", char, len(text), h)
		}
		b.acks = append(b.acks, ack)
	case (kind == "S" || kind == "D") && len(parts) >= 3:
		q, _ := strconv.Atoi(parts[2])
		if err := b.queueAction(ctx, kind, q); err != nil {
			b.acks = append(b.acks, map[string]any{"ok": false, "error": err.Error()})
			b.Log("%s: %s %d failed: %v", char, kind, q, err)
		}
	case kind == "N" && len(parts) >= 5:
		id, project, text := parts[2], parts[3], parts[4]
		ack := map[string]any{"id": id, "ok": true}
		if thread, err := b.launch(ctx, project, text); err != nil {
			ack["ok"], ack["error"] = false, err.Error()
			b.Log("%s: new thread failed: %v", char, err)
		} else {
			ack["thread"] = thread
			b.sentList = "" // the list goes again, with the new thread in it
			b.Log("%s: started thread %s", char, thread)
		}
		b.acks = append(b.acks, ack)
	case kind == "A" && len(parts) >= 4:
		n, _ := strconv.Atoi(parts[2])
		lines := strings.Join(parts[3:], "|") // typed answers may hold | themselves
		if err := b.answer(ctx, n, lines); err != nil {
			b.acks = append(b.acks, map[string]any{"ask": n, "ok": false, "error": err.Error()})
			b.Log("%s: answer %d failed: %v", char, n, err)
		} else {
			b.acks = append(b.acks, map[string]any{"ask": n, "ok": true})
			b.Log("%s: answered question %d", char, n)
		}
	case kind == "X" && len(parts) >= 3:
		h, _ := strconv.Atoi(parts[2])
		if err := b.stop(ctx, h); err != nil {
			b.acks = append(b.acks, map[string]any{"ok": false, "error": err.Error()})
			b.Log("%s: stop %d failed: %v", char, h, err)
		}
	default:
		return false
	}
	b.urgent = true
	b.Poll(ctx, false)
	return true
}

func (b *Bridge) threadOf(h int) (string, error) {
	if h < 1 || h > len(b.ids) {
		return "", fmt.Errorf("that thread isn't known to the program any more; pick it again")
	}
	return b.ids[h-1], nil
}

func (b *Bridge) send(ctx context.Context, h int, text string) error {
	id, err := b.threadOf(h)
	if err != nil {
		return err
	}
	if err := b.connect(ctx); err != nil {
		return err
	}
	_, err = b.client.Call(ctx, "t3_thread_send", map[string]any{
		"threadId": id, "message": text, "mode": "queue",
	})
	return plainError(err)
}

// plainError says what to do about T3 refusals the player can fix. T3 caps what a signed-in
// program may do at the access picked when its sign-in was approved, and refuses a thread that
// runs with more.
func plainError(err error) error {
	if err == nil {
		return nil
	}
	msg := err.Error()
	if strings.Contains(msg, "mode_escalation_denied") {
		return fmt.Errorf("this thread runs with more access than the program's T3 sign-in allows; " +
			"run forever-agent login again and approve it with Full access")
	}
	return err
}

// titleLength is how much of the first line a new thread is named by, until T3 names it itself.
const titleLength = 60

// launch starts a thread with a first message and returns its id. T3 needs a title up front; the
// first line stands in, and T3 is then asked for a proper one, as it gives threads started in it.
func (b *Bridge) launch(ctx context.Context, project, text string) (string, error) {
	if strings.TrimSpace(text) == "" {
		return "", fmt.Errorf("write the first message")
	}
	if err := b.connect(ctx); err != nil {
		return "", err
	}
	title := strings.TrimSpace(strings.SplitN(text, "\n", 2)[0])
	if r := []rune(title); len(r) > titleLength {
		title = strings.TrimSpace(string(r[:titleLength])) + "..."
	}
	args := map[string]any{"title": title, "message": text}
	if project == "" {
		args["scratch"] = true
	} else {
		args["projectId"] = project
	}
	raw, err := b.client.Call(ctx, "t3_thread_launch", args)
	if err != nil {
		return "", plainError(err)
	}
	var res struct {
		ThreadID string `json:"threadId"`
	}
	if err := json.Unmarshal(raw, &res); err != nil || res.ThreadID == "" {
		return "", fmt.Errorf("T3 started no thread")
	}
	if _, err := b.client.Call(ctx, "t3_thread_update", map[string]any{
		"action": "regenerate_title", "threadId": res.ThreadID,
	}); err != nil {
		b.Log("naming thread %s: %v", res.ThreadID, err) // it keeps the first line
	}
	return res.ThreadID, nil
}

func (b *Bridge) stop(ctx context.Context, h int) error {
	id, err := b.threadOf(h)
	if err != nil {
		return err
	}
	if err := b.connect(ctx); err != nil {
		return err
	}
	_, err = b.client.Call(ctx, "t3_thread_interrupt", map[string]any{"threadId": id})
	return plainError(err)
}

func (b *Bridge) queueAction(ctx context.Context, kind string, q int) error {
	if q < 1 || q > len(b.queued) {
		return fmt.Errorf("that queued message is gone")
	}
	item := b.queued[q-1]
	if err := b.connect(ctx); err != nil {
		return err
	}
	args := map[string]any{"threadId": item.thread, "queuedRunId": item.run, "action": "cancel"}
	if kind == "S" {
		active := ""
		if t := b.threads[item.thread]; t != nil {
			active = t.active
		}
		if active == "" {
			return fmt.Errorf("nothing is running to steer into; it runs next anyway")
		}
		args["action"], args["targetRunId"] = "promote_to_steer", active
	}
	_, err := b.client.Call(ctx, "t3_queue", args)
	return plainError(err)
}

func (b *Bridge) queuedNumber(thread, run string) int {
	for i, q := range b.queued {
		if q.thread == thread && q.run == run {
			return i + 1
		}
	}
	b.queued = append(b.queued, queued{thread, run})
	return len(b.queued)
}

// queueNews reads a thread's queued messages, and a signature of them and whether it's running.
func (b *Bridge) queueNews(ctx context.Context, id string) (map[string]any, string, error) {
	raw, err := b.client.Call(ctx, "t3_queue", map[string]any{"action": "list", "threadId": id, "limit": 20})
	if err != nil {
		return nil, "", err
	}
	var res struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(raw, &res); err != nil {
		return nil, "", err
	}
	active, started := "", int64(0)
	if t := b.threads[id]; t != nil {
		active, started = t.active, t.started
	}
	sig := fnv.New64a()
	fmt.Fprintf(sig, "%s|%v|%d\n", id, active != "", started)
	items := []map[string]any{}
	for _, it := range res.Items {
		run := firstString(it, "queuedRunId", "runId", "id")
		if run == "" {
			continue
		}
		text := firstString(it, "text", "message", "preview", "textPreview")
		items = append(items, map[string]any{"q": b.queuedNumber(id, run), "text": text})
		fmt.Fprintf(sig, "%s|%s\n", run, text)
	}
	return map[string]any{"id": id, "active": active != "", "started": started, "items": items},
		fmt.Sprint(sig.Sum64()), nil
}

// firstString is the first of keys that holds a non-empty string. T3's queue items aren't
// documented, so this reads the likely names.
func firstString(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if s, ok := m[k].(string); ok && strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}
