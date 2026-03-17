package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const sshConfigBeginFmt = "# === percona-sandbox:%s BEGIN ==="
const sshConfigEndFmt = "# === percona-sandbox:%s END ==="

// sshConfigPath returns the path to the user's SSH config file.
func sshConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".ssh", "config")
}

// updateDockerSSHConfig writes (or replaces) an SSH config block for the given
// Docker environment. Each container gets a Host stanza with its IP address so
// that `ssh <container-name>` resolves correctly from the local machine.
// Containers with an unknown/empty IP ("—") are skipped.
func updateDockerSSHConfig(envID string, hosts []HostInfo) {
	path := sshConfigPath()
	if path == "" {
		return
	}

	// Build the block content.
	var block strings.Builder
	block.WriteString(fmt.Sprintf(sshConfigBeginFmt, envID) + "\n")
	for _, h := range hosts {
		if h.IP == "" || h.IP == "—" {
			continue
		}
		block.WriteString(fmt.Sprintf("Host %s\n", h.Name))
		block.WriteString(fmt.Sprintf("    HostName %s\n", h.IP))
		block.WriteString("    User root\n")
		block.WriteString("    StrictHostKeyChecking no\n")
		block.WriteString("    UserKnownHostsFile /dev/null\n")
	}
	block.WriteString(fmt.Sprintf(sshConfigEndFmt, envID) + "\n")

	// Read existing config, replace our block (or append).
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return
	}

	beginMarker := fmt.Sprintf(sshConfigBeginFmt, envID)
	endMarker := fmt.Sprintf(sshConfigEndFmt, envID)

	updated := replaceSSHBlock(string(existing), beginMarker, endMarker, block.String())

	// Ensure the .ssh directory exists.
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return
	}
	os.WriteFile(path, []byte(updated), 0600)
}

// removeDockerSSHConfig removes the SSH config block for the given environment.
func removeDockerSSHConfig(envID string) {
	path := sshConfigPath()
	if path == "" {
		return
	}
	existing, err := os.ReadFile(path)
	if err != nil {
		return
	}
	beginMarker := fmt.Sprintf(sshConfigBeginFmt, envID)
	endMarker := fmt.Sprintf(sshConfigEndFmt, envID)
	updated := replaceSSHBlock(string(existing), beginMarker, endMarker, "")
	os.WriteFile(path, []byte(updated), 0600)
}

// replaceSSHBlock replaces (or inserts/removes) a marked block in sshConfig.
// If newBlock is empty the entire block is removed.
func replaceSSHBlock(sshConfig, beginMarker, endMarker, newBlock string) string {
	lines := strings.Split(sshConfig, "\n")
	var out []string
	inside := false
	found := false
	for _, line := range lines {
		if strings.TrimSpace(line) == beginMarker {
			inside = true
			found = true
			if newBlock != "" {
				out = append(out, strings.TrimRight(newBlock, "\n"))
			}
			continue
		}
		if inside {
			if strings.TrimSpace(line) == endMarker {
				inside = false
			}
			continue
		}
		out = append(out, line)
	}
	if !found && newBlock != "" {
		// Append the new block.
		if len(out) > 0 && out[len(out)-1] != "" {
			out = append(out, "")
		}
		out = append(out, strings.TrimRight(newBlock, "\n"))
	}
	result := strings.Join(out, "\n")
	// Ensure file ends with a newline.
	if !strings.HasSuffix(result, "\n") {
		result += "\n"
	}
	return result
}
