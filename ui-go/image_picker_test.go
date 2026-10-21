package main

import (
	"html/template"
	"strings"
	"testing"
)

func renderConfigure(t *testing.T, data ConfigureData) string {
	t.Helper()
	tmpl, err := template.New("").Funcs(funcMap).ParseFS(uiAssets, "templates/layout.html", "templates/configure.html")
	if err != nil {
		t.Fatal(err)
	}
	var out strings.Builder
	if err := tmpl.ExecuteTemplate(&out, "layout", data); err != nil {
		t.Fatal(err)
	}
	return out.String()
}

func TestConfigureKeepsSavedDockerPmmImages(t *testing.T) {
	cfg := Config{
		PmmServers: map[string]PmmServerConfig{"pmm-server": {PmmServerImage: "perconalab/pmm-server:3.10.0-rc"}},
		Replsets:   map[string]ReplsetConfig{"rs01": {PmmClientImage: "perconalab/pmm-client-fb:PR-1"}},
	}
	page := renderConfigure(t, ConfigureData{
		Platform:         "docker",
		Config:           cfg,
		PMMImages:        []string{"latest", "3.9.1"},
		PMMClientImages:  []string{"latest", "3.9.1"},
		SortedPmmServers: sortedPmmServers(cfg.PmmServers),
		SortedReplsets:   sortedReplsets(cfg.Replsets),
	})
	for _, want := range []string{
		`<option value="3.10.0-rc" selected>perconalab/pmm-server:3.10.0-rc</option>`,
		`<option value="__custom__" selected>Custom image…</option>`,
		`name="replset_pmm_client_image_custom" value="perconalab/pmm-client-fb:PR-1"`,
	} {
		if !strings.Contains(page, want) {
			t.Errorf("expected %q in the rendered page", want)
		}
	}
}

func TestConfigureKeepsSavedCloudPmmImage(t *testing.T) {
	page := renderConfigure(t, ConfigureData{
		Platform:  "chaos",
		Config:    Config{PmmImage: "perconalab/pmm-server:3.10.0-rc"},
		PMMImages: []string{"latest", "3.9.1"},
	})
	if !strings.Contains(page, `<option value="3.10.0-rc" selected>perconalab/pmm-server:3.10.0-rc</option>`) {
		t.Error("the saved PMM Server tag is not selected")
	}
}
