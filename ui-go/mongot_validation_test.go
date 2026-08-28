package main

import "testing"

func mongotBoolPtr(v bool) *bool { return &v }

func TestValidateMongotVersionCompatibilityPSMDB83(t *testing.T) {
	for _, version := range []string{"1.70", "1.70.1", "1.70.3-1", "1.80.0", "2.0.0"} {
		t.Run(version, func(t *testing.T) {
			cfg := &Config{
				Clusters: map[string]ClusterConfig{
					"cluster": {
						EnableMongot:        mongotBoolPtr(true),
						MongoDBDistribution: "psmdb",
						MongoRelease:        "psmdb-83",
						MongotSource:        "auto",
						MongoVersion:        "8.3.7-1",
						MongotVersion:       version,
					},
				},
			}
			if err := validateMongotVersionCompatibility("aws", cfg); err != nil {
				t.Fatalf("expected Percona Search %s to be supported, got %v", version, err)
			}
		})
	}
}

func TestValidateMongotVersionCompatibilityRejectsUnsupportedPerconaSearch(t *testing.T) {
	for _, version := range []string{"1.69.9", "0.80.0", "2.-1", "invalid"} {
		t.Run(version, func(t *testing.T) {
			cfg := &Config{
				Replsets: map[string]ReplsetConfig{
					"rs": {
						EnableMongot:        mongotBoolPtr(true),
						MongoDBDistribution: "psmdb",
						MongoRelease:        "psmdb-83",
						MongotSource:        "percona_package",
						MongoVersion:        "8.3.7-1",
						MongotVersion:       version,
					},
				},
			}
			if err := validateMongotVersionCompatibility("gcp", cfg); err == nil {
				t.Fatalf("expected Percona Search %s to be rejected", version)
			}
		})
	}
}

func TestValidateMongotVersionCompatibilityRejectsInvalidPerconaSearchChannel(t *testing.T) {
	cfg := &Config{
		Clusters: map[string]ClusterConfig{
			"cluster": {
				EnableMongot:        mongotBoolPtr(true),
				MongoDBDistribution: "psmdb",
				MongoRelease:        "psmdb-83",
				MongotSource:        "percona_package",
				MongotRepo:          "nightly",
				MongoVersion:        "8.3.7-1",
				MongotVersion:       "1.70.3-1",
			},
		},
	}
	if err := validateMongotVersionCompatibility("aws", cfg); err == nil {
		t.Fatal("expected invalid Percona Search channel to be rejected")
	}
}
