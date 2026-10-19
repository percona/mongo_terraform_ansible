package main

import (
	"os"
	"strings"
	"testing"
)

func TestWriteTfvarsWritesPmmExtensions(t *testing.T) {
	origTerraformDir := terraformDir
	terraformDir = t.TempDir()
	t.Cleanup(func() { terraformDir = origTerraformDir })

	docker := Config{PmmServers: map[string]PmmServerConfig{
		"pmm-server": {EnvTag: "test", EnableExtensions: true, ExtensionsImage: "percona/pmm-extensions:3.10.0-rc1"},
	}}
	chaos := Config{EnableExtensions: true, ExtensionsImage: "percona/pmm-extensions:3.10.0-rc1"}

	for _, tc := range []struct {
		platform string
		cfg      Config
		want     []string
	}{
		{"docker", docker, []string{"    enable_extensions = true", `    extensions_image = "percona/pmm-extensions:3.10.0-rc1"`}},
		{"chaos", chaos, []string{"enable_extensions = true", `extensions_image = "percona/pmm-extensions:3.10.0-rc1"`}},
	} {
		if err := writeTfvars("ext", tc.platform, tc.cfg); err != nil {
			t.Fatalf("%s: writeTfvars: %v", tc.platform, err)
		}
		data, err := os.ReadFile(tfvarsPath("ext", tc.platform))
		if err != nil {
			t.Fatal(err)
		}
		for _, want := range tc.want {
			if !strings.Contains(string(data), want) {
				t.Errorf("%s: expected %q in tfvars:\n%s", tc.platform, want, data)
			}
		}
	}
}

func TestWriteTfvarsOmitsPmmExtensionsWhenDisabled(t *testing.T) {
	origTerraformDir := terraformDir
	terraformDir = t.TempDir()
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{PmmServers: map[string]PmmServerConfig{
		"pmm-server": {EnvTag: "test", ExtensionsImage: "percona/pmm-extensions:3.10.0-rc1"},
	}}
	for _, platform := range []string{"docker", "chaos"} {
		if err := writeTfvars("noext", platform, cfg); err != nil {
			t.Fatalf("%s: writeTfvars: %v", platform, err)
		}
		data, err := os.ReadFile(tfvarsPath("noext", platform))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(data), "extensions") {
			t.Errorf("%s: unexpected extensions settings in tfvars:\n%s", platform, data)
		}
	}
}
