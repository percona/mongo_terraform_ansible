package main

import (
	"strings"
	"testing"
)

func TestAnalyseTopologyChangeAllowsScaleOut(t *testing.T) {
	previous := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {ConfigsvrCount: 3, ShardCount: 2, ShardsvrReplicas: 2, ArbitersPerReplset: intPtr(1)},
		},
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 2, ArbitersPerReplset: intPtr(1)},
		},
	}
	desired := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {ConfigsvrCount: 3, ShardCount: 4, ShardsvrReplicas: 2, ArbitersPerReplset: intPtr(1)},
		},
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 3, ArbitersPerReplset: intPtr(1)},
		},
	}

	plan, unsupported := analyseTopologyChange(previous, desired)
	if len(unsupported) != 0 {
		t.Fatalf("expected no unsupported changes, got %v", unsupported)
	}
	if got := plan.AddedShards["cl01"]; len(got) != 2 || got[0] != 2 || got[1] != 3 {
		t.Fatalf("unexpected added shards: %v", got)
	}
	if got := plan.AddedReplsetNodes["rs01"]; got != 1 {
		t.Fatalf("unexpected added replset node count: %d", got)
	}
}

func TestAnalyseTopologyChangeRejectsUnsupportedChanges(t *testing.T) {
	previous := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {ConfigsvrCount: 3, ShardCount: 3, ShardsvrReplicas: 2, ArbitersPerReplset: intPtr(1)},
		},
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 3, ArbitersPerReplset: intPtr(1)},
		},
	}
	desired := Config{
		Clusters: map[string]ClusterConfig{
			"cl01": {ConfigsvrCount: 5, ShardCount: 2, ShardsvrReplicas: 3, ArbitersPerReplset: intPtr(2)},
		},
		Replsets: map[string]ReplsetConfig{
			"rs01": {DataNodesPerReplset: 2, ArbitersPerReplset: intPtr(0)},
		},
	}

	_, unsupported := analyseTopologyChange(previous, desired)
	joined := strings.Join(unsupported, "\n")
	for _, want := range []string{
		"changing config server count",
		"reducing shard count",
		"changing replicas per shard",
		"changing arbiters per shard",
		"reducing data-bearing nodes",
		"changing arbiters",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("expected unsupported message containing %q, got %v", want, unsupported)
		}
	}
}
