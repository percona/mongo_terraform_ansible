package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigurePaths(t *testing.T) {
	repo := t.TempDir()
	if err := os.MkdirAll(filepath.Join(repo, "terraform"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(repo, "ansible"), 0755); err != nil {
		t.Fatal(err)
	}
	data := filepath.Join(t.TempDir(), "data")
	t.Setenv("UI_REPO_DIR", repo)
	t.Setenv("UI_DATA_DIR", data)

	if err := configurePaths(); err != nil {
		t.Fatal(err)
	}
	if terraformDir != filepath.Join(repo, "terraform") || ansibleDir != filepath.Join(repo, "ansible") {
		t.Fatalf("unexpected repository paths: %q, %q", terraformDir, ansibleDir)
	}
	if stateFile != filepath.Join(data, "environments.json") || settingsFile != filepath.Join(data, "settings.json") {
		t.Fatalf("unexpected data paths: %q, %q", stateFile, settingsFile)
	}
}

func TestConfigurePathsRequiresRepository(t *testing.T) {
	t.Setenv("UI_REPO_DIR", "")
	if err := configurePaths(); err == nil || !strings.Contains(err.Error(), "UI_REPO_DIR is required") {
		t.Fatalf("expected required repository error, got %v", err)
	}
}

func TestEmbeddedStaticAssets(t *testing.T) {
	if _, err := uiAssets.ReadFile("static/style.css"); err != nil {
		t.Fatal(err)
	}
}
