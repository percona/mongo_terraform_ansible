package main

import (
	"html/template"
	"path/filepath"
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
