package main

import "testing"

func TestChaosAPIProbeURLUsesProviderEndpoint(t *testing.T) {
	t.Setenv("CHAOS_API_URL", "")
	t.Setenv("CHAOS_API_PROBE_URL", "")

	if got := chaosAPIProbeURL(); got != defaultChaosAPIURL {
		t.Fatalf("chaosAPIProbeURL() = %q, want %q", got, defaultChaosAPIURL)
	}
}

func TestChaosAPIProbeURLUsesProviderOverride(t *testing.T) {
	t.Setenv("CHAOS_API_PROBE_URL", "https://probe.example.test")
	t.Setenv("CHAOS_API_URL", "https://provider.example.test/api")

	if got := chaosAPIProbeURL(); got != "https://provider.example.test/api" {
		t.Fatalf("chaosAPIProbeURL() = %q, want provider API override", got)
	}
}
