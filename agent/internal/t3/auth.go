// Package t3 connects to T3 Code through its MCP endpoint, the way it supports outside programs:
// OAuth sign-in once (the player approves it in the browser), then MCP tool calls with the token.
//
// T3's server (seen at 0.1.8-nightly.20261107) advertises standard MCP auth at
// /.well-known/oauth-authorization-server: dynamic client registration, the authorization code
// grant with PKCE (S256), public clients, and scopes orchestration:read and orchestration:operate.
// There's no refresh token, so when the token runs out the player signs in again.
package t3

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Scopes asked for: reading threads, and sending to them.
const Scopes = "orchestration:read orchestration:operate"

// Token is a saved sign-in.
type Token struct {
	Server      string    `json:"server"` // e.g. http://127.0.0.1:3773
	ClientID    string    `json:"clientId"`
	AccessToken string    `json:"accessToken"`
	Scope       string    `json:"scope,omitempty"`
	ExpiresAt   time.Time `json:"expiresAt,omitempty"`
}

// Expired says whether the token has run out (or will within a minute).
func (t *Token) Expired() bool {
	return !t.ExpiresAt.IsZero() && time.Now().Add(time.Minute).After(t.ExpiresAt)
}

// MCPURL is the server's MCP endpoint.
func (t *Token) MCPURL() string { return strings.TrimRight(t.Server, "/") + "/mcp" }

// TokenPath is where the sign-in is saved, in the program's own folder.
func TokenPath(data string) string { return filepath.Join(data, "t3.json") }

// LoadToken reads the saved sign-in.
func LoadToken(data string) (*Token, error) {
	b, err := os.ReadFile(TokenPath(data))
	if err != nil {
		return nil, err
	}
	var t Token
	if err := json.Unmarshal(b, &t); err != nil {
		return nil, err
	}
	return &t, nil
}

// Save writes the sign-in, readable only by this Windows user's programs.
func (t *Token) Save(data string) error {
	if err := os.MkdirAll(data, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(t, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(TokenPath(data), b, 0o600)
}

// DefaultServer is the local T3 server, from the file T3 writes when it starts.
func DefaultServer() string {
	home, _ := os.UserHomeDir()
	b, err := os.ReadFile(filepath.Join(home, ".t3", "userdata", "server-runtime.json"))
	if err == nil {
		var rt struct {
			Origin string `json:"origin"`
		}
		if json.Unmarshal(b, &rt) == nil && rt.Origin != "" {
			return rt.Origin
		}
	}
	return "http://127.0.0.1:3773"
}

type serverMeta struct {
	AuthorizationEndpoint string `json:"authorization_endpoint"`
	TokenEndpoint         string `json:"token_endpoint"`
	RegistrationEndpoint  string `json:"registration_endpoint"`
}

func getJSON(ctx context.Context, u string, out any) error {
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("%s: %s", u, resp.Status)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func random(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// Login signs in to the T3 server: registers this program, opens the approval page in the
// browser, waits for the player to approve, and returns the token. show is told the page's
// address too, in case the browser doesn't open.
func Login(ctx context.Context, server string, show func(url string)) (*Token, error) {
	server = strings.TrimRight(server, "/")
	var meta serverMeta
	if err := getJSON(ctx, server+"/.well-known/oauth-authorization-server", &meta); err != nil {
		return nil, fmt.Errorf("is T3 Code running? %w", err)
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	defer listener.Close()
	redirect := fmt.Sprintf("http://127.0.0.1:%d/callback", listener.Addr().(*net.TCPAddr).Port)

	// Register this program.
	reg, _ := json.Marshal(map[string]any{
		"client_name":                "Forever Agent (WoW: Forever)",
		"redirect_uris":              []string{redirect},
		"grant_types":                []string{"authorization_code"},
		"response_types":             []string{"code"},
		"token_endpoint_auth_method": "none",
		"scope":                      Scopes,
	})
	req, _ := http.NewRequestWithContext(ctx, "POST", meta.RegistrationEndpoint, strings.NewReader(string(reg)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	var client struct {
		ClientID string `json:"client_id"`
	}
	err = json.NewDecoder(resp.Body).Decode(&client)
	resp.Body.Close()
	if err != nil || client.ClientID == "" {
		return nil, fmt.Errorf("registering with T3: %s %v", resp.Status, err)
	}

	// Ask the player to approve it.
	verifier, state := random(32), random(16)
	sum := sha256.Sum256([]byte(verifier))
	resource := server + "/mcp"
	q := url.Values{
		"response_type":         {"code"},
		"client_id":             {client.ClientID},
		"redirect_uri":          {redirect},
		"scope":                 {Scopes},
		"state":                 {state},
		"code_challenge":        {base64.RawURLEncoding.EncodeToString(sum[:])},
		"code_challenge_method": {"S256"},
		"resource":              {resource},
	}
	approve := meta.AuthorizationEndpoint + "?" + q.Encode()
	show(approve)
	exec.Command("rundll32", "url.dll,FileProtocolHandler", approve).Start()

	codes := make(chan url.Values, 1)
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/callback" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, "<!doctype html><title>Forever Agent</title><body style=\"font:16px system-ui;padding:2em\">"+
			"Forever Agent is signed in to T3 Code. You can close this tab.</body>")
		select {
		case codes <- r.URL.Query():
		default:
		}
	})}
	go srv.Serve(listener)
	defer srv.Close()

	var got url.Values
	select {
	case got = <-codes:
	case <-time.After(10 * time.Minute):
		return nil, errors.New("no approval within 10 minutes")
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	if e := got.Get("error"); e != "" {
		return nil, fmt.Errorf("T3 said no: %s %s", e, got.Get("error_description"))
	}
	if got.Get("state") != state {
		return nil, errors.New("the approval came back for a different sign-in; try again")
	}

	// Trade the code for a token.
	form := url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {got.Get("code")},
		"redirect_uri":  {redirect},
		"client_id":     {client.ClientID},
		"code_verifier": {verifier},
		"resource":      {resource},
	}
	resp, err = http.PostForm(meta.TokenEndpoint, form)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var tok struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
		Scope       string `json:"scope"`
		Error       string `json:"error"`
		Description string `json:"error_description"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tok); err != nil {
		return nil, fmt.Errorf("token: %s %v", resp.Status, err)
	}
	if tok.AccessToken == "" {
		return nil, fmt.Errorf("token: %s %s %s", resp.Status, tok.Error, tok.Description)
	}
	t := &Token{Server: server, ClientID: client.ClientID, AccessToken: tok.AccessToken, Scope: tok.Scope}
	if tok.ExpiresIn > 0 {
		t.ExpiresAt = time.Now().Add(time.Duration(tok.ExpiresIn) * time.Second)
	}
	return t, nil
}
