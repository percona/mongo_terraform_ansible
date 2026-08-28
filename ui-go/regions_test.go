package main

import (
	"bytes"
	"encoding/json"
	"html/template"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestGCPRegionSelectorRendersImmediateOptions(t *testing.T) {
	tmpl, err := template.New("").Funcs(funcMap).ParseFiles(
		filepath.Join("templates", "layout.html"),
		filepath.Join("templates", "configure.html"),
	)
	if err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct {
		name           string
		configured     string
		selectedRegion string
	}{
		{name: "default", selectedRegion: "northamerica-northeast1"},
		{name: "saved region outside fallback list", configured: "me-central1", selectedRegion: "me-central1"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var page bytes.Buffer
			data := ConfigureData{
				Platform: "gcp",
				Config:   Config{Region: tc.configured},
				Regions:  defaultRegions("gcp"),
			}
			if err := tmpl.ExecuteTemplate(&page, "layout", data); err != nil {
				t.Fatal(err)
			}

			selected := `<option value="` + tc.selectedRegion + `" selected>` + tc.selectedRegion + `</option>`
			if !strings.Contains(page.String(), selected) {
				t.Fatalf("region selector missing selected option %q", selected)
			}
			if !strings.Contains(page.String(), `<option value="us-central1">us-central1</option>`) {
				t.Fatal("region selector missing immediate fallback options")
			}
		})
	}
}

func TestAPIRegionsRefreshBypassesCache(t *testing.T) {
	const platform = "cache-test"
	cacheSet("regions:"+platform, []string{"cached-region"})
	t.Cleanup(func() { cacheDelete("regions:" + platform) })

	req := httptest.NewRequest(http.MethodGet, "/api/regions/"+platform+"?refresh=1", nil)
	req.SetPathValue("platform", platform)
	rec := httptest.NewRecorder()
	apiRegionsHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	var payload struct {
		Regions []string `json:"regions"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Regions) != 0 {
		t.Fatalf("regions = %v, want refreshed result", payload.Regions)
	}
}
