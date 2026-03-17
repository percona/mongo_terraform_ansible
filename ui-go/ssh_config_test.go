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
