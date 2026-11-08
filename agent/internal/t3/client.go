package t3

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// Client is a connection to T3's MCP endpoint.
type Client struct {
	session *mcp.ClientSession
}

type bearer struct {
	token string
	next  http.RoundTripper
}

func (b bearer) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", "Bearer "+b.token)
	return b.next.RoundTrip(r)
}

// ErrSignIn means the token is missing, ran out, or was turned down: sign in again.
var ErrSignIn = errors.New("sign in to T3 again: forever-agent login")

// Connect opens an MCP session with the saved token.
func Connect(ctx context.Context, tok *Token, version string) (*Client, error) {
	if tok == nil || tok.AccessToken == "" || tok.Expired() {
		return nil, ErrSignIn
	}
	httpClient := &http.Client{Transport: bearer{tok.AccessToken, http.DefaultTransport}}
	client := mcp.NewClient(&mcp.Implementation{Name: "forever-agent", Version: version}, nil)
	session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
		Endpoint:             tok.MCPURL(),
		HTTPClient:           httpClient,
		DisableStandaloneSSE: true, // replies come from polling; T3 sends nothing unasked
	}, nil)
	if err != nil {
		if strings.Contains(err.Error(), "401") || strings.Contains(err.Error(), "Unauthorized") {
			return nil, ErrSignIn
		}
		return nil, err
	}
	return &Client{session: session}, nil
}

// Close ends the session.
func (c *Client) Close() error { return c.session.Close() }

// Tool is one of T3's tools, with what it takes.
type Tool struct {
	Name        string
	Description string
	Input       json.RawMessage
}

// Tools lists T3's tools.
func (c *Client) Tools(ctx context.Context) ([]Tool, error) {
	var out []Tool
	for tool, err := range c.session.Tools(ctx, nil) {
		if err != nil {
			return nil, err
		}
		input, _ := json.Marshal(tool.InputSchema)
		out = append(out, Tool{Name: tool.Name, Description: tool.Description, Input: input})
	}
	return out, nil
}

// Call runs one of T3's tools and returns what it says: its structured result when it gives
// one, else its text.
func (c *Client) Call(ctx context.Context, name string, args any) (json.RawMessage, error) {
	res, err := c.session.CallTool(ctx, &mcp.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		return nil, err
	}
	var text strings.Builder
	for _, content := range res.Content {
		if t, ok := content.(*mcp.TextContent); ok {
			text.WriteString(t.Text)
		}
	}
	if res.IsError {
		return nil, fmt.Errorf("%s: %s", name, text.String())
	}
	if res.StructuredContent != nil {
		return json.Marshal(res.StructuredContent)
	}
	return json.RawMessage(mustJSONString(text.String())), nil
}

// mustJSONString is s as JSON: as is when it already is JSON, else as a JSON string.
func mustJSONString(s string) []byte {
	if json.Valid([]byte(s)) {
		return []byte(s)
	}
	b, _ := json.Marshal(s)
	return b
}
