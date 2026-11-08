package bridge

import (
	"strings"
	"testing"
)

func TestSummarize(t *testing.T) {
	cases := []struct {
		kind, title, text, status string
		want                      step
		ok                        bool
	}{
		{"command_execution", "", "$ cd /c/repo/agent && go test ./...\nok  github.com/x", "completed",
			step{Kind: "ran", Detail: "go test ./..."}, true},
		{"command_execution", "", "$ Set-Location 'C:\\a b'; go vet ./...", "failed",
			step{Kind: "ran", Detail: "go vet ./...", Failed: true}, true},
		{"file_change", "", "C:\\repo\\agent\\main.go\n--- C:\\repo\\agent\\main.go\n+++ x", "completed",
			step{Kind: "edited", Detail: "main.go"}, true},
		{"file_change", "", "C:\\repo\\agent\\steps.go\n--- /dev/null\n+++ x", "completed",
			step{Kind: "created", Detail: "steps.go"}, true},
		{"dynamic_tool", "Read C:\\repo\\README.md", `{"toolName": "Read", "input": {"file_path": "C:\\repo\\README.md"}}`,
			"completed", step{Kind: "read", Detail: "README.md"}, true},
		{"dynamic_tool", "Read C:\\repo\\Window.lua", `{"toolName": "Read", "inp`, "completed",
			step{Kind: "read", Detail: "Window.lua"}, true}, // cut short: the title says it
		{"dynamic_tool", "", `{"toolName": "PowerShell", "input": {"command": "Get-Process wow"}}`, "completed",
			step{Kind: "ran", Detail: "Get-Process wow"}, true},
		{"dynamic_tool", "", `{"toolName": "Grep", "input": {"pattern": "AGENTCHAT_"}}`, "completed",
			step{Kind: "searched", Detail: "AGENTCHAT_"}, true},
		{"dynamic_tool", "", `{"toolName": "mcp__t3-code__t3_thread_read", "input": {}}`, "completed",
			step{Kind: "used", Detail: "t3_thread_read"}, true},
		{"reasoning", "Thinking", "I'm weighing...", "completed", step{}, false},
		{"assistant_message", "", "Done.", "completed", step{}, false},
	}
	for _, c := range cases {
		got, ok := summarize(c.kind, c.title, c.text, c.status)
		if ok != c.ok || (ok && got != c.want) {
			t.Errorf("summarize(%s, %q) = %+v, %v; want %+v, %v", c.kind, c.text, got, ok, c.want, c.ok)
		}
	}
	long := "$ echo " + strings.Repeat("a", 90)
	if got, _ := summarize("command_execution", "", long, ""); len([]rune(got.Detail)) != detailLength+3 {
		t.Errorf("a long command isn't cut: %q", got.Detail)
	}
}
