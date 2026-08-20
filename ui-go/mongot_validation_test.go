package main

import "testing"

func mongotBoolPtr(v bool) *bool { return &v }

func TestValidateMongotVersionCompatibilityPSMDB83(t *testing.T) {
	cfg := &Config{
		Clusters: map[string]ClusterConfig{
			"cluster": {
				EnableMongot:        mongotBoolPtr(true),
				MongoDBDistribution: "psmdb",
				MongoRelease:        "psmdb-83",
				MongotSource:        "auto",
				MongoVersion:        "8.3.7-1",
				MongotVersion:       "1.70.3-1",
			},
		},
	}
	if err := validateMongotVersionCompatibility("aws", cfg); err != nil {
		t.Fatalf("expected supported PSMDB Search combination, got %v", err)
	}
}

func TestValidateMongotVersionCompatibilityRejectsOldPerconaSearch(t *testing.T) {
	cfg := &Config{
		Replsets: map[string]ReplsetConfig{
			"rs": {
				EnableMongot:        mongotBoolPtr(true),
				MongoDBDistribution: "psmdb",
				MongoRelease:        "psmdb-83",
				MongotSource:        "percona_package",
				MongoVersion:        "8.3.7-1",
				MongotVersion:       "1.70.1",
			},
		},
	}
	if err := validateMongotVersionCompatibility("gcp", cfg); err == nil {
		t.Fatal("expected old Search version to be rejected")
	}
}
