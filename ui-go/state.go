package main

import (
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"sync"
)

var envIDRe = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,40}$`)
var envNameRe = regexp.MustCompile(`^[a-z0-9]{1,16}$`)

var stateMu sync.Mutex
var settingsMu sync.Mutex

func loadState() (map[string]*Environment, error) {
	stateMu.Lock()
	defer stateMu.Unlock()
	data, err := os.ReadFile(stateFile)
	if os.IsNotExist(err) {
		return map[string]*Environment{}, nil
	}
	if err != nil {
		return nil, err
	}
	var state map[string]*Environment
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}
	return state, nil
}

func saveState(state map[string]*Environment) error {
	stateMu.Lock()
	defer stateMu.Unlock()
	b, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(stateFile, b, 0644)
}

func loadAppSettings() (AppSettings, error) {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	if settingsFile == "" {
		return AppSettings{}, nil
	}
	data, err := os.ReadFile(settingsFile)
	if os.IsNotExist(err) {
		return AppSettings{}, nil
	}
	if err != nil {
		return AppSettings{}, err
	}
	var settings AppSettings
	if err := json.Unmarshal(data, &settings); err != nil {
		return AppSettings{}, err
	}
	settings.ChaosApiTokenPath = strings.TrimSpace(settings.ChaosApiTokenPath)
	return settings, nil
}

func saveAppSettings(settings AppSettings) error {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	if settingsFile == "" {
		return nil
	}
	settings.ChaosApiTokenPath = strings.TrimSpace(settings.ChaosApiTokenPath)
	b, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(settingsFile, b, 0644)
}
