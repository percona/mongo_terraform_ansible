package main

import (
	"strings"
)

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
