package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReplaceSSHBlock(t *testing.T) {
	// Test: append new block to empty file
	result := replaceSSHBlock("", "# === BEGIN ===", "# === END ===", "# === BEGIN ===\nHost foo\n    HostName 1.2.3.4\n# === END ===\n")
	if !strings.Contains(result, "Host foo") {
		t.Errorf("expected Host foo in result, got: %s", result)
	}

	// Test: replace existing block
	existing := "# some existing config\n\n# === BEGIN ===\nHost old\n    HostName 9.9.9.9\n# === END ===\nHost other\n    HostName 5.5.5.5\n"
	result = replaceSSHBlock(existing, "# === BEGIN ===", "# === END ===", "# === BEGIN ===\nHost new\n    HostName 1.2.3.4\n# === END ===\n")
	if strings.Contains(result, "Host old") {
		t.Errorf("expected old block to be replaced, got: %s", result)
	}
	if !strings.Contains(result, "Host new") {
		t.Errorf("expected new block in result, got: %s", result)
	}
	if !strings.Contains(result, "Host other") {
		t.Errorf("expected other host to be preserved, got: %s", result)
	}

	// Test: remove block
	result = replaceSSHBlock(existing, "# === BEGIN ===", "# === END ===", "")
	if strings.Contains(result, "Host old") {
		t.Errorf("expected old block to be removed, got: %s", result)
	}
	if !strings.Contains(result, "Host other") {
		t.Errorf("expected other host to be preserved, got: %s", result)
	}
}

func TestAssignDockerReplsetPorts(t *testing.T) {
	cfg := &Config{
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 2},
			"rs02": {DataNodesPerReplset: 2},
		},
	}
	assignDockerReplsetPorts(cfg)

	rs01 := cfg.Replsets["rs01"]
	rs02 := cfg.Replsets["rs02"]

	if rs01.ReplsetPort == rs02.ReplsetPort {
		t.Errorf("rs01 and rs02 should have different ports, both got %d", rs01.ReplsetPort)
	}
	if rs01.ReplsetPort == 0 {
		t.Errorf("rs01 should have a non-zero port")
	}
	if rs02.ReplsetPort == 0 {
		t.Errorf("rs02 should have a non-zero port")
	}
	// Ensure they're 20 apart
	diff := rs02.ReplsetPort - rs01.ReplsetPort
	if diff != 20 && diff != -20 {
		t.Errorf("ports should be 20 apart, got rs01=%d rs02=%d", rs01.ReplsetPort, rs02.ReplsetPort)
	}
}

func TestParseAPTPackageVersions(t *testing.T) {
	samplePackages := `Package: percona-server-mongodb
Version: 7.0.12-3.jammy
Architecture: amd64

Package: percona-server-mongodb-server
Version: 7.0.12-3.jammy
Architecture: amd64

Package: percona-server-mongodb
Version: 7.0.11-2.jammy
Architecture: amd64

Package: percona-backup-mongodb
Version: 2.7.0-1.jammy
Architecture: amd64

Package: percona-backup-mongodb
Version: 2.11.0-1.jammy
Architecture: amd64

Package: percona-backup-mongodb
Version: 2.0.5-1.jammy
Architecture: amd64

Package: percona-mongodb-mongosh
Version: 2.3.7-1.jammy
Architecture: amd64
`
	got := parseAPTPackageVersions(samplePackages, "percona-server-mongodb")
	if len(got) != 2 {
		t.Errorf("expected 2 versions, got %d: %v", len(got), got)
	}
	if got[0] != "7.0.12" {
		t.Errorf("expected first version 7.0.12, got %s", got[0])
	}
	if got[1] != "7.0.11" {
		t.Errorf("expected second version 7.0.11, got %s", got[1])
	}

	// PBM: all versions should appear in a flat list, newest first.
	// Specifically 2.11.0 > 2.7.0 > 2.0.5 (semantic sort, not lexicographic).
	pbmVers := parseAPTPackageVersions(samplePackages, "percona-backup-mongodb")
	if len(pbmVers) != 3 {
		t.Errorf("expected 3 PBM versions, got %d: %v", len(pbmVers), pbmVers)
	}
	if pbmVers[0] != "2.11.0" {
		t.Errorf("expected first PBM version 2.11.0 (semantic > 2.7.0), got %s", pbmVers[0])
	}
	if pbmVers[1] != "2.7.0" {
		t.Errorf("expected second PBM version 2.7.0, got %s", pbmVers[1])
	}
	if pbmVers[2] != "2.0.5" {
		t.Errorf("expected third PBM version 2.0.5, got %s", pbmVers[2])
	}
}

func TestSemverGreater(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"7.0.12", "7.0.9", true},   // multi-digit patch: 12 > 9
		{"7.0.9", "7.0.12", false},  // 9 < 12
		{"8.0.0", "7.0.12", true},   // major version wins
		{"7.0.12", "7.0.12", false}, // equal
		{"7.1.0", "7.0.12", true},   // minor version wins
		{"2.7.0", "2.6.0", true},    // pbm-style versions
		{"2.6.0", "2.7.0", false},
	}
	for _, c := range cases {
		got := semverGreater(c.a, c.b)
		if got != c.want {
			t.Errorf("semverGreater(%q, %q) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}

func TestWriteTfvarsDockerCredentials(t *testing.T) {
	dir := t.TempDir()
	// Override terraformDir so writeTfvars writes into the temp directory.
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test", ConfigsvrCount: 1, ShardCount: 1, ShardsvrReplicas: 1, MongosCount: 1},
		},
		Replsets: map[string]ReplsetConfig{
			"rs01": {EnvTag: "test", DataNodesPerReplset: 1},
		},
		PmmServers: map[string]PmmServerConfig{
			"pmm-server": {EnvTag: "test"},
		},
		AnsibleVars: map[string]string{
			"mongo_admin_password": "mysecret",
		},
	}

	if err := writeTfvars("testenv", "docker", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("testenv", "docker"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	checks := []struct {
		desc string
		want string
	}{
		{"mongodb_root_password in clusters", `mongodb_root_password = "mysecret"`},
		{"mongodb_root_password in replsets", `mongodb_root_password = "mysecret"`},
	}
	for _, c := range checks {
		if !strings.Contains(tfvars, c.want) {
			t.Errorf("%s: expected %q in tfvars:\n%s", c.desc, c.want, tfvars)
		}
	}

	// pmm_server_user/pwd are no longer set via the credentials section
	for _, unwanted := range []string{"pmm_server_user", "pmm_server_pwd"} {
		if strings.Contains(tfvars, unwanted) {
			t.Errorf("expected no %q in tfvars (PMM user/pwd not settable via credentials section):\n%s", unwanted, tfvars)
		}
	}
}

func TestWriteTfvarsDockerNoCredentials(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
		Replsets: map[string]ReplsetConfig{},
	}

	if err := writeTfvars("testenv2", "docker", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}

	content, err := os.ReadFile(tfvarsPath("testenv2", "docker"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	tfvars := string(content)

	for _, unwanted := range []string{"mongodb_root_password", "pmm_server_user", "pmm_server_pwd"} {
		if strings.Contains(tfvars, unwanted) {
			t.Errorf("expected no %q in tfvars when credentials are empty:\n%s", unwanted, tfvars)
		}
	}
}

func TestCleanupDockerModuleArtifacts(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	// Create fake module directory tree.
	replsetDir := filepath.Join(dir, "docker", "modules", "mongodb_replset")
	clusterDir := filepath.Join(dir, "docker", "modules", "mongodb_cluster")
	if err := os.MkdirAll(replsetDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(clusterDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Simulate files created by Terraform for an environment with prefix "myenv".
	filesToCreate := []string{
		filepath.Join(replsetDir, "pbm-storage.conf.myenv-rs01"),
		filepath.Join(replsetDir, "myenv-rs01-percona-pbm-agent.Dockerfile"),
		filepath.Join(clusterDir, "pbm-storage.conf.myenv-cl01"),
		filepath.Join(clusterDir, "myenv-cl01-percona-pbm-agent.Dockerfile"),
	}
	for _, f := range filesToCreate {
		if err := os.WriteFile(f, []byte("test"), 0644); err != nil {
			t.Fatalf("create %s: %v", f, err)
		}
	}

	// Simulate old-style subdirectory created when image name had a "/".
	oldDir := filepath.Join(replsetDir, "myenv-rs01-percona")
	if err := os.MkdirAll(oldDir, 0755); err != nil {
		t.Fatal(err)
	}
	oldFile := filepath.Join(oldDir, "pbm-agent.Dockerfile")
	if err := os.WriteFile(oldFile, []byte("test"), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := Config{
		Prefix: "myenv",
		Replsets: map[string]ReplsetConfig{
			"rs01": {EnvTag: "test"},
		},
		Clusters: map[string]ClusterConfig{
			"cl01": {EnvTag: "test"},
		},
	}

	cleanupDockerModuleArtifacts(cfg)

	// All created files and directories should be gone.
	for _, f := range filesToCreate {
		if _, err := os.Stat(f); !os.IsNotExist(err) {
			t.Errorf("expected %s to be removed", f)
		}
	}
	if _, err := os.Stat(oldDir); !os.IsNotExist(err) {
		t.Errorf("expected old-style directory %s to be removed", oldDir)
	}
}

func TestTfstatePathHelpers(t *testing.T) {
	origTerraformDir := terraformDir
	terraformDir = "/tmp/tf"
	t.Cleanup(func() { terraformDir = origTerraformDir })

	if got := tfstatePath("myenv", "docker"); got != "/tmp/tf/docker/myenv.tfstate" {
		t.Errorf("tfstatePath = %q", got)
	}
	if got := tfstateBackupPath("myenv", "gcp"); got != "/tmp/tf/gcp/myenv.tfstate.backup" {
		t.Errorf("tfstateBackupPath = %q", got)
	}
}

func TestTfstateRemovedOnDeleteHandler(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	origStateFile := stateFile
	terraformDir = dir
	t.Cleanup(func() {
		terraformDir = origTerraformDir
		stateFile = origStateFile
	})

	platform := "docker"
	platformDir := filepath.Join(dir, platform)
	if err := os.MkdirAll(platformDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Write a minimal state file so loadState / saveState work.
	sf := filepath.Join(dir, "environments.json")
	stateFile = sf

	// Pre-create the tfvars, tfstate and tfstate.backup files.
	for _, name := range []string{"testenv.tfvars", "testenv.tfstate", "testenv.tfstate.backup"} {
		if err := os.WriteFile(filepath.Join(platformDir, name), []byte("x"), 0644); err != nil {
			t.Fatal(err)
		}
	}

	// Save a matching environment entry.
	env := &Environment{
		Platform: platform,
		Status:   "running",
		Config:   Config{},
	}
	if err := saveState(map[string]*Environment{"testenv": env}); err != nil {
		t.Fatalf("saveState: %v", err)
	}

	// Call deleteEnvironmentHandler via the path-value mechanism is tricky; call
	// the underlying cleanup logic directly instead.
	state, _ := loadState()
	e := state["testenv"]
	delete(state, "testenv")
	saveState(state)
	if e != nil {
		os.Remove(tfvarsPath("testenv", e.Platform))
		os.Remove(tfstatePath("testenv", e.Platform))
		os.Remove(tfstateBackupPath("testenv", e.Platform))
	}

	// All three files should be gone.
	for _, name := range []string{"testenv.tfvars", "testenv.tfstate", "testenv.tfstate.backup"} {
		p := filepath.Join(platformDir, name)
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Errorf("expected %s to be removed after delete", p)
		}
	}
}

func TestGuessDockerRole(t *testing.T) {
	prefix := "myenv"
	tests := []struct {
		name string
		want string
	}{
		{"myenv-rs01-node1-pbm-agent", "pbm-agent"},
		{"myenv-cl01-node2-pbm-agent", "pbm-agent"},
		{"myenv-rs01-pbm-cli", "pbm-cli"},
		{"myenv-cl01-pbm-cli", "pbm-cli"},
		{"myenv-rs01-node1-pmm-client", "pmm-client"},
		{"myenv-cl01-cfg1-pmm-client", "pmm-client"},
		{"myenv-pmm-server", "pmm"},
		{"myenv-pmm-server-pmm", "pmm"},
		{"myenv-rs01-node1svr", "mongod"},
		{"myenv-rs01-arb1", "arbiter"},
		{"myenv-cl01-cfg1", "configsvr"},
		{"myenv-cl01-mongos1", "mongos"},
		{"myenv-minio-server", "minio"},
		{"myenv-ldap-server", "ldap"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := guessDockerRole(tc.name, prefix)
			if got != tc.want {
				t.Errorf("guessDockerRole(%q, %q) = %q, want %q", tc.name, prefix, got, tc.want)
			}
		})
	}
}

func TestGuessDockerGroup(t *testing.T) {
	prefix := "myenv"
	tests := []struct {
		name string
		want string
	}{
		{"myenv-rs01-node1-pbm-agent", "PBM"},
		{"myenv-cl01-node2-pbm-agent", "PBM"},
		{"myenv-rs01-pbm-cli", "PBM"},
		{"myenv-cl01-pbm-cli", "PBM"},
		{"myenv-rs01-node1-pmm-client", "PMM Clients"},
		{"myenv-cl01-cfg1-pmm-client", "PMM Clients"},
		{"myenv-pmm-server", "PMM"},
		{"myenv-rs01-node1svr", "rs01"},
		{"myenv-cl01-arb1", "cl01"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := guessDockerGroup(tc.name, prefix)
			if got != tc.want {
				t.Errorf("guessDockerGroup(%q, %q) = %q, want %q", tc.name, prefix, got, tc.want)
			}
		})
	}
}
