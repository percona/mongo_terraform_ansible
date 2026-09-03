package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNormalizedYcsbLoadConfigDefaults(t *testing.T) {
	cfg := normalizedYcsbLoadConfig(YcsbLoadConfig{})
	if cfg.RecordCount != 1000000 || cfg.Workload != "workloade" || cfg.MaxScanLength != 10000 {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
	if cfg.Threads != 4 || cfg.TargetOpsPerSecond != 1000 || cfg.DurationSeconds != 600 || !cfg.ResetBeforeLoad {
		t.Fatalf("unexpected execution defaults: %+v", cfg)
	}
}

func TestYcsbWorkloadArgs(t *testing.T) {
	cfg := YcsbLoadConfig{RecordCount: 250000, Workload: "workloade", MaxScanLength: 5000, ScanLengthDistribution: "uniform", Threads: 8, TargetOpsPerSecond: 200, DurationSeconds: 30}
	load := ycsbWorkloadArgs("/ycsb/bin/ycsb", "load", "/ycsb/workloads/workloade", "mongodb://example/ycsb", cfg)
	for _, want := range []string{"recordcount=250000", "workloade", "maxscanlength=5000", "scanlengthdistribution=uniform"} {
		if !strings.Contains(load, want) {
			t.Fatalf("load command missing %q: %s", want, load)
		}
	}
	if strings.Contains(load, "operationcount=") || strings.Contains(load, "-threads") {
		t.Fatalf("load command contains run-only arguments: %s", load)
	}
	run := ycsbWorkloadArgs("/ycsb/bin/ycsb", "run", "/ycsb/workloads/workloade", "mongodb://example/ycsb", cfg)
	for _, want := range []string{"operationcount=6000", "-target 200", "-threads 8"} {
		if !strings.Contains(run, want) {
			t.Fatalf("run command missing %q: %s", want, run)
		}
	}
}

func TestYcsbDeploymentReady(t *testing.T) {
	applied := Config{}
	tests := []struct {
		name string
		env  *Environment
		want bool
	}{
		{name: "not deployed", env: &Environment{Status: "configured"}},
		{name: "failed first deploy", env: &Environment{Status: "deploy_failed"}},
		{name: "successful deploy", env: &Environment{Status: "running", LastAppliedConfig: &applied}, want: true},
		{name: "successful deploy history", env: &Environment{Status: "ycsb_load_failed", History: []HistoryEvent{{Action: "deploy", Status: "success"}}}, want: true},
		{name: "legacy running environment", env: &Environment{Status: "running"}, want: true},
		{name: "deleted environment", env: &Environment{Status: "deleted", LastAppliedConfig: &applied}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ycsbDeploymentReady(tt.env); got != tt.want {
				t.Fatalf("ycsbDeploymentReady() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestYcsbResetCommandUsesDockerContainer(t *testing.T) {
	env := &Environment{Platform: "docker", Config: Config{Prefix: "test"}}
	command := ycsbResetCommand("env", env, "replset", "rs01", "mongodb://unused")

	for _, want := range []string{
		"docker exec 'test-rs01-svr0'",
		"mongosh",
		"dropDatabase()",
	} {
		if !strings.Contains(command, want) {
			t.Fatalf("reset command missing %q: %s", want, command)
		}
	}
}

func TestYcsbResetCommandUsesCloudTopologyHost(t *testing.T) {
	tmp := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = tmp
	t.Cleanup(func() { terraformDir = origTerraformDir })
	if err := os.MkdirAll(filepath.Join(tmp, "chaos"), 0755); err != nil {
		t.Fatal(err)
	}

	inventory := `[replsets:children]
rs01

[rs01]
source-node ansible_host=10.0.0.10
arbiter-node ansible_host=10.0.0.11 arbiter=True

[all:vars]
ansible_user=test
`
	if err := os.WriteFile(filepath.Join(tmp, "chaos", "env_inventory_rs01"), []byte(inventory), 0644); err != nil {
		t.Fatal(err)
	}

	env := &Environment{
		Platform: "chaos",
		Config: Config{
			Prefix:   "env",
			Replsets: map[string]ReplsetConfig{"rs01": {}},
			UseTLS:   true,
		},
	}
	command := ycsbResetCommand("env", env, "replset", "rs01", "mongodb://root:secret@source-node:27017/?authSource=admin&tls=true")

	for _, want := range []string{
		"ssh 'source-node'",
		"mongosh",
		"--tls --tlsCertificateKeyFile /etc/ssl/client.pem --tlsCAFile /etc/ssl/test-ca.pem",
		"dropDatabase()",
	} {
		if !strings.Contains(command, want) {
			t.Fatalf("reset command missing %q: %s", want, command)
		}
	}
	if strings.Contains(command, "only supported") {
		t.Fatalf("cloud reset still reports unsupported: %s", command)
	}
}

func TestYcsbResetCommandUsesMongosForCloudCluster(t *testing.T) {
	tmp := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = tmp
	t.Cleanup(func() { terraformDir = origTerraformDir })
	if err := os.MkdirAll(filepath.Join(tmp, "aws"), 0755); err != nil {
		t.Fatal(err)
	}

	inventory := `[mongos]
router-node ansible_host=10.0.0.20

[shards:children]
shard0
`
	if err := os.WriteFile(filepath.Join(tmp, "aws", "env_inventory_cluster"), []byte(inventory), 0644); err != nil {
		t.Fatal(err)
	}

	env := &Environment{
		Platform: "aws",
		Config: Config{
			Prefix:   "env",
			Clusters: map[string]ClusterConfig{"cluster": {}},
		},
	}
	command := ycsbResetCommand("env", env, "cluster", "cluster", "mongodb://root:secret@router-node:27017/?authSource=admin")
	if !strings.Contains(command, "ssh 'router-node'") {
		t.Fatalf("cluster reset should use mongos host: %s", command)
	}
}
