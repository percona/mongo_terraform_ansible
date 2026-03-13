package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// jobPIDs maps jobID → *os.Process for cancellation support.
var jobPIDs sync.Map

func jobLogPath(jobID string) string    { return filepath.Join(jobsDir, jobID+".log") }
func jobStatusPath(jobID string) string { return filepath.Join(jobsDir, jobID+".status") }

// secureID returns a cryptographically random hex string of length 2*n bytes.
func secureID(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// Extremely unlikely; fall back to timestamp-based ID.
		return fmt.Sprintf("%x", time.Now().UnixNano())[:n*2]
	}
	return hex.EncodeToString(b)
}

// startJob runs cmd in a goroutine, writing output to a log file.
// onComplete is called with the final status string when the job finishes.
func startJob(cmd []string, cwd string, extraEnv map[string]string, onComplete func(string)) string {
	jobID := secureID(8) // 16 hex chars of crypto random – not guessable
	go runJob(jobID, cmd, cwd, extraEnv, onComplete)
	return jobID
}

func runJob(jobID string, cmd []string, cwd string, extraEnv map[string]string, onComplete func(string)) {
	startTime := time.Now()
	statusPath := jobStatusPath(jobID)
	logPath := jobLogPath(jobID)

	if err := os.WriteFile(statusPath, []byte("running"), 0644); err != nil {
		slog.Error("job status write failed", "job", jobID, "err", err)
		return
	}

	// Build command string for display
	var cmdDisplay string
	if len(cmd) == 3 && cmd[0] == "bash" && cmd[1] == "-c" {
		cmdDisplay = cmd[2]
	} else {
		cmdDisplay = strings.Join(cmd, " ")
	}
	slog.Info("job started", "job", jobID, "cwd", cwd, "cmd", cmdDisplay)

	logFile, err := os.Create(logPath)
	if err != nil {
		slog.Error("job log create failed", "job", jobID, "err", err)
		os.WriteFile(statusPath, []byte("error"), 0644)
		return
	}

	// Write the command at the top so it's visible in the terminal output.
	fmt.Fprintf(logFile, "$ %s\n# cwd: %s\n\n", cmdDisplay, cwd)
	logFile.Sync()

	// Build exec.Cmd
	execCmd := &struct {
		name string
		args []string
		env  []string
	}{
		name: cmd[0],
		args: cmd[1:],
	}
	// Build environment
	for _, e := range os.Environ() {
		execCmd.env = append(execCmd.env, e)
	}
	for k, v := range extraEnv {
		execCmd.env = append(execCmd.env, k+"="+v)
	}

	finalStatus := runProcess(jobID, execCmd.name, execCmd.args, execCmd.env, cwd, logFile)

	// Append elapsed time to the log so it is visible in the terminal output.
	elapsed := time.Since(startTime)
	totalSecs := int(elapsed.Seconds())
	mins := totalSecs / 60
	secs := totalSecs % 60
	fmt.Fprintf(logFile, "\n# Elapsed: %dm %ds\n", mins, secs)
	logFile.Sync()
	logFile.Close()

	if err := os.WriteFile(statusPath, []byte(finalStatus), 0644); err != nil {
		slog.Error("job status write failed", "job", jobID, "err", err)
	}
	slog.Info("job finished", "job", jobID, "status", finalStatus)

	if onComplete != nil {
		onComplete(finalStatus)
	}
}

// runProcess executes the given command and pipes stdout+stderr to logFile.
// Returns "success", "failed:N", or "error".
func runProcess(jobID string, name string, args []string, envVars []string, cwd string, logFile *os.File) string {
	proc := execCommand(name, args...)
	proc.Dir = cwd
	proc.Env = envVars
	proc.Stdout = logFile
	proc.Stderr = logFile
	if err := proc.Start(); err != nil {
		fmt.Fprintf(logFile, "\nError starting process: %v\n", err)
		return "error"
	}
	jobPIDs.Store(jobID, proc.Process)
	defer jobPIDs.Delete(jobID)
	if err := proc.Wait(); err != nil {
		return fmt.Sprintf("failed:%d", proc.ProcessState.ExitCode())
	}
	return "success"
}

// cancelJob looks up the running process for jobID and kills it.
// Returns true if the process was found and killed, false otherwise.
func cancelJob(jobID string) bool {
	val, ok := jobPIDs.Load(jobID)
	if !ok {
		return false
	}
	proc := val.(*os.Process)
	if err := proc.Kill(); err != nil {
		slog.Warn("cancel job kill failed", "job", jobID, "err", err)
	}
	return true
}

// POST /api/job/{job_id}/cancel
func jobCancelHandler(w http.ResponseWriter, r *http.Request) {
	jobID := r.PathValue("job_id")
	cancelled := cancelJob(jobID)
	writeJSON(w, 200, map[string]bool{"cancelled": cancelled})
}
