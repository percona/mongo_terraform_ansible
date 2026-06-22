package main

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

func boolPtr(v bool) *bool {
	return &v
}

func TestWriteTfvarsChaosOmitsMinioVariablesWhenDisabled(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		EnableMinio:       boolPtr(false),
		MinioRootUser:     "minioadmin",
		MinioRootPassword: "minioadmin",
		MinioPort:         9000,
		MinioConsolePort:  9001,
		MinioCpuCores:     1,
		MinioMemoryGb:     2,
		MinioVolumeSize:   10,
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
	}

	if err := writeTfvars("chaos-minio-disabled", "chaos", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("chaos-minio-disabled", "chaos"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	if !strings.Contains(tfvars, "enable_minio = false") {
		t.Fatalf("expected enable_minio flag in tfvars:\n%s", tfvars)
	}

	for _, unwanted := range []string{
		"minio_root_user =",
		"minio_root_password =",
		"minio_port =",
		"minio_console_port =",
		"minio_cpu_cores =",
		"minio_memory_gb =",
		"minio_volume_size =",
	} {
		if strings.Contains(tfvars, unwanted) {
			t.Fatalf("did not expect %q in tfvars:\n%s", unwanted, tfvars)
		}
	}
}

func TestWriteTfvarsChaosEnableMongot(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	for _, enabled := range []bool{true, false} {
		cfg := Config{
			MongoRelease: "psmdb-83",
			EnableMongot: enabled,
			Clusters: map[string]ClusterConfig{
				"cl01": {EnvTag: "test"},
			},
		}

		envID := "chaos-mongot"
		if err := writeTfvars(envID, "chaos", cfg); err != nil {
			t.Fatalf("writeTfvars failed: %v", err)
		}

		content, err := os.ReadFile(tfvarsPath(envID, "chaos"))
		if err != nil {
			t.Fatalf("read tfvars failed: %v", err)
		}
		want := "enable_mongot = false"
		if enabled {
			want = "enable_mongot = true"
		}
		if !strings.Contains(string(content), want) {
			t.Fatalf("expected %q in tfvars:\n%s", want, content)
		}
	}
}

func TestWriteTfvarsChaosMongoNodeCount(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	// When MongotNodeCount is 0 (default "all nodes") it should be omitted.
	cfgZero := Config{
		EnableMongot:    true,
		MongotNodeCount: 0,
		Clusters:        map[string]ClusterConfig{"cl01": {EnvTag: "test"}},
	}
	if err := writeTfvars("chaos-mongot-nc-zero", "chaos", cfgZero); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}
	contentZero, err := os.ReadFile(tfvarsPath("chaos-mongot-nc-zero", "chaos"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	if strings.Contains(string(contentZero), "mongot_node_count") {
		t.Fatalf("did not expect mongot_node_count when value is 0:\n%s", contentZero)
	}

	// When MongotNodeCount > 0 it should be written.
	for _, n := range []int{1, 2, 3} {
		cfg := Config{
			EnableMongot:    true,
			MongotNodeCount: n,
			Clusters:        map[string]ClusterConfig{"cl01": {EnvTag: "test"}},
		}
		envID := "chaos-mongot-nc"
		if err := writeTfvars(envID, "chaos", cfg); err != nil {
			t.Fatalf("writeTfvars failed: %v", err)
		}
		content, err := os.ReadFile(tfvarsPath(envID, "chaos"))
		if err != nil {
			t.Fatalf("read tfvars failed: %v", err)
		}
		want := fmt.Sprintf("mongot_node_count = %d", n)
		if !strings.Contains(string(content), want) {
			t.Fatalf("expected %q in tfvars:\n%s", want, content)
		}
	}
}
