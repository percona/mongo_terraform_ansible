package main

import (
	"encoding/json"
	"os"
	"regexp"
	"sync"
)

var envIDRe = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,40}$`)

var stateMu sync.Mutex

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
