package main

import (
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
