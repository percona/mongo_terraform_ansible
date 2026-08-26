package main

import (
	"html/template"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTemplatesParse(t *testing.T) {
	tmplDir := filepath.Join("templates")
	pages := []string{"configure", "environment", "index", "new_environment"}
	for _, page := range pages {
		t.Run(page, func(t *testing.T) {
			_, err := template.New("").Funcs(funcMap).ParseFiles(
				filepath.Join(tmplDir, "layout.html"),
				filepath.Join(tmplDir, page+".html"),
			)
			if err != nil {
				t.Fatalf("parse %s template: %v", page, err)
			}
		})
	}
}

func TestDockerMongotImageSelectorSupportsCustomRepository(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("templates", "configure.html"))
	if err != nil {
		t.Fatalf("read configure template: %v", err)
	}
	template := string(content)
	for _, want := range []string{
		`{{$mongotNs := imageNamespace $curMongot "percona"}}{{$mongotRepo := imageRepository $curMongot "percona-search-mongodb"}}`,
		`class="docker-image-repository" value="{{$mongotRepo}}" placeholder="repository" aria-label="mongot image repository" {{if not (mongotNamespaceCustom $mongotNs)}}style="display:none"{{end}}`,
		`onDockerMongotNamespaceChange`,
		`/api/docker-tags?namespace=${encodeURIComponent(namespace)}&repo=${encodeURIComponent(repo)}`,
	} {
		if !strings.Contains(template, want) {
			t.Errorf("configure template missing %q", want)
		}
	}
}
