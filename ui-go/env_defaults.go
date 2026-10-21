package main

import (
	"bufio"
	"errors"
	"io/fs"
	"os"
	"strings"
)

// DefaultImages are the images the configure page offers for a new environment or block.
type DefaultImages struct {
	PmmServer  string `json:"pmmServer"`
	PmmClient  string `json:"pmmClient"`
	Extensions string `json:"extensions"`
}

// builtinDefaultImages match the Terraform defaults; existing environments keep using them.
var builtinDefaultImages = DefaultImages{
	PmmServer:  "percona/pmm-server:latest",
	PmmClient:  "percona/pmm-client:latest",
	Extensions: defaultExtensionsImage,
}

// defaultImages are builtinDefaultImages with the .env overrides, offered to new environments.
var defaultImages = builtinDefaultImages

// loadDefaultImages overrides defaultImages from the PMM_SERVER_IMAGE, PMM_CLIENT_IMAGE and
// PMM_EXTENSIONS_IMAGE lines of a KEY=VALUE file. A missing file is not an error.
func loadDefaultImages(path string) error {
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer f.Close()

	targets := map[string]*string{
		"PMM_SERVER_IMAGE":     &defaultImages.PmmServer,
		"PMM_CLIENT_IMAGE":     &defaultImages.PmmClient,
		"PMM_EXTENSIONS_IMAGE": &defaultImages.Extensions,
	}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		key, value, ok := strings.Cut(strings.TrimSpace(scanner.Text()), "=")
		if !ok || strings.HasPrefix(key, "#") {
			continue
		}
		value = strings.Trim(strings.TrimSpace(value), `"'`)
		if target := targets[strings.TrimSpace(key)]; target != nil && value != "" {
			*target = value
		}
	}
	return scanner.Err()
}
