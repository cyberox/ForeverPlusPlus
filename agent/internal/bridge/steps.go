package bridge

import (
	"context"
	"encoding/json"
	"path/filepath"
	"regexp"
	"strings"
)

// A step is something an agent did along the way: a command run, a file changed, a tool used. T3
// keeps them in a thread's activity view, beside its messages and in the same positions. The game
// shows each as a short gray line, from a kind and a detail; it has the words for each kind.
//
// Kinds: ran (a command), edited, created (a file), read (a file), searched (for text or files),
// web (a page or a search), used (any other tool, by name).

type step struct {
	Kind    string
	Detail  string
	Failed  bool
	Running bool // read again until it ends
}

const (
	detailLength = 70
	stepChars    = 400 // of each activity item: enough for a command or a path, not a whole diff
	stepPages    = 30
)

// readSteps reads the thread's activity after position `from` the first time, and after that from
// the second to last item read, or the earliest step still running if that's before it, so what
// is still going comes again until it ends.
func (b *Bridge) readSteps(ctx context.Context, id string, t *thread, from int) error {
	if t.steps == nil {
		t.steps = map[int]*step{}
	}
	after := from
	if n := len(t.activity); n >= 2 {
		after = t.activity[n-2]
	} else if n == 1 {
		after = t.activity[0] - 1
	}
	for pos, s := range t.steps {
		if s.Running && pos-1 < after {
			after = pos - 1
		}
	}
	seen := map[int]bool{}
	for _, pos := range t.activity {
		seen[pos] = true
	}
	for page := 0; page < stepPages; page++ {
		args := map[string]any{"threadId": id, "view": "activity", "limit": readPage, "maxCharsPerItem": stepChars}
		if after >= 0 {
			args["afterPosition"] = after
		}
		raw, err := b.client.Call(ctx, "t3_thread_read", args)
		if err != nil {
			return err
		}
		var res struct {
			HasMore      bool `json:"hasMore"`
			NextPosition *int `json:"nextPosition"`
			Items        []struct {
				Position int    `json:"position"`
				Type     string `json:"type"`
				Title    string `json:"title"`
				Text     string `json:"text"`
				Status   string `json:"status"`
			} `json:"items"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}
		for _, it := range res.Items {
			if !seen[it.Position] {
				seen[it.Position] = true
				t.activity = append(t.activity, it.Position)
			}
			if s, ok := summarize(it.Type, it.Title, it.Text, it.Status); ok {
				t.steps[it.Position] = &s
			}
		}
		if !res.HasMore || res.NextPosition == nil || len(res.Items) == 0 {
			break
		}
		after = *res.NextPosition
	}
	return nil
}

var spaces = regexp.MustCompile(`\s+`)

// A leading "cd <folder> &&" or "Set-Location <folder>;" only says where it ran; the command is
// what follows.
var leadingCd = regexp.MustCompile(`^(cd|Set-Location)\s+("[^"]*"|'[^']*'|\S+)\s*(&&|;)\s*`)

func short(s string) string {
	s = strings.TrimSpace(spaces.ReplaceAllString(s, " "))
	if r := []rune(s); len(r) > detailLength {
		s = strings.TrimSpace(string(r[:detailLength])) + "..."
	}
	return s
}

func command(s string) string {
	s = strings.TrimSpace(strings.SplitN(s, "\n", 2)[0])
	for {
		trimmed := leadingCd.ReplaceAllString(s, "")
		if trimmed == s {
			break
		}
		s = trimmed
	}
	return short(s)
}

// base is a path's file name, whichever slashes it uses.
func base(path string) string {
	path = strings.TrimRight(strings.TrimSpace(path), `\/`)
	if i := strings.LastIndexAny(path, `\/`); i >= 0 {
		path = path[i+1:]
	}
	return path
}

// toolName is an MCP tool's own name, without its server: mcp__t3-code__t3_thread_read is
// t3_thread_read.
func toolName(name string) string {
	if i := strings.LastIndex(name, "__"); i >= 0 {
		return name[i+2:]
	}
	return name
}

// summarize says what an activity item did, or false for one that isn't a step (messages,
// thinking, checkpoints).
func summarize(kind, title, text, status string) (step, bool) {
	s := step{Failed: status == "failed", Running: status == "running"}
	switch kind {
	case "command_execution":
		cmd := strings.TrimPrefix(strings.TrimSpace(text), "$ ")
		if cmd == "" {
			return s, false
		}
		s.Kind, s.Detail = "ran", command(cmd)
	case "file_change":
		lines := strings.SplitN(text, "\n", 3)
		if strings.TrimSpace(lines[0]) == "" {
			return s, false
		}
		s.Kind, s.Detail = "edited", base(lines[0])
		if len(lines) > 1 && strings.Contains(lines[1], "/dev/null") {
			s.Kind = "created"
		}
	case "dynamic_tool":
		var call struct {
			ToolName string         `json:"toolName"`
			Input    map[string]any `json:"input"`
		}
		json.Unmarshal([]byte(text), &call) // cut short, it may not parse; the title still helps
		in := func(key string) string {
			v, _ := call.Input[key].(string)
			return v
		}
		name := toolName(call.ToolName)
		switch {
		case in("command") != "":
			s.Kind, s.Detail = "ran", command(in("command"))
		case name == "Read" || strings.HasPrefix(title, "Read "):
			path := in("file_path")
			if path == "" {
				path = strings.TrimPrefix(title, "Read ")
			}
			s.Kind, s.Detail = "read", base(path)
		case name == "Edit" || name == "Write" || name == "NotebookEdit":
			s.Kind, s.Detail = "edited", base(in("file_path"))
		case name == "Grep" || name == "Glob":
			s.Kind, s.Detail = "searched", short(in("pattern"))
		case name == "WebFetch":
			s.Kind, s.Detail = "web", short(in("url"))
		case name == "WebSearch":
			s.Kind, s.Detail = "web", short(in("query"))
		case name != "":
			s.Kind, s.Detail = "used", short(name)
		case title != "":
			s.Kind, s.Detail = "used", short(filepath.Base(title))
		default:
			return s, false
		}
	default:
		return s, false
	}
	return s, s.Detail != ""
}
