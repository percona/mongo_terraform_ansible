package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
		"pmm_port = 8443",
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

func TestWriteTfvarsCloudPmmClientVersion(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		MongoRelease:     "psmdb-80",
		PmmClientVersion: "3.4.0",
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
	}

	if err := writeTfvars("cloud-pmm-client", "gcp", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("cloud-pmm-client", "gcp"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	if !strings.Contains(tfvars, "pmm_client_version = \"3.4.0\"") {
		t.Fatalf("expected pmm_client_version in tfvars:\n%s", tfvars)
	}
}

func TestWriteTfvarsIncludesEnableYcsbForAllPlatforms(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	platforms := []string{"docker", "gcp", "aws", "azure", "chaos"}
	for _, platform := range platforms {
		cfg := Config{
			EnableYcsb: true,
			Clusters: map[string]ClusterConfig{
				"cl01": {EnvTag: "test"},
			},
		}

		if err := writeTfvars("enable-ycsb-"+platform, platform, cfg); err != nil {
			t.Fatalf("platform %s: writeTfvars failed: %v", platform, err)
		}

		content, err := os.ReadFile(tfvarsPath("enable-ycsb-"+platform, platform))
		if err != nil {
			t.Fatalf("platform %s: read tfvars failed: %v", platform, err)
		}
		if !strings.Contains(string(content), "enable_ycsb = true") {
			t.Fatalf("platform %s: expected enable_ycsb in tfvars:\n%s", platform, string(content))
		}
	}
}

func TestWriteTfvarsDockerYcsbSettings(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		EnableYcsb:          true,
		YcsbImage:           "custom/ycsb:dev",
		YcsbOsImage:         "rockylinux:9",
		YcsbContainerSuffix: "bench",
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
	}

	if err := writeTfvars("docker-ycsb-settings", "docker", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("docker-ycsb-settings", "docker"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	for _, want := range []string{
		"enable_ycsb = true",
		`ycsb_image = "custom/ycsb:dev"`,
		`ycsb_os_image = "rockylinux:9"`,
		`ycsb_container_suffix = "bench"`,
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

	err := validateDockerPortConflicts("", cfg, nil)
	if err == nil {
		t.Fatal("expected docker port conflict error")
	}
	if !strings.Contains(err.Error(), "port 27018") {
		t.Fatalf("expected conflict error to mention port 27018, got %v", err)
	}
}

func TestDockerConfigureDefaultsAvoidRunningEnvironmentServicePorts(t *testing.T) {
	state := map[string]*Environment{
		"env-running": {
			Platform: "docker",
			Status:   "running",
			Config: Config{
				PmmServers: map[string]PmmServerConfig{
					"pmm-server": {PmmPort: 8443, PmmExternalPort: 8443},
				},
				MinioServers: map[string]MinioServerConfig{
					"minio": {MinioPort: 9000, MinioConsolePort: 9001},
				},
			},
		},
	}

	occupied := dockerOccupiedServicePorts(state, "")
	pmmPort := nextFreeDockerPort(8443, occupied)
	minioPort, minioConsolePort := nextFreeDockerPortPair(9000, occupied)

	if pmmPort != 8444 {
		t.Fatalf("expected PMM external port 8444, got %d", pmmPort)
	}
	if minioPort != 9002 || minioConsolePort != 9003 {
		t.Fatalf("expected MinIO ports 9002/9003, got %d/%d", minioPort, minioConsolePort)
	}
}

func TestSaveEnvironmentHandlerDetectsRunningDockerEnvironmentPortConflicts(t *testing.T) {
	dir := t.TempDir()
	origStateFile := stateFile
	origTerraformDir := terraformDir
	stateFile = dir + "/environments.json"
	terraformDir = dir
	t.Cleanup(func() {
		stateFile = origStateFile
		terraformDir = origTerraformDir
	})

	existing := map[string]*Environment{
		"env-running": {
			Platform: "docker",
			Status:   "running",
			Config: Config{
				Prefix: "env-running",
				Replsets: map[string]ReplsetConfig{
					"rs01": {DataNodesPerReplset: 2, ArbitersPerReplset: intPtr(1), ReplsetPort: 27017, ArbiterPort: 27017},
				},
				PmmServers: map[string]PmmServerConfig{
					"pmm-server": {PmmPort: 8443, PmmExternalPort: 8443},
				},
				MinioServers: map[string]MinioServerConfig{
					"minio": {MinioPort: 9000, MinioConsolePort: 9001},
				},
			},
		},
	}
	if err := saveState(existing); err != nil {
		t.Fatalf("saveState failed: %v", err)
	}

	payload := map[string]interface{}{
		"env_id":   "env-new",
		"platform": "docker",
		"config": Config{
			Prefix: "env-new",
			Replsets: map[string]ReplsetConfig{
				"rs01": {DataNodesPerReplset: 2, ArbitersPerReplset: intPtr(1), ReplsetPort: 27017, ArbiterPort: 27017},
			},
			PmmServers: map[string]PmmServerConfig{
				"pmm-server": {PmmPort: 8443, PmmExternalPort: 8443},
			},
			MinioServers: map[string]MinioServerConfig{
				"minio": {MinioPort: 9000, MinioConsolePort: 9001},
			},
		},
	}
	body, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload failed: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/environment", strings.NewReader(string(body)))
	rec := httptest.NewRecorder()
	saveEnvironmentHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response failed: %v", err)
	}
	if !strings.Contains(resp.Error, "port 27017") {
		t.Fatalf("expected conflict response to mention port 27017, got %s", resp.Error)
	}
	if !strings.Contains(resp.Error, "docker port conflicts detected:\n-") {
		t.Fatalf("expected multiline conflict response, got %s", resp.Error)
	}
	if !strings.Contains(resp.Error, "this environment replica set") {
		t.Fatalf("expected conflict response to mention this environment, got %s", resp.Error)
	}
	if !strings.Contains(resp.Error, "environment env-running replica set") {
		t.Fatalf("expected conflict response to mention running environment, got %s", resp.Error)
	}

	state, err := loadState()
	if err != nil {
		t.Fatalf("loadState failed: %v", err)
	}
	if _, exists := state["env-new"]; exists {
		t.Fatal("conflicting environment should not be saved")
	}
}
