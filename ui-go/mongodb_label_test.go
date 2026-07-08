package main

import "testing"

func TestMongoDBPackageLabelUsesTopologyDistribution(t *testing.T) {
	cfg := Config{
		Replsets: map[string]ReplsetConfig{
			"rs1": {
				MongoDBDistribution: "community",
				MongoRelease:        "8.0",
				MongoVersion:        "8.0.13",
			},
		},
	}

	got := mongodbPackageLabel(cfg)
	want := "MongoDB Community 8.0.13"
	if got != want {
		t.Fatalf("mongodbPackageLabel() = %q, want %q", got, want)
	}
}

func TestMongoDBPackageLabelUsesEnterpriseRelease(t *testing.T) {
	cfg := Config{
		Clusters: map[string]ClusterConfig{
			"c1": {
				MongoDBDistribution: "enterprise",
				MongoRelease:        "7.0",
			},
		},
	}

	got := mongodbPackageLabel(cfg)
	want := "MongoDB Enterprise 7.0"
	if got != want {
		t.Fatalf("mongodbPackageLabel() = %q, want %q", got, want)
	}
}

func TestMongoDBPackageLabelDefaultsToPSMDB(t *testing.T) {
	got := mongodbPackageLabel(Config{})
	want := "PSMDB psmdb-80"
	if got != want {
		t.Fatalf("mongodbPackageLabel() = %q, want %q", got, want)
	}
}
