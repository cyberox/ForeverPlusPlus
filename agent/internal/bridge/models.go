package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"time"
)

// The models a new thread can start on, from T3's orchestrator_capabilities: each provider T3
// runs (Codex, Claude through each of its sign-ins) with its models. Providers T3 has turned off
// say so in their constraints, and are left out.

const modelsEvery = 10 * time.Minute

// readModels reads T3's providers and their models, now and then.
func (b *Bridge) readModels(ctx context.Context) {
	if time.Since(b.modelsRead) < modelsEvery {
		return
	}
	b.modelsRead = time.Now()
	raw, err := b.client.Call(ctx, "orchestrator_capabilities", map[string]any{})
	if err != nil {
		b.Log("T3 models: %v", err) // new threads use T3's own choice
		return
	}
	var res struct {
		Providers []struct {
			DisplayName        string   `json:"displayName"`
			ProviderInstanceID string   `json:"providerInstanceId"`
			Constraints        []string `json:"constraints"`
			Models             []struct {
				ID    string `json:"id"`
				Label string `json:"label"`
			} `json:"models"`
		} `json:"providers"`
	}
	if err := json.Unmarshal(raw, &res); err != nil {
		b.Log("T3 models: %v", err)
		return
	}
	var providers []map[string]any
	for _, p := range res.Providers {
		if len(p.Constraints) > 0 || len(p.Models) == 0 {
			continue
		}
		models := make([]map[string]any, 0, len(p.Models))
		for _, m := range p.Models {
			models = append(models, map[string]any{"id": m.ID, "label": m.Label})
		}
		providers = append(providers, map[string]any{"name": p.DisplayName, "instance": p.ProviderInstanceID,
			"models": models})
	}
	b.models = providers
}

// modelsNews is the providers and a signature of them.
func (b *Bridge) modelsNews() ([]map[string]any, string) {
	sig := fnv.New64a()
	for _, p := range b.models {
		fmt.Fprintf(sig, "%s|%s\n", p["instance"], p["name"])
		for _, m := range p["models"].([]map[string]any) {
			fmt.Fprintf(sig, " %s|%s\n", m["id"], m["label"])
		}
	}
	return b.models, fmt.Sprint(sig.Sum64())
}
