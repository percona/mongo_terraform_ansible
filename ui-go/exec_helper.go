package main

import "os/exec"

// execCommand creates an exec.Cmd. This wrapper lets the rest of main.go
// avoid importing os/exec directly.
func execCommand(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}
