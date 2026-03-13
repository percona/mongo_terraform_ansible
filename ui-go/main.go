// main.go – MongoDB Deploy UI (Go rewrite)
// Drop-in replacement for ui/app.py, runs as a standalone binary.
// Usage: cd ui-go && go run . (or build with: go build -o mongodeploy .)
package main

import (
"encoding/json"
"html/template"
"log"
"log/slog"
"net/http"
"os"
"path/filepath"
"regexp"
"strings"
"unicode"
)

// ─── Constants ───────────────────────────────────────────────────────────────

var platforms = []string{"aws", "gcp", "azure", "docker"}

var ansiRe = regexp.MustCompile(`\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])`)
var safeFilenameRe = regexp.MustCompile(`[^a-zA-Z0-9._-]`)

// defaultPSMDBVersions is used as a fallback when the Percona repo is unreachable.
var defaultPSMDBVersions = []string{"psmdb-80", "psmdb-70", "psmdb-60", "psmdb-50", "psmdb-44", "psmdb-42", "psmdb-40", "psmdb-36"}

// defaultPBMReleases is used as a fallback when the Percona repo is unreachable.
var defaultPBMReleases = []string{"pbm-30", "pbm-20", "pbm-12", "pbm-11", "pbm-10"}

// ─── Globals ──────────────────────────────────────────────────────────────────

var (
// Application directories (set in main)
baseDir      string
terraformDir string
ansibleDir   string
stateFile    string
jobsDir      string
tmplDir      string
staticDir    string
)

// ─── Template function map ────────────────────────────────────────────────────

var funcMap = template.FuncMap{
// Emit a Go value as a JS-safe JSON literal.
"json": func(v interface{}) (template.JS, error) {
b, err := json.Marshal(v)
return template.JS(b), err
},
"upper": strings.ToUpper,
// Return s if non-empty, otherwise def.
"strDefault": func(s, def string) string {
if s == "" {
return def
}
return s
},
// Return n if non-zero, otherwise def.
"intDefault": func(n, def int) int {
if n == 0 {
return def
}
return n
},
// Return *b if non-nil, otherwise def.
"boolDefault": func(b *bool, def bool) bool {
if b == nil {
return def
}
return *b
},
// Return true when b is explicitly set to false.
"ptrBoolFalse": func(b *bool) bool {
return b != nil && !*b
},
// True if the stored image value matches the given tag (with or without prefix).
"tagSelected": func(stored, prefix, tag string) bool {
if stored == "" {
return tag == "latest"
}
return stored == prefix+":"+tag || stored == tag
},
// Extract the version tag from a Docker image string (the part after the last
// colon).  Returns "—" for an empty input.
"imageTag": func(image string) string {
if image == "" {
return "—"
}
if idx := strings.LastIndex(image, ":"); idx >= 0 && idx < len(image)-1 {
return image[idx+1:]
}
return image
},
// dockerPsmdbImage returns the first PSMDB container image configured for a
// Docker environment (checked across all replsets, then clusters).
"dockerPsmdbImage": func(cfg Config) string {
for _, rc := range cfg.Replsets {
if rc.PsmdbImage != "" {
return rc.PsmdbImage
}
}
for _, cc := range cfg.Clusters {
if cc.PsmdbImage != "" {
return cc.PsmdbImage
}
}
return ""
},
// dockerPbmImage returns the first PBM container image configured for a
// Docker environment (checked across all replsets, then clusters).
"dockerPbmImage": func(cfg Config) string {
for _, rc := range cfg.Replsets {
if rc.PbmImage != "" {
return rc.PbmImage
}
}
for _, cc := range cfg.Clusters {
if cc.PbmImage != "" {
return cc.PbmImage
}
}
return ""
},
// dockerPmmImage returns the first PMM server container image configured for
// a Docker environment.
"dockerPmmImage": func(cfg Config) string {
for _, ns := range cfg.PmmServers {
if ns.PmmServerImage != "" {
return ns.PmmServerImage
}
}
return ""
},
// title-cases a status string, with human-friendly overrides for action
// statuses that differ from the button label (e.g. "configure" → "Install").
"statusLabel": func(s string) string {
switch s {
case "configure_in_progress":
return "Installing…"
case "configure_failed":
return "Install Failed"
}
words := strings.ReplaceAll(s, "_", " ")
var out []rune
capNext := true
for _, r := range words {
if unicode.IsSpace(r) {
capNext = true
out = append(out, r)
} else if capNext {
out = append(out, unicode.ToUpper(r))
capNext = false
} else {
out = append(out, r)
}
}
return string(out)
},
// Returns the CSS class suffix for a status string.
"statusClass": func(s string) string {
if idx := strings.Index(s, ":"); idx >= 0 {
s = s[:idx]
}
return s
},
"len": func(v interface{}) int {
switch t := v.(type) {
case map[string]ClusterConfig:
return len(t)
case map[string]ReplsetConfig:
return len(t)
case []NamedCluster:
return len(t)
case []NamedReplset:
return len(t)
}
return 0
},
}

// ─── renderPage ───────────────────────────────────────────────────────────────

func renderPage(w http.ResponseWriter, page string, data interface{}) {
t, err := template.New("").Funcs(funcMap).ParseFiles(
filepath.Join(tmplDir, "layout.html"),
filepath.Join(tmplDir, page+".html"),
)
if err != nil {
http.Error(w, "Template error: "+err.Error(), http.StatusInternalServerError)
return
}
w.Header().Set("Content-Type", "text/html; charset=utf-8")
if err := t.ExecuteTemplate(w, "layout", data); err != nil {
slog.Error("template execute", "page", page, "err", err)
}
}

// ─── JSON helpers ─────────────────────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
b, _ := json.Marshal(v)
w.Header().Set("Content-Type", "application/json")
w.WriteHeader(status)
w.Write(b)
}

func jsonError(w http.ResponseWriter, status int, msg string) {
writeJSON(w, status, map[string]string{"error": msg})
}

// ─── Small value helpers ─────────────────────────────────────────────────────

func strDefault(s, def string) string {
if s == "" {
return def
}
return s
}

func intDefault(n, def int) int {
if n == 0 {
return def
}
return n
}

// ─── ANSI stripping ───────────────────────────────────────────────────────────

func stripAnsi(s string) string {
s = ansiRe.ReplaceAllString(s, "")
s = strings.ReplaceAll(s, "\r", "")
return s
}

// ─── Shell helpers ────────────────────────────────────────────────────────────

// shellQuote wraps s in single-quotes, escaping any single-quotes inside.
func shellQuote(s string) string {
return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// sanitiseShellArg removes characters that are not safe for direct shell interpolation.
func sanitiseShellArg(s string) string {
var b strings.Builder
for _, r := range s {
if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
b.WriteRune(r)
}
}
return b.String()
}

// validPlatform reports whether p is a known platform name.
func validPlatform(p string) bool {
for _, pl := range platforms {
if p == pl {
return true
}
}
return false
}

// ─── Main ─────────────────────────────────────────────────────────────────────

func main() {
cwd, err := os.Getwd()
if err != nil {
log.Fatal(err)
}
if override := os.Getenv("UI_BASE_DIR"); override != "" {
baseDir = override
} else {
baseDir = cwd
}

terraformDir = filepath.Join(baseDir, "..", "terraform")
ansibleDir = filepath.Join(baseDir, "..", "ansible")
stateFile = filepath.Join(baseDir, "environments.json")
jobsDir = filepath.Join(baseDir, "jobs")
tmplDir = filepath.Join(baseDir, "templates")
staticDir = filepath.Join(baseDir, "static")

if err := os.MkdirAll(jobsDir, 0755); err != nil {
log.Fatal("cannot create jobs dir:", err)
}

slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})))
slog.Info("starting PSMDB Sandbox", "baseDir", baseDir)

go prefetchVersions()

mux := http.NewServeMux()

// Pages
mux.HandleFunc("GET /", indexHandler)
mux.HandleFunc("GET /new", newEnvironmentHandler)
mux.HandleFunc("GET /configure/{platform}", configureHandler)
mux.HandleFunc("GET /environment/{env_id}", environmentHandler)

// API
mux.HandleFunc("GET /api/versions", apiVersionsHandler)
mux.HandleFunc("GET /api/regions/{platform}", apiRegionsHandler)
mux.HandleFunc("GET /api/images/{platform}", apiImagesHandler)
mux.HandleFunc("POST /api/upload-ssh-key/{platform}", apiUploadSSHKeyHandler)
mux.HandleFunc("POST /api/environment", saveEnvironmentHandler)
mux.HandleFunc("DELETE /api/environment/{env_id}", deleteEnvironmentHandler)
mux.HandleFunc("DELETE /api/environments/deleted", purgeDeletedEnvironmentsHandler)
mux.HandleFunc("GET /api/environment/{env_id}/tfvars", getTfvarsHandler)
mux.HandleFunc("GET /api/environment/{env_id}/inventory", getInventoryHandler)
mux.HandleFunc("GET /api/environment/{env_id}/hosts", getHostsHandler)
mux.HandleFunc("GET /api/environment/{env_id}/history", envHistoryHandler)
mux.HandleFunc("GET /api/environment/{env_id}/status", envStatusHandler)
mux.HandleFunc("POST /api/environment/{env_id}/action", environmentActionHandler)
mux.HandleFunc("GET /api/job/{job_id}/status", jobStatusHandler)
mux.HandleFunc("GET /api/job/{job_id}/stream", jobStreamHandler)
mux.HandleFunc("GET /api/job/{job_id}/log", jobLogHandler)
mux.HandleFunc("POST /api/job/{job_id}/cancel", jobCancelHandler)

// Static files
mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServer(http.Dir(staticDir))))

addr := ":5001"
if p := os.Getenv("PORT"); p != "" {
addr = ":" + p
}
host := "127.0.0.1"
if os.Getenv("UI_HOST") != "" {
host = os.Getenv("UI_HOST")
}

srv := &http.Server{
Addr:    host + addr,
Handler: mux,
}
slog.Info("listening", "addr", "http://"+host+addr)
if err := srv.ListenAndServe(); err != nil {
log.Fatal(err)
}
}
