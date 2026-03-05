// main.go – MongoDB Deploy UI (Go rewrite)
// Drop-in replacement for ui/app.py, runs as a standalone binary.
// Usage: cd ui-go && go run main.go   (or build with: go build -o mongodeploy .)
package main

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

// ─── Constants ───────────────────────────────────────────────────────────────

var platforms = []string{"aws", "gcp", "azure", "docker"}

var envIDRe = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,40}$`)
var ansiRe = regexp.MustCompile(`\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])`)

const cacheTTL = 5 * time.Minute

// ─── Type definitions ─────────────────────────────────────────────────────────

// ClusterConfig maps to the Terraform "clusters" map object type.
type ClusterConfig struct {
	EnvTag            string `json:"env_tag"`
	ConfigsvrCount    int    `json:"configsvr_count"`
	ShardCount        int    `json:"shard_count"`
	ShardsvrReplicas  int    `json:"shardsvr_replicas"`
	ArbitersPerReplset int   `json:"arbiters_per_replset"`
	MongosCount       int    `json:"mongos_count"`
	// Docker-only
	PsmdbImage     string `json:"psmdb_image,omitempty"`
	PbmImage       string `json:"pbm_image,omitempty"`
	PmmClientImage string `json:"pmm_client_image,omitempty"`
	EnablePmm      bool   `json:"enable_pmm,omitempty"`
	EnablePbm      bool   `json:"enable_pbm,omitempty"`
	BindToLocalhost bool  `json:"bind_to_localhost,omitempty"`
}

// ReplsetConfig maps to the Terraform "replsets" map object type.
type ReplsetConfig struct {
	EnvTag             string `json:"env_tag"`
	DataNodesPerReplset int   `json:"data_nodes_per_replset"`
	ArbitersPerReplset  int   `json:"arbiters_per_replset"`
	// Docker-only
	PsmdbImage     string `json:"psmdb_image,omitempty"`
	PbmImage       string `json:"pbm_image,omitempty"`
	PmmClientImage string `json:"pmm_client_image,omitempty"`
	EnablePmm      bool   `json:"enable_pmm,omitempty"`
	EnablePbm      bool   `json:"enable_pbm,omitempty"`
	BindToLocalhost bool  `json:"bind_to_localhost,omitempty"`
}

// PmmServerConfig maps to the Docker pmm_servers map object type.
type PmmServerConfig struct {
	EnvTag         string `json:"env_tag"`
	PmmServerImage string `json:"pmm_server_image,omitempty"`
	PmmPort        int    `json:"pmm_port,omitempty"`
	PmmServerUser  string `json:"pmm_server_user,omitempty"`
	PmmServerPwd   string `json:"pmm_server_pwd,omitempty"`
	BindToLocalhost bool  `json:"bind_to_localhost,omitempty"`
}

// MinioServerConfig maps to the Docker minio_servers map object type.
type MinioServerConfig struct {
	EnvTag           string `json:"env_tag"`
	MinioImage       string `json:"minio_image,omitempty"`
	MinioPort        int    `json:"minio_port,omitempty"`
	MinioConsolePort int    `json:"minio_console_port,omitempty"`
	MinioAccessKey   string `json:"minio_access_key,omitempty"`
	MinioSecretKey   string `json:"minio_secret_key,omitempty"`
	BucketName       string `json:"bucket_name,omitempty"`
	BackupRetention  int    `json:"backup_retention,omitempty"`
	BindToLocalhost  bool   `json:"bind_to_localhost,omitempty"`
}

// LdapServerConfig maps to the Docker ldap_servers map object type.
type LdapServerConfig struct {
	EnvTag            string `json:"env_tag"`
	LdapImage         string `json:"ldap_image,omitempty"`
	LdapPort          int    `json:"ldap_port,omitempty"`
	LdapDomain        string `json:"ldap_domain,omitempty"`
	LdapAdminPassword string `json:"ldap_admin_password,omitempty"`
	BindToLocalhost   bool   `json:"bind_to_localhost,omitempty"`
}

// Config holds all user-configurable settings for an environment.
type Config struct {
	// General
	Prefix      string `json:"prefix"`
	MongoRelease string `json:"mongo_release,omitempty"`

	// Cloud credentials / settings
	ProjectID       string `json:"project_id,omitempty"`
	Region          string `json:"region,omitempty"`
	Location        string `json:"location,omitempty"`
	SubnetCIDR      string `json:"subnet_cidr,omitempty"`
	SubnetCount     int    `json:"subnet_count,omitempty"`
	SourceRanges    string `json:"source_ranges,omitempty"`
	MySSHUser       string `json:"my_ssh_user,omitempty"`
	SSHPublicKeyPath string `json:"ssh_public_key_path,omitempty"`
	DefaultKeyPair  string `json:"default_key_pair,omitempty"`
	EnableSSHGateway bool  `json:"enable_ssh_gateway,omitempty"`
	SSHGatewayName  string `json:"ssh_gateway_name,omitempty"`
	PortToForward   string `json:"port_to_forward,omitempty"`
	UseSpotInstances bool  `json:"use_spot_instances,omitempty"`

	// PMM (cloud)
	EnablePmm    *bool  `json:"enable_pmm,omitempty"`
	PmmType      string `json:"pmm_type,omitempty"`
	PmmVolumeSize int   `json:"pmm_volume_size,omitempty"`
	PmmPort      int    `json:"pmm_port,omitempty"`
	PmmImage     string `json:"pmm_image,omitempty"`
	PmmDiskType  string `json:"pmm_disk_type,omitempty"`

	// Backup
	DefaultBucketName string `json:"default_bucket_name,omitempty"`
	BackupRetention   int    `json:"backup_retention,omitempty"`

	// Per-component instance types and disk sizes (cloud platforms only).
	// These correspond to top-level Terraform variables that apply to all
	// clusters and replica sets in the environment.
	ShardsvrType        string `json:"shardsvr_type,omitempty"`
	ShardsvrVolumeSize  int    `json:"shardsvr_volume_size,omitempty"`
	ConfigsvrType       string `json:"configsvr_type,omitempty"`
	ConfigsvrVolumeSize int    `json:"configsvr_volume_size,omitempty"`
	MongosType          string `json:"mongos_type,omitempty"`
	ArbiterType         string `json:"arbiter_type,omitempty"`
	ReplsetSvrType      string `json:"replsetsvr_type,omitempty"`
	ReplsetSvrVolumeSize int   `json:"replsetsvr_volume_size,omitempty"`
	DataDiskType        string `json:"data_disk_type,omitempty"`

	// Docker networking
	NetworkName string `json:"network_name,omitempty"`

	// Topology
	Clusters map[string]ClusterConfig  `json:"clusters"`
	Replsets map[string]ReplsetConfig  `json:"replsets"`

	// Docker-specific service servers
	PmmServers   map[string]PmmServerConfig   `json:"pmm_servers,omitempty"`
	MinioServers map[string]MinioServerConfig `json:"minio_servers,omitempty"`
	LdapServers  map[string]LdapServerConfig  `json:"ldap_servers,omitempty"`
}

// Environment is one record in the state file.
type Environment struct {
	Platform  string    `json:"platform"`
	Config    Config    `json:"config"`
	Status    string    `json:"status"`
	CreatedAt string    `json:"created_at"`
	UpdatedAt string    `json:"updated_at"`
	LastJobID string    `json:"last_job_id,omitempty"`
}

// ─── Named pair helpers (sorted map iteration for templates) ──────────────────

type NamedCluster struct {
	Name   string
	Config ClusterConfig
}
type NamedReplset struct {
	Name   string
	Config ReplsetConfig
}
type NamedPmmServer struct {
	Name   string
	Config PmmServerConfig
}
type NamedMinioServer struct {
	Name   string
	Config MinioServerConfig
}
type NamedLdapServer struct {
	Name   string
	Config LdapServerConfig
}

func sortedClusters(m map[string]ClusterConfig) []NamedCluster {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]NamedCluster, 0, len(keys))
	for _, k := range keys {
		out = append(out, NamedCluster{k, m[k]})
	}
	return out
}

func sortedReplsets(m map[string]ReplsetConfig) []NamedReplset {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]NamedReplset, 0, len(keys))
	for _, k := range keys {
		out = append(out, NamedReplset{k, m[k]})
	}
	return out
}

func sortedPmmServers(m map[string]PmmServerConfig) []NamedPmmServer {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]NamedPmmServer, 0, len(keys))
	for _, k := range keys {
		out = append(out, NamedPmmServer{k, m[k]})
	}
	return out
}

func sortedMinioServers(m map[string]MinioServerConfig) []NamedMinioServer {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]NamedMinioServer, 0, len(keys))
	for _, k := range keys {
		out = append(out, NamedMinioServer{k, m[k]})
	}
	return out
}

func sortedLdapServers(m map[string]LdapServerConfig) []NamedLdapServer {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]NamedLdapServer, 0, len(keys))
	for _, k := range keys {
		out = append(out, NamedLdapServer{k, m[k]})
	}
	return out
}

// ─── Template data structs ────────────────────────────────────────────────────

type EnvEntry struct {
	ID  string
	Env *Environment
}

type IndexData struct {
	Environments []EnvEntry
}

type NewEnvData struct {
	Platforms []string
}

type ConfigureData struct {
	Platform        string
	EnvID           string
	Config          Config // populated from existing or defaults
	PSMDBVersions   []string
	PMMImages       []string
	PSMDBImages     []string
	PBMImages       []string
	PMMClientImages []string
	// Pre-sorted for templates
	SortedClusters   []NamedCluster
	SortedReplsets   []NamedReplset
	SortedPmmServers []NamedPmmServer
	SortedMinio      []NamedMinioServer
	SortedLdap       []NamedLdapServer
}

type EnvironmentData struct {
	EnvID          string
	Env            *Environment
	SortedClusters []NamedCluster
	SortedReplsets []NamedReplset
}

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

	// State mutex
	stateMu sync.Mutex

	// Version/image cache
	cacheMu  sync.RWMutex
	imgCache = map[string]cacheEntry{}
)

type cacheEntry struct {
	data interface{}
	ts   time.Time
}

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
	// Return *b if non-nil, otherwise def.  Used in templates to safely
	// dereference optional bool pointers (e.g. EnablePmm *bool).
	"boolDefault": func(b *bool, def bool) bool {
		if b == nil {
			return def
		}
		return *b
	},
	// True if the stored image value matches the given tag (with or without prefix).
	"tagSelected": func(stored, prefix, tag string) bool {
		if stored == "" {
			return tag == "latest"
		}
		return stored == prefix+":"+tag || stored == tag
	},
	// title-cases a status string (e.g. "deploy_in_progress" → "Deploy In Progress").
	"statusLabel": func(s string) string {
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
	// Strip "in_progress" suffix and colon-suffix for CSS class names.
	"statusClass": func(s string) string {
		s = strings.TrimSuffix(s, "_in_progress")
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

// ─── State management ─────────────────────────────────────────────────────────

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

// ─── Version / image fetching ────────────────────────────────────────────────

func cacheGet(key string) (interface{}, bool) {
	cacheMu.RLock()
	defer cacheMu.RUnlock()
	e, ok := imgCache[key]
	if !ok || time.Since(e.ts) > cacheTTL {
		return nil, false
	}
	return e.data, true
}

func cacheSet(key string, data interface{}) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	imgCache[key] = cacheEntry{data, time.Now()}
}

func getDockerHubTags(namespace, repo string, limit int) []string {
	key := "dh:" + namespace + "/" + repo
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	url := fmt.Sprintf("https://hub.docker.com/v2/repositories/%s/%s/tags/?page_size=%d&ordering=last_updated", namespace, repo, limit)
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		slog.Warn("docker hub tags fetch failed", "repo", namespace+"/"+repo, "err", err)
		cacheSet(key, []string{})
		return []string{}
	}
	defer resp.Body.Close()
	var result struct {
		Results []struct {
			Name string `json:"name"`
		} `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		slog.Warn("docker hub tags decode failed", "repo", namespace+"/"+repo, "err", err)
		cacheSet(key, []string{})
		return []string{}
	}
	tags := make([]string, 0, len(result.Results))
	for _, r := range result.Results {
		tags = append(tags, r.Name)
	}
	slog.Info("fetched docker hub tags", "repo", namespace+"/"+repo, "count", len(tags))
	cacheSet(key, tags)
	return tags
}

func getPSMDBVersions() []string {
	const key = "psmdb_versions"
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	client := &http.Client{Timeout: 6 * time.Second}
	resp, err := client.Get("https://repo.percona.com/percona/yum/release/")
	var versions []string
	if err == nil && resp.StatusCode == 200 {
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		re := regexp.MustCompile(`psmdb-\d+`)
		found := re.FindAllString(string(body), -1)
		seen := map[string]bool{}
		for _, v := range found {
			if !seen[v] {
				seen[v] = true
				versions = append(versions, v)
			}
		}
		// Sort descending
		sort.Slice(versions, func(i, j int) bool { return versions[i] > versions[j] })
		slog.Info("fetched PSMDB versions", "count", len(versions))
	} else {
		slog.Warn("psmdb versions fetch failed", "err", err)
	}
	cacheSet(key, versions)
	return versions
}

func getPMMServerImages() []string {
	tags := getDockerHubTags("percona", "pmm-server", 30)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

func getPSMDBImages() []string {
	tags := getDockerHubTags("percona", "percona-server-mongodb", 30)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

func getPBMImages() []string {
	tags := getDockerHubTags("percona", "percona-backup-mongodb", 20)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

func getPMMClientImages() []string {
	tags := getDockerHubTags("percona", "pmm-client", 20)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

// prefetchVersions warms all image/version caches at startup in a goroutine.
func prefetchVersions() {
	slog.Info("prefetching container image tags and PSMDB versions…")
	getPSMDBVersions()
	getPMMServerImages()
	getPSMDBImages()
	getPBMImages()
	getPMMClientImages()
	slog.Info("version prefetch complete")
}

// ─── tfvars generation ────────────────────────────────────────────────────────

// tfvarsPath returns the path for the env's tfvars file.
func tfvarsPath(envID, platform string) string {
	return filepath.Join(terraformDir, platform, envID+".tfvars")
}

// formatHCLVal formats a Go value as an HCL literal.
func formatHCLVal(v interface{}) string {
	switch t := v.(type) {
	case bool:
		if t {
			return "true"
		}
		return "false"
	case int:
		return strconv.Itoa(t)
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case string:
		return fmt.Sprintf("%q", t)
	default:
		return fmt.Sprintf("%q", fmt.Sprintf("%v", t))
	}
}

// writeTfvars generates the <env_id>.tfvars file in the platform's terraform directory.
func writeTfvars(envID, platform string, cfg Config) error {
	dir := filepath.Join(terraformDir, platform)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	path := tfvarsPath(envID, platform)

	var b strings.Builder

	write := func(line string) { b.WriteString(line); b.WriteByte('\n') }
	writeVar := func(name string, val interface{}) {
		write(fmt.Sprintf("%s = %s", name, formatHCLVal(val)))
	}
	writeOptStr := func(name, val string) {
		if val != "" {
			writeVar(name, val)
		}
	}
	writeOptInt := func(name string, val int) {
		if val != 0 {
			writeVar(name, val)
		}
	}
	writeOptBool := func(name string, val bool) {
		writeVar(name, val)
	}

	// General
	if cfg.Prefix != "" {
		writeVar("prefix", cfg.Prefix)
	}

	if platform != "docker" {
		// Cloud-only simple vars
		writeOptStr("project_id", cfg.ProjectID)
		writeOptStr("region", cfg.Region)
		writeOptStr("location", cfg.Location)
		writeOptStr("subnet_cidr", cfg.SubnetCIDR)
		writeOptStr("source_ranges", cfg.SourceRanges)
		writeOptStr("my_ssh_user", cfg.MySSHUser)
		writeOptStr("ssh_public_key_path", cfg.SSHPublicKeyPath)
		writeOptStr("default_key_pair", cfg.DefaultKeyPair)
		if cfg.EnableSSHGateway {
			writeOptBool("enable_ssh_gateway", cfg.EnableSSHGateway)
		}
		writeOptStr("ssh_gateway_name", cfg.SSHGatewayName)
		writeOptStr("port_to_forward", cfg.PortToForward)
		if cfg.UseSpotInstances {
			writeOptBool("use_spot_instances", cfg.UseSpotInstances)
		}
		writeOptInt("subnet_count", cfg.SubnetCount)

		// PMM
		writeOptStr("pmm_type", cfg.PmmType)
		writeOptInt("pmm_volume_size", cfg.PmmVolumeSize)
		writeOptInt("pmm_port", cfg.PmmPort)
		writeOptStr("pmm_disk_type", cfg.PmmDiskType)
		// Write enable_pmm only when explicitly set; terraform default is true.
		if cfg.EnablePmm != nil {
			writeVar("enable_pmm", *cfg.EnablePmm)
		}

		// Backup
		writeOptStr("default_bucket_name", cfg.DefaultBucketName)
		writeOptStr("backup_retention", func() string {
			if cfg.BackupRetention != 0 {
				return strconv.Itoa(cfg.BackupRetention)
			}
			return ""
		}())

		// Per-component instance types and disk sizes (new per-component customisation)
		writeOptStr("data_disk_type", cfg.DataDiskType)
		writeOptStr("shardsvr_type", cfg.ShardsvrType)
		writeOptInt("shardsvr_volume_size", cfg.ShardsvrVolumeSize)
		writeOptStr("configsvr_type", cfg.ConfigsvrType)
		writeOptInt("configsvr_volume_size", cfg.ConfigsvrVolumeSize)
		writeOptStr("mongos_type", cfg.MongosType)
		writeOptStr("arbiter_type", cfg.ArbiterType)
		writeOptStr("replsetsvr_type", cfg.ReplsetSvrType)
		writeOptInt("replsetsvr_volume_size", cfg.ReplsetSvrVolumeSize)
	} else {
		// Docker-only
		writeOptStr("network_name", cfg.NetworkName)
	}

	// ── clusters – always write (even as empty map) to override Terraform defaults ──
	write("")
	clusters := cfg.Clusters
	if len(clusters) == 0 {
		write("clusters = {}")
	} else {
		write("clusters = {")
		for _, nc := range sortedClusters(clusters) {
			name, c := nc.Name, nc.Config
			write(fmt.Sprintf("  %q = {", name))
			write(fmt.Sprintf("    env_tag = %s", formatHCLVal(strDefault(c.EnvTag, "test"))))
			write(fmt.Sprintf("    configsvr_count = %s", formatHCLVal(intDefault(c.ConfigsvrCount, 3))))
			write(fmt.Sprintf("    shard_count = %s", formatHCLVal(intDefault(c.ShardCount, 2))))
			write(fmt.Sprintf("    shardsvr_replicas = %s", formatHCLVal(intDefault(c.ShardsvrReplicas, 2))))
			write(fmt.Sprintf("    arbiters_per_replset = %s", formatHCLVal(intDefault(c.ArbitersPerReplset, 1))))
			write(fmt.Sprintf("    mongos_count = %s", formatHCLVal(intDefault(c.MongosCount, 2))))
			if platform == "docker" {
				if c.PsmdbImage != "" {
					write(fmt.Sprintf("    psmdb_image = %s", formatHCLVal(c.PsmdbImage)))
				}
				if c.PbmImage != "" {
					write(fmt.Sprintf("    pbm_image = %s", formatHCLVal(c.PbmImage)))
				}
				if c.PmmClientImage != "" {
					write(fmt.Sprintf("    pmm_client_image = %s", formatHCLVal(c.PmmClientImage)))
				}
				write(fmt.Sprintf("    enable_pmm = %s", formatHCLVal(c.EnablePmm)))
				write(fmt.Sprintf("    enable_pbm = %s", formatHCLVal(c.EnablePbm)))
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(c.BindToLocalhost)))
			}
			write("  }")
		}
		write("}")
	}

	// ── replsets – always write (even as empty map) to override Terraform defaults ──
	write("")
	replsets := cfg.Replsets
	if len(replsets) == 0 {
		write("replsets = {}")
	} else {
		write("replsets = {")
		for _, nr := range sortedReplsets(replsets) {
			name, r := nr.Name, nr.Config
			write(fmt.Sprintf("  %q = {", name))
			write(fmt.Sprintf("    env_tag = %s", formatHCLVal(strDefault(r.EnvTag, "test"))))
			write(fmt.Sprintf("    data_nodes_per_replset = %s", formatHCLVal(intDefault(r.DataNodesPerReplset, 2))))
			write(fmt.Sprintf("    arbiters_per_replset = %s", formatHCLVal(intDefault(r.ArbitersPerReplset, 1))))
			if platform == "docker" {
				if r.PsmdbImage != "" {
					write(fmt.Sprintf("    psmdb_image = %s", formatHCLVal(r.PsmdbImage)))
				}
				if r.PbmImage != "" {
					write(fmt.Sprintf("    pbm_image = %s", formatHCLVal(r.PbmImage)))
				}
				if r.PmmClientImage != "" {
					write(fmt.Sprintf("    pmm_client_image = %s", formatHCLVal(r.PmmClientImage)))
				}
				write(fmt.Sprintf("    enable_pmm = %s", formatHCLVal(r.EnablePmm)))
				write(fmt.Sprintf("    enable_pbm = %s", formatHCLVal(r.EnablePbm)))
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(r.BindToLocalhost)))
			}
			write("  }")
		}
		write("}")
	}

	// ── Docker service blocks ─────────────────────────────────────────────────
	if platform == "docker" {
		if len(cfg.PmmServers) > 0 {
			write("")
			write("pmm_servers = {")
			for _, ns := range sortedPmmServers(cfg.PmmServers) {
				n, s := ns.Name, ns.Config
				write(fmt.Sprintf("  %q = {", n))
				write(fmt.Sprintf("    env_tag = %s", formatHCLVal(strDefault(s.EnvTag, "test"))))
				if s.PmmServerImage != "" {
					write(fmt.Sprintf("    pmm_server_image = %s", formatHCLVal(s.PmmServerImage)))
				}
				if s.PmmPort != 0 {
					write(fmt.Sprintf("    pmm_port = %s", formatHCLVal(s.PmmPort)))
				}
				if s.PmmServerUser != "" {
					write(fmt.Sprintf("    pmm_server_user = %s", formatHCLVal(s.PmmServerUser)))
				}
				if s.PmmServerPwd != "" {
					write(fmt.Sprintf("    pmm_server_pwd = %s", formatHCLVal(s.PmmServerPwd)))
				}
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(s.BindToLocalhost)))
				write("  }")
			}
			write("}")
		}

		if len(cfg.MinioServers) > 0 {
			write("")
			write("minio_servers = {")
			for _, ns := range sortedMinioServers(cfg.MinioServers) {
				n, s := ns.Name, ns.Config
				write(fmt.Sprintf("  %q = {", n))
				write(fmt.Sprintf("    env_tag = %s", formatHCLVal(strDefault(s.EnvTag, "test"))))
				if s.MinioImage != "" {
					write(fmt.Sprintf("    minio_image = %s", formatHCLVal(s.MinioImage)))
				}
				if s.MinioPort != 0 {
					write(fmt.Sprintf("    minio_port = %s", formatHCLVal(s.MinioPort)))
				}
				if s.MinioConsolePort != 0 {
					write(fmt.Sprintf("    minio_console_port = %s", formatHCLVal(s.MinioConsolePort)))
				}
				if s.MinioAccessKey != "" {
					write(fmt.Sprintf("    minio_access_key = %s", formatHCLVal(s.MinioAccessKey)))
				}
				if s.MinioSecretKey != "" {
					write(fmt.Sprintf("    minio_secret_key = %s", formatHCLVal(s.MinioSecretKey)))
				}
				if s.BucketName != "" {
					write(fmt.Sprintf("    bucket_name = %s", formatHCLVal(s.BucketName)))
				}
				if s.BackupRetention != 0 {
					write(fmt.Sprintf("    backup_retention = %s", formatHCLVal(s.BackupRetention)))
				}
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(s.BindToLocalhost)))
				write("  }")
			}
			write("}")
		}

		if len(cfg.LdapServers) > 0 {
			write("")
			write("ldap_servers = {")
			for _, ns := range sortedLdapServers(cfg.LdapServers) {
				n, s := ns.Name, ns.Config
				write(fmt.Sprintf("  %q = {", n))
				write(fmt.Sprintf("    env_tag = %s", formatHCLVal(strDefault(s.EnvTag, "test"))))
				if s.LdapImage != "" {
					write(fmt.Sprintf("    ldap_image = %s", formatHCLVal(s.LdapImage)))
				}
				if s.LdapPort != 0 {
					write(fmt.Sprintf("    ldap_port = %s", formatHCLVal(s.LdapPort)))
				}
				if s.LdapDomain != "" {
					write(fmt.Sprintf("    ldap_domain = %s", formatHCLVal(s.LdapDomain)))
				}
				if s.LdapAdminPassword != "" {
					write(fmt.Sprintf("    ldap_admin_password = %s", formatHCLVal(s.LdapAdminPassword)))
				}
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(s.BindToLocalhost)))
				write("  }")
			}
			write("}")
		}
	}

	if err := os.WriteFile(path, []byte(b.String()), 0644); err != nil {
		return err
	}
	slog.Info("wrote tfvars", "path", path)
	return nil
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

// ─── Job management ───────────────────────────────────────────────────────────

func jobLogPath(jobID string) string  { return filepath.Join(jobsDir, jobID+".log") }
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

	// Use os/exec via a helper that avoids importing os/exec at top level
	finalStatus := runProcess(execCmd.name, execCmd.args, execCmd.env, cwd, logFile)
	logFile.Close()

	if err := os.WriteFile(statusPath, []byte(finalStatus), 0644); err != nil {
		slog.Error("job status write failed", "job", jobID, "err", err)
	}
	slog.Info("job finished", "job", jobID, "status", finalStatus)

	if onComplete != nil {
		onComplete(finalStatus)
	}
}

// ─── Process runner (wraps os/exec) ──────────────────────────────────────────

// runProcess executes the given command and pipes stdout+stderr to logFile.
// Returns "success", "failed:N", or "error".
func runProcess(name string, args []string, env []string, cwd string, logFile *os.File) string {
	// We import os/exec inline to keep the package import list minimal.
	// (Using the global exec package imported at top.)
	proc := execCommand(name, args...)
	proc.Dir = cwd
	proc.Env = env
	proc.Stdout = logFile
	proc.Stderr = logFile
	if err := proc.Start(); err != nil {
		fmt.Fprintf(logFile, "\nError starting process: %v\n", err)
		return "error"
	}
	if err := proc.Wait(); err != nil {
		// Extract exit code
		return fmt.Sprintf("failed:%d", proc.ProcessState.ExitCode())
	}
	return "success"
}

// ─── HTTP handlers ────────────────────────────────────────────────────────────

// GET /
func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	state, err := loadState()
	if err != nil {
		http.Error(w, "State error: "+err.Error(), 500)
		return
	}
	// Sort by env ID
	ids := make([]string, 0, len(state))
	for id := range state {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	entries := make([]EnvEntry, 0, len(ids))
	for _, id := range ids {
		entries = append(entries, EnvEntry{id, state[id]})
	}
	renderPage(w, "index", IndexData{Environments: entries})
}

// GET /new
func newEnvironmentHandler(w http.ResponseWriter, r *http.Request) {
	renderPage(w, "new_environment", NewEnvData{Platforms: platforms})
}

// GET /configure/{platform}
func configureHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	if !validPlatform(platform) {
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}
	envID := r.URL.Query().Get("env_id")
	var cfg Config
	if envID != "" {
		state, _ := loadState()
		if env, ok := state[envID]; ok {
			cfg = env.Config
		}
	}

	// For new environments (or environments with no clusters configured),
	// seed with a single default cluster so the form is not empty.
	if len(cfg.Clusters) == 0 {
		cfg.Clusters = map[string]ClusterConfig{
			"cl01": {EnvTag: "test", ConfigsvrCount: 3, ShardCount: 2, ShardsvrReplicas: 2, ArbitersPerReplset: 1, MongosCount: 2},
		}
	}
	if platform == "docker" {
		if len(cfg.PmmServers) == 0 {
			cfg.PmmServers = map[string]PmmServerConfig{
				"pmm-server": {EnvTag: "test"},
			}
		}
		if len(cfg.MinioServers) == 0 {
			cfg.MinioServers = map[string]MinioServerConfig{
				"minio": {EnvTag: "test", MinioPort: 9000, MinioConsolePort: 9001, MinioAccessKey: "minio", MinioSecretKey: "minioadmin", BucketName: "mongo-backups", BackupRetention: 2},
			}
		}
	}

	renderPage(w, "configure", ConfigureData{
		Platform:         platform,
		EnvID:            envID,
		Config:           cfg,
		PSMDBVersions:    getPSMDBVersions(),
		PMMImages:        getPMMServerImages(),
		PSMDBImages:      getPSMDBImages(),
		PBMImages:        getPBMImages(),
		PMMClientImages:  getPMMClientImages(),
		SortedClusters:   sortedClusters(cfg.Clusters),
		SortedReplsets:   sortedReplsets(cfg.Replsets),
		SortedPmmServers: sortedPmmServers(cfg.PmmServers),
		SortedMinio:      sortedMinioServers(cfg.MinioServers),
		SortedLdap:       sortedLdapServers(cfg.LdapServers),
	})
}

// GET /environment/{env_id}
func environmentHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	state, _ := loadState()
	env, ok := state[envID]
	if !ok {
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}
	renderPage(w, "environment", EnvironmentData{
		EnvID:          envID,
		Env:            env,
		SortedClusters: sortedClusters(env.Config.Clusters),
		SortedReplsets: sortedReplsets(env.Config.Replsets),
	})
}

// GET /api/versions
func apiVersionsHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]interface{}{
		"psmdb_versions":    getPSMDBVersions(),
		"pmm_server_images": getPMMServerImages(),
		"psmdb_images":      getPSMDBImages(),
		"pbm_images":        getPBMImages(),
		"pmm_client_images": getPMMClientImages(),
	})
}

// POST /api/environment
func saveEnvironmentHandler(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		EnvID    string `json:"env_id"`
		Platform string `json:"platform"`
		Config   Config `json:"config"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		jsonError(w, 400, "invalid JSON: "+err.Error())
		return
	}
	if payload.EnvID == "" {
		payload.EnvID = secureID(4) // 8 hex chars, 32 bits – sufficient for env names
	}
	if !envIDRe.MatchString(payload.EnvID) {
		jsonError(w, 400, "invalid env_id: use letters, digits, hyphens and underscores (max 40 chars)")
		return
	}
	if !validPlatform(payload.Platform) {
		jsonError(w, 400, "invalid platform")
		return
	}

	state, _ := loadState()
	existing := state[payload.EnvID]
	status := "configured"
	createdAt := time.Now().UTC().Format(time.RFC3339)
	if existing != nil {
		status = existing.Status
		createdAt = existing.CreatedAt
	}
	env := &Environment{
		Platform:  payload.Platform,
		Config:    payload.Config,
		Status:    status,
		CreatedAt: createdAt,
		UpdatedAt: time.Now().UTC().Format(time.RFC3339),
	}
	if existing != nil {
		env.LastJobID = existing.LastJobID
	}
	state[payload.EnvID] = env
	if err := saveState(state); err != nil {
		jsonError(w, 500, "state save failed: "+err.Error())
		return
	}

	if err := writeTfvars(payload.EnvID, payload.Platform, payload.Config); err != nil {
		jsonError(w, 500, "tfvars write failed: "+err.Error())
		return
	}

	writeJSON(w, 200, map[string]string{"env_id": payload.EnvID, "status": "configured"})
}

// DELETE /api/environment/{env_id}
func deleteEnvironmentHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	if !envIDRe.MatchString(envID) {
		jsonError(w, 400, "invalid environment ID")
		return
	}
	state, _ := loadState()
	env := state[envID]
	delete(state, envID)
	saveState(state)

	// Remove tfvars file
	if env != nil {
		p := tfvarsPath(envID, env.Platform)
		os.Remove(p)
	} else {
		for _, pl := range platforms {
			os.Remove(tfvarsPath(envID, pl))
		}
	}
	writeJSON(w, 200, map[string]string{"status": "deleted"})
}

// GET /api/environment/{env_id}/tfvars
func getTfvarsHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	if !envIDRe.MatchString(envID) {
		jsonError(w, 400, "invalid environment ID")
		return
	}
	state, _ := loadState()
	env, ok := state[envID]
	if !ok {
		jsonError(w, 404, "environment not found")
		return
	}
	p := tfvarsPath(envID, env.Platform)
	content, err := os.ReadFile(p)
	if err != nil {
		writeJSON(w, 200, map[string]string{"content": "", "message": "tfvars file not yet generated"})
		return
	}
	writeJSON(w, 200, map[string]string{"content": string(content), "filename": filepath.Base(p)})
}

// POST /api/environment/{env_id}/action
func environmentActionHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	if !envIDRe.MatchString(envID) {
		jsonError(w, 400, "invalid environment ID")
		return
	}
	state, _ := loadState()
	env, ok := state[envID]
	if !ok {
		jsonError(w, 404, "environment not found")
		return
	}

	var body struct {
		Action string `json:"action"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, 400, "invalid JSON")
		return
	}
	action := body.Action
	platform := env.Platform
	tfDir := filepath.Join(terraformDir, platform)
	varfile := tfvarsPath(envID, platform)

	// Ensure tfvars file exists
	if _, err := os.Stat(varfile); os.IsNotExist(err) {
		if wErr := writeTfvars(envID, platform, env.Config); wErr != nil {
			jsonError(w, 500, "tfvars not found and could not be regenerated: "+wErr.Error())
			return
		}
	}

	var cmd []string
	switch action {
	case "deploy":
		shellCmd := fmt.Sprintf(
			"terraform init -input=false && terraform apply -auto-approve -input=false -var-file=%s",
			shellQuote(varfile),
		)
		if platform != "docker" {
			playbook := shellQuote(filepath.Join(ansibleDir, "main.yml"))
			// Terraform writes inventory_<name> files into the platform directory.
			// Verify at least one exists (proving terraform apply succeeded), then
			// run ansible-playbook once per generated inventory file.
			shellCmd += fmt.Sprintf(
				` && { inv_files=$(ls inventory_* 2>/dev/null); `+
					`[ -n "$inv_files" ] || { echo "ERROR: no inventory_* files found – terraform apply may not have completed successfully"; exit 1; }; `+
					`for inv in $inv_files; do echo "==> ansible-playbook -i $inv"; ansible-playbook -i "$inv" %s || exit $?; done; }`,
				playbook,
			)
		}
		cmd = []string{"bash", "-c", shellCmd}

	case "destroy":
		cmd = []string{"bash", "-c", fmt.Sprintf(
			"terraform destroy -auto-approve -input=false -var-file=%s",
			shellQuote(varfile),
		)}

	case "stop":
		if platform == "docker" {
			// sanitiseShellArg strips everything except [a-zA-Z0-9_-] so the
			// prefix is safe to embed in the docker --filter value.  The
			// alternative of using exec.Command without bash -c is not feasible
			// here because we need the pipe to xargs.
			prefix := sanitiseShellArg(strDefault(env.Config.Prefix, envID))
			cmd = []string{"bash", "-c",
				fmt.Sprintf("docker ps -q --filter 'name=%s-' | xargs -r docker stop", prefix),
			}
		} else {
			playbook := shellQuote(filepath.Join(ansibleDir, "stop.yml"))
			cmd = []string{"bash", "-c", fmt.Sprintf(
				`{ inv_files=$(ls inventory_* 2>/dev/null); `+
					`[ -n "$inv_files" ] || { echo "ERROR: no inventory_* files found – has the environment been deployed?"; exit 1; }; `+
					`for inv in $inv_files; do echo "==> ansible-playbook -i $inv"; ansible-playbook -i "$inv" %s || exit $?; done; }`,
				playbook,
			)}
		}

	case "restart":
		if platform == "docker" {
			prefix := sanitiseShellArg(strDefault(env.Config.Prefix, envID))
			cmd = []string{"bash", "-c",
				fmt.Sprintf("docker ps -aq --filter 'name=%s-' | xargs -r docker restart", prefix),
			}
		} else {
			playbook := shellQuote(filepath.Join(ansibleDir, "restart.yml"))
			cmd = []string{"bash", "-c", fmt.Sprintf(
				`{ inv_files=$(ls inventory_* 2>/dev/null); `+
					`[ -n "$inv_files" ] || { echo "ERROR: no inventory_* files found – has the environment been deployed?"; exit 1; }; `+
					`for inv in $inv_files; do echo "==> ansible-playbook -i $inv"; ansible-playbook -i "$inv" %s || exit $?; done; }`,
				playbook,
			)}
		}

	default:
		jsonError(w, 400, "unknown action: "+action)
		return
	}

	// Callback: remove environment from inventory after successful destroy.
	var onComplete func(string)
	if action == "destroy" {
		onComplete = func(status string) {
			if status == "success" {
				st, _ := loadState()
				delete(st, envID)
				saveState(st)
				os.Remove(varfile)
			}
		}
	}

	jobID := startJob(cmd, tfDir, nil, onComplete)

	env.Status = action + "_in_progress"
	env.LastJobID = jobID
	state[envID] = env
	saveState(state)

	slog.Info("action dispatched", "action", action, "env", envID, "platform", platform, "job", jobID)
	writeJSON(w, 200, map[string]string{"job_id": jobID, "status": env.Status})
}

// GET /api/job/{job_id}/status
func jobStatusHandler(w http.ResponseWriter, r *http.Request) {
	jobID := r.PathValue("job_id")
	data, err := os.ReadFile(jobStatusPath(jobID))
	if err != nil {
		writeJSON(w, 200, map[string]string{"status": "unknown"})
		return
	}
	writeJSON(w, 200, map[string]string{"status": strings.TrimSpace(string(data))})
}

// GET /api/job/{job_id}/stream  (Server-Sent Events)
func jobStreamHandler(w http.ResponseWriter, r *http.Request) {
	jobID := r.PathValue("job_id")

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", 500)
		return
	}

	logPath := jobLogPath(jobID)
	statusPath := jobStatusPath(jobID)

	// Wait up to 2 s for log file to appear.
	for i := 0; i < 20; i++ {
		if _, err := os.Stat(logPath); err == nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	var pos int64
	ctx := r.Context()
	for {
		// Read any new data from the log file.
		if f, err := os.Open(logPath); err == nil {
			f.Seek(pos, io.SeekStart)
			scanner := bufio.NewScanner(f)
			for scanner.Scan() {
				line := stripAnsi(scanner.Text())
				if data, err := json.Marshal(line); err == nil {
					fmt.Fprintf(w, "data: %s\n\n", data)
				}
			}
			newPos, _ := f.Seek(0, io.SeekCurrent)
			f.Close()
			if newPos > pos {
				pos = newPos
				flusher.Flush()
			}
		}

		// Check if job has finished.
		statusBytes, _ := os.ReadFile(statusPath)
		status := strings.TrimSpace(string(statusBytes))
		if status != "" && status != "running" {
			statusJSON, _ := json.Marshal(status)
			fmt.Fprintf(w, "event: done\ndata: %s\n\n", statusJSON)
			flusher.Flush()
			return
		}

		select {
		case <-ctx.Done():
			return
		case <-time.After(300 * time.Millisecond):
		}
	}
}

// GET /api/job/{job_id}/log
func jobLogHandler(w http.ResponseWriter, r *http.Request) {
	jobID := r.PathValue("job_id")
	logPath := jobLogPath(jobID)
	content, err := os.ReadFile(logPath)
	if err != nil {
		writeJSON(w, 200, map[string]string{"log": "", "status": "unknown"})
		return
	}
	statusBytes, _ := os.ReadFile(jobStatusPath(jobID))
	status := strings.TrimSpace(string(statusBytes))
	if status == "" {
		status = "unknown"
	}
	writeJSON(w, 200, map[string]string{"log": string(content), "status": status})
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func validPlatform(p string) bool {
	for _, pl := range platforms {
		if p == pl {
			return true
		}
	}
	return false
}

// shellQuote wraps s in single-quotes, escaping any single-quotes inside.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// sanitiseShellArg removes characters that are not safe for direct shell interpolation.
// Hyphens are retained because they are valid in container names and docker --filter values.
func sanitiseShellArg(s string) string {
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ─── Main ─────────────────────────────────────────────────────────────────────

func main() {
	// Determine base directory (the ui-go/ folder) relative to the binary or
	// relative to the current working directory when using `go run`.
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}
	// If running from source with `go run`, cwd is the ui-go/ directory.
	// If running a compiled binary from another directory, the caller should
	// set UI_BASE_DIR or run the binary from ui-go/.
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

	// Structured logging to stderr.
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})))
	slog.Info("starting MongoDB Deploy UI (Go)", "baseDir", baseDir)

	// Warm the version/image caches in the background.
	go prefetchVersions()

	// Register routes.
	mux := http.NewServeMux()

	// Pages
	mux.HandleFunc("GET /", indexHandler)
	mux.HandleFunc("GET /new", newEnvironmentHandler)
	mux.HandleFunc("GET /configure/{platform}", configureHandler)
	mux.HandleFunc("GET /environment/{env_id}", environmentHandler)

	// API
	mux.HandleFunc("GET /api/versions", apiVersionsHandler)
	mux.HandleFunc("POST /api/environment", saveEnvironmentHandler)
	mux.HandleFunc("DELETE /api/environment/{env_id}", deleteEnvironmentHandler)
	mux.HandleFunc("GET /api/environment/{env_id}/tfvars", getTfvarsHandler)
	mux.HandleFunc("POST /api/environment/{env_id}/action", environmentActionHandler)
	mux.HandleFunc("GET /api/job/{job_id}/status", jobStatusHandler)
	mux.HandleFunc("GET /api/job/{job_id}/stream", jobStreamHandler)
	mux.HandleFunc("GET /api/job/{job_id}/log", jobLogHandler)

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
