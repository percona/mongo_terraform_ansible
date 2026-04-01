package main

import (
	"os"
	"strings"
	"testing"
)

func intPtr(v int) *int {
	return &v
}

func TestWriteTfvarsDockerPmmExternalAndEmptyServiceMaps(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
		Replsets: map[string]ReplsetConfig{
			"rs01": {EnvTag: "test", DataNodesPerReplset: 1, ArbitersPerReplset: intPtr(0), ReplsetPort: 27017, ArbiterPort: 27017},
		},
		PmmServers: map[string]PmmServerConfig{
			"pmm-server": {EnvTag: "test", PmmExternalPort: 9443},
		},
	}

	if err := writeTfvars("docker-ports", "docker", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("docker-ports", "docker"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	for _, want := range []string{
		"pmm_external_port = 9443",
		"minio_servers = {}",
	} {
		if !strings.Contains(tfvars, want) {
			t.Fatalf("expected %q in tfvars:\n%s", want, tfvars)
		}
	}
}

func TestWriteTfvarsDockerEmptyPmmServersMap(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
	}

	if err := writeTfvars("docker-empty-services", "docker", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("docker-empty-services", "docker"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	for _, want := range []string{
		"pmm_servers = {}",
		"minio_servers = {}",
	} {
		if !strings.Contains(tfvars, want) {
			t.Fatalf("expected %q in tfvars:\n%s", want, tfvars)
		}
	}
}

func TestAssignDockerReplsetPortsAvoidsServicePorts(t *testing.T) {
	cfg := &Config{
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 2, ArbitersPerReplset: intPtr(1)},
		},
		PmmServers: map[string]PmmServerConfig{
			"pmm-server": {PmmExternalPort: 27017},
		},
	}

	assignDockerReplsetPorts(cfg)

	rs := cfg.Replsets["rs01"]
	if rs.ReplsetPort != 27037 {
		t.Fatalf("expected replset port 27037 to avoid PMM port 27017, got %d", rs.ReplsetPort)
	}
}

func TestValidateDockerPortConflictsDetectsOverlap(t *testing.T) {
	cfg := Config{
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 2, ArbitersPerReplset: intPtr(1), ReplsetPort: 27017, ArbiterPort: 27017},
		},
		MinioServers: map[string]MinioServerConfig{
			"minio-server": {MinioPort: 27018},
		},
	}

	err := validateDockerPortConflicts(cfg)
	if err == nil {
		t.Fatal("expected docker port conflict error")
	}
	if !strings.Contains(err.Error(), "port 27018") {
		t.Fatalf("expected conflict error to mention port 27018, got %v", err)
	}
}
