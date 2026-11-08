package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"strconv"
	"strings"
)

// Questions an agent asks the player (Claude's AskUserQuestion and the like), which the game shows
// with their options and answers:
//
//	A|session|a|answers   answer question request a; answers has a line per question, in order:
//	                      "o:1,3" for options picked (from 1), or "t:text" for the player's own
//
// T3's MCP tools list and answer questions but not permission approvals (t3_pending_request:
// "approvals are not listed", "cannot approve a permission request"), so for those the game only
// says one waits. Checked against T3 Code on 2026-11-08 with a throwaway thread: a request reads as
// { requestId, questions: [{ id, header, question, multiSelect, options: [{ label, description }] }] },
// and is answered with { <question id>: "label" } or, for multiSelect, { <question id>: ["a", "b"] }.

type ask struct {
	thread    string
	request   string
	questions []question
}

type question struct {
	ID       string `json:"id"`
	Header   string `json:"header"`
	Question string `json:"question"`
	Multi    bool   `json:"multiSelect"`
	Options  []struct {
		Label       string `json:"label"`
		Description string `json:"description"`
	} `json:"options"`
}

// askFor is the request's small number, reading it from T3 the first time (it doesn't change).
func (b *Bridge) askFor(ctx context.Context, thread, request string) (int, *ask, error) {
	for i, a := range b.asks {
		if a.thread == thread && a.request == request {
			return i + 1, a, nil
		}
	}
	raw, err := b.client.Call(ctx, "t3_pending_request", map[string]any{
		"action": "read", "threadId": thread, "requestId": request,
	})
	if err != nil {
		return 0, nil, err
	}
	var res struct {
		Questions []question `json:"questions"`
	}
	if err := json.Unmarshal(raw, &res); err != nil {
		return 0, nil, err
	}
	a := &ask{thread: thread, request: request, questions: res.Questions}
	b.asks = append(b.asks, a)
	return len(b.asks), a, nil
}

// asksNews reads the questions waiting in a thread, how many approvals wait besides, and a
// signature of them.
func (b *Bridge) asksNews(ctx context.Context, id string) (map[string]any, string, error) {
	t := b.threads[id]
	pending := 0
	if t != nil {
		pending = t.pending
	}
	items := []map[string]any{}
	sig := fnv.New64a()
	fmt.Fprintf(sig, "%s|%d\n", id, pending)
	if pending > 0 || b.statuses[id] == "waiting" {
		raw, err := b.client.Call(ctx, "t3_pending_request", map[string]any{"action": "list", "threadId": id})
		if err != nil {
			return nil, "", err
		}
		var res struct {
			RequestIDs []string `json:"requestIds"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return nil, "", err
		}
		for _, request := range res.RequestIDs {
			n, a, err := b.askFor(ctx, id, request)
			if err != nil {
				return nil, "", err
			}
			questions := make([]map[string]any, 0, len(a.questions))
			for _, q := range a.questions {
				options := make([]map[string]any, 0, len(q.Options))
				for _, o := range q.Options {
					options = append(options, map[string]any{"label": o.Label, "description": o.Description})
				}
				questions = append(questions, map[string]any{
					"header": q.Header, "question": q.Question, "multi": q.Multi, "options": options,
				})
			}
			items = append(items, map[string]any{"a": n, "questions": questions})
			fmt.Fprintf(sig, "%d\n", n)
		}
	}
	approvals := pending - len(items)
	if approvals < 0 {
		approvals = 0
	}
	return map[string]any{"id": id, "items": items, "approvals": approvals}, fmt.Sprint(sig.Sum64()), nil
}

// answer answers question request n from the game's lines.
func (b *Bridge) answer(ctx context.Context, n int, lines string) error {
	if n < 1 || n > len(b.asks) {
		return fmt.Errorf("that question is gone")
	}
	a := b.asks[n-1]
	parts := strings.Split(lines, "\n")
	if len(parts) != len(a.questions) {
		return fmt.Errorf("answer every question")
	}
	answers := map[string]any{}
	for i, q := range a.questions {
		part := parts[i]
		switch {
		case strings.HasPrefix(part, "t:") && strings.TrimSpace(part[2:]) != "":
			text := strings.TrimSpace(part[2:])
			if q.Multi {
				answers[q.ID] = []string{text}
			} else {
				answers[q.ID] = text
			}
		case strings.HasPrefix(part, "o:"):
			var labels []string
			for _, s := range strings.Split(part[2:], ",") {
				o, err := strconv.Atoi(s)
				if err != nil || o < 1 || o > len(q.Options) {
					return fmt.Errorf("that answer isn't one of the options")
				}
				labels = append(labels, q.Options[o-1].Label)
			}
			if q.Multi {
				answers[q.ID] = labels
			} else {
				answers[q.ID] = labels[0]
			}
		default:
			return fmt.Errorf("answer every question")
		}
	}
	if err := b.connect(ctx); err != nil {
		return err
	}
	_, err := b.client.Call(ctx, "t3_pending_request", map[string]any{
		"action": "respond", "threadId": a.thread, "requestId": a.request, "answers": answers,
	})
	return err
}
