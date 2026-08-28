package main

import (
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
