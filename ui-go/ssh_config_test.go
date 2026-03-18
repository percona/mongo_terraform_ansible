package main

import (
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
