package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigServiceURLsChaosUsesDirectPMMHost(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	if err := os.MkdirAll(filepath.Join(dir, "chaos"), 0755); err != nil {
		t.Fatalf("mkdir failed: %v", err)
	}

	inventory := `[pmm]
env-pmm ansible_host=10.11.12.13

[minio]
env-minio ansible_host=10.11.12.14
`
	if err := os.WriteFile(filepath.Join(dir, "chaos", "env_inventory_rs01"), []byte(inventory), 0644); err != nil {
		t.Fatalf("write inventory failed: %v", err)
	}

	enablePmm := true
	env := &Environment{
		Platform: "chaos",
		Config: Config{
			Prefix:    "env",
			EnablePmm: &enablePmm,
			PmmPort:   8443,
			Replsets: map[string]ReplsetConfig{
				"rs01": {EnvTag: "test", DataNodesPerReplset: 1},
			},
		},
	}

	urls := configServiceURLs("env", env)
	var pmmURL string
	for _, svc := range urls {
		if svc.Name == "pmm" {
			pmmURL = svc.URL
		}
	}
	if pmmURL != "https://10.11.12.13:8443" {
		t.Fatalf("expected direct PMM URL, got %q", pmmURL)
	}
}

func TestChaosReachabilityHandlerReturnsBadGatewayWhenUnreachable(t *testing.T) {
	dir := t.TempDir()
	origStateFile := stateFile
	stateFile = filepath.Join(dir, "environments.json")
	origProbe := os.Getenv("CHAOS_API_PROBE_URL")
	if err := os.Setenv("CHAOS_API_PROBE_URL", "http://nonexistent.invalid"); err != nil {
		t.Fatalf("setenv failed: %v", err)
	}
	t.Cleanup(func() {
		stateFile = origStateFile
		if origProbe == "" {
			_ = os.Unsetenv("CHAOS_API_PROBE_URL")
		} else {
			_ = os.Setenv("CHAOS_API_PROBE_URL", origProbe)
		}
	})

	state := map[string]*Environment{
		"chaos-env": {Platform: "chaos", Config: Config{Clusters: map[string]ClusterConfig{"cl01": {EnvTag: "test"}}}},
	}
	if err := saveState(state); err != nil {
		t.Fatalf("saveState failed: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/environment/chaos-env/chaos/reachability", nil)
	req.SetPathValue("env_id", "chaos-env")
	rec := httptest.NewRecorder()

	chaosReachabilityHandler(rec, req)

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("expected status %d, got %d", http.StatusBadGateway, rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if body["reachable"] != false {
		t.Fatalf("expected reachable=false, got %#v", body["reachable"])
	}
	errMsg, _ := body["error"].(string)
	if !strings.Contains(errMsg, "Percona VPN") {
		t.Fatalf("expected VPN guidance in error, got %#v", body["error"])
	}
}
