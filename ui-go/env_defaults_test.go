package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadDefaultImages(t *testing.T) {
	saved := defaultImages
	t.Cleanup(func() { defaultImages = saved })

	path := filepath.Join(t.TempDir(), ".env")
	content := "# PMM 3.10 release candidate\n" +
		"PMM_SERVER_IMAGE=perconalab/pmm-server:3.10.0-rc\n" +
		"PMM_EXTENSIONS_IMAGE=\"percona/pmm-extensions:3.10.0-rc1\"\n" +
		"PMM_CLIENT_IMAGE=\n" +
		"UNRELATED=value\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := loadDefaultImages(path); err != nil {
		t.Fatal(err)
	}

	want := DefaultImages{
		PmmServer:  "perconalab/pmm-server:3.10.0-rc",
		PmmClient:  saved.PmmClient,
		Extensions: "percona/pmm-extensions:3.10.0-rc1",
	}
	if defaultImages != want {
		t.Fatalf("defaultImages = %+v, want %+v", defaultImages, want)
	}
}

func TestLoadDefaultImagesWithoutFile(t *testing.T) {
	saved := defaultImages
	t.Cleanup(func() { defaultImages = saved })

	if err := loadDefaultImages(filepath.Join(t.TempDir(), ".env")); err != nil {
		t.Fatal(err)
	}
	if defaultImages != saved {
		t.Fatalf("defaultImages changed to %+v", defaultImages)
	}
}

func TestConfigureOffersEnvDefaultsToNewEnvironmentsOnly(t *testing.T) {
	savedImages, savedStateFile := defaultImages, stateFile
	t.Cleanup(func() { defaultImages, stateFile = savedImages, savedStateFile })
	stateFile = filepath.Join(t.TempDir(), "environments.json")
	if err := saveState(map[string]*Environment{"old": {Platform: "docker", Config: Config{Prefix: "old"}}}); err != nil {
		t.Fatal(err)
	}
	defaultImages.PmmServer = "perconalab/pmm-server:3.10.0-rc"

	mux := http.NewServeMux()
	mux.HandleFunc("GET /configure/{platform}", configureHandler)
	for _, tc := range []struct{ query, want string }{
		{"", `"pmmServer":"perconalab/pmm-server:3.10.0-rc"`},
		{"?env_id=old", `"pmmServer":"percona/pmm-server:latest"`},
	} {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest("GET", "/configure/docker"+tc.query, nil))
		if !strings.Contains(rec.Body.String(), tc.want) {
			t.Errorf("configure/docker%s: expected %s in the page", tc.query, tc.want)
		}
	}
}
