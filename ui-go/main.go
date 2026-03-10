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
var safeFilenameRe = regexp.MustCompile(`[^a-zA-Z0-9._-]`)

const cacheTTL = 5 * time.Minute

// defaultPSMDBVersions is used as a fallback when the Percona repo is unreachable.
var defaultPSMDBVersions = []string{"psmdb-80", "psmdb-70", "psmdb-60", "psmdb-50", "psmdb-44", "psmdb-42", "psmdb-40", "psmdb-36"}

// defaultPBMReleases is used as a fallback when the Percona repo is unreachable.
var defaultPBMReleases = []string{"pbm-30", "pbm-20", "pbm-12", "pbm-11", "pbm-10"}

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
	Prefix       string `json:"prefix"`
	MongoRelease string `json:"mongo_release,omitempty"`
	PbmRelease   string `json:"pbm_release,omitempty"`

	// Cloud credentials / settings
	ProjectID        string `json:"project_id,omitempty"`
	Region           string `json:"region,omitempty"`
	Location         string `json:"location,omitempty"`
	SubnetCIDR       string `json:"subnet_cidr,omitempty"`
	SubnetCount      int    `json:"subnet_count,omitempty"`
	SourceRanges     string `json:"source_ranges,omitempty"`
	MySSHUser        string `json:"my_ssh_user,omitempty"`
	SSHPublicKeyPath string `json:"ssh_public_key_path,omitempty"`
	DefaultKeyPair   string `json:"default_key_pair,omitempty"`
	EnableSSHGateway bool   `json:"enable_ssh_gateway,omitempty"`
	SSHGatewayName   string `json:"ssh_gateway_name,omitempty"`
	PortToForward    string `json:"port_to_forward,omitempty"`
	UseSpotInstances bool   `json:"use_spot_instances,omitempty"`
	DefaultVpcName   string `json:"default_vpc_name,omitempty"`

	// SSH users map — key=username, value=path to public key file.
	// GCP uses the variable name gce_ssh_users; AWS/Azure use ssh_users.
	SSHUsers map[string]string `json:"ssh_users,omitempty"`

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

	// Machine image / AMI selected for cloud instances (AWS: AMI ID, GCP: image path).
	// Stored as a single ID; the Terraform `image` map is generated from this
	// value together with Region / Location at tfvars-write time.
	MachineImage string `json:"machine_image,omitempty"`

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

	// Ansible variable overrides passed via --extra-vars at playbook runtime.
	// Keys and values correspond directly to Ansible variable names.
	AnsibleVars map[string]string `json:"ansible_vars,omitempty"`
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
	HasDeleted   bool
}

type NewEnvData struct {
	Platforms []string
}

type ConfigureData struct {
	Platform        string
	EnvID           string
	Config          Config // populated from existing or defaults
	PSMDBVersions   []string
	PBMVersions     []string
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
	// Return true when b is explicitly set to false (i.e. non-nil and false).
	// Used to auto-expand the PMM customize panel when PMM has been disabled.
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
	// Returns the CSS class suffix for a status string.
	// Passes the status through mostly as-is; strips only colon-suffixes.
	// CSS classes for in-progress states are defined explicitly (.status-deploy_in_progress, etc.)
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

// fetchPerconaRepoPage fetches the Percona repository listing page and returns
// its body text. The result is cached to avoid redundant HTTP requests since
// both getPSMDBVersions and getPBMReleases need it.
func fetchPerconaRepoPage() string {
	const key = "percona_repo_page"
	if v, ok := cacheGet(key); ok {
		return v.(string)
	}
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get("https://repo.percona.com/")
	if err != nil {
		slog.Warn("percona repo page fetch failed", "err", err)
		cacheSet(key, "")
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		slog.Warn("percona repo page non-200", "status", resp.StatusCode)
		cacheSet(key, "")
		return ""
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Warn("percona repo page read failed", "err", err)
		cacheSet(key, "")
		return ""
	}
	page := string(body)
	cacheSet(key, page)
	return page
}

func getPSMDBVersions() []string {
	const key = "psmdb_versions"
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	var versions []string
	page := fetchPerconaRepoPage()
	if page != "" {
		re := regexp.MustCompile(`psmdb-\d+`)
		found := re.FindAllString(page, -1)
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
		slog.Warn("psmdb versions fetch failed – using defaults")
	}
	if len(versions) == 0 {
		versions = defaultPSMDBVersions
	}
	cacheSet(key, versions)
	return versions
}

func getPBMReleases() []string {
	const key = "pbm_releases"
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	var releases []string
	page := fetchPerconaRepoPage()
	if page != "" {
		re := regexp.MustCompile(`pbm-\d+`)
		found := re.FindAllString(page, -1)
		seen := map[string]bool{}
		for _, v := range found {
			if !seen[v] {
				seen[v] = true
				releases = append(releases, v)
			}
		}
		sort.Slice(releases, func(i, j int) bool { return releases[i] > releases[j] })
		slog.Info("fetched PBM releases", "count", len(releases))
	} else {
		slog.Warn("pbm releases fetch failed – using defaults")
	}
	if len(releases) == 0 {
		releases = defaultPBMReleases
	}
	cacheSet(key, releases)
	return releases
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
	getPBMReleases()
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
		// Note: mongo_release, pbm_release, pmm_image are Ansible-only variables;
		// they are passed via --extra-vars at Ansible runtime, not via tfvars.
		writeOptStr("project_id", cfg.ProjectID)
		writeOptStr("region", cfg.Region)
		writeOptStr("location", cfg.Location)
		writeOptStr("subnet_cidr", cfg.SubnetCIDR)
		writeOptStr("source_ranges", cfg.SourceRanges)
		writeOptStr("my_ssh_user", cfg.MySSHUser)
		writeOptStr("ssh_public_key_path", cfg.SSHPublicKeyPath)
		writeOptStr("default_key_pair", cfg.DefaultKeyPair)
		writeOptStr("default_vpc_name", cfg.DefaultVpcName)
		if cfg.EnableSSHGateway {
			writeOptBool("enable_ssh_gateway", cfg.EnableSSHGateway)
		}
		writeOptStr("ssh_gateway_name", cfg.SSHGatewayName)
		writeOptStr("port_to_forward", cfg.PortToForward)
		if cfg.UseSpotInstances {
			writeOptBool("use_spot_instances", cfg.UseSpotInstances)
		}
		writeOptInt("subnet_count", cfg.SubnetCount)

		// SSH users map:
		// - GCP: gce_ssh_users is written later (merged with primary user key if set)
		// - AWS: uses EC2 key pairs, ssh_users is not a Terraform variable
		// - Azure: ssh_users Terraform variable
		if len(cfg.SSHUsers) > 0 && platform == "azure" {
			// Sort keys for deterministic output
			userKeys := make([]string, 0, len(cfg.SSHUsers))
			for k := range cfg.SSHUsers {
				userKeys = append(userKeys, k)
			}
			sort.Strings(userKeys)
			write("")
			write("ssh_users = {")
			for _, k := range userKeys {
				write(fmt.Sprintf("  %s = %s", formatHCLVal(k), formatHCLVal(cfg.SSHUsers[k])))
			}
			write("}")
		}
		// GCP gce_ssh_users: only write if no primary SSH key (otherwise the merged
		// block written later covers all users including additional ones).
		if len(cfg.SSHUsers) > 0 && platform == "gcp" && cfg.SSHPublicKeyPath == "" {
			userKeys := make([]string, 0, len(cfg.SSHUsers))
			for k := range cfg.SSHUsers {
				userKeys = append(userKeys, k)
			}
			sort.Strings(userKeys)
			write("")
			write("gce_ssh_users = {")
			for _, k := range userKeys {
				write(fmt.Sprintf("  %s = %s", formatHCLVal(k), formatHCLVal(cfg.SSHUsers[k])))
			}
			write("}")
		}

		// PMM
		writeOptStr("pmm_type", cfg.PmmType)
		writeOptInt("pmm_volume_size", cfg.PmmVolumeSize)
		writeOptInt("pmm_port", cfg.PmmPort)
		// pmm_image is an Ansible variable; do not write it to tfvars.
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

		// Machine image: write as a map from region to image ID so it overrides
		// the hardcoded default in variables.tf.  For Azure the image is an object
		// (publisher/offer/sku) so we leave it to its Terraform default.
		regionKey := cfg.Region
		if platform == "azure" {
			regionKey = cfg.Location
		}
		if cfg.MachineImage != "" && regionKey != "" && platform != "azure" {
			write("")
			write("image = {")
			write(fmt.Sprintf("  %s = %s", formatHCLVal(regionKey), formatHCLVal(cfg.MachineImage)))
			write("}")
		}

		// For GCP: if a primary SSH key path is configured, inject the default
		// SSH user into gce_ssh_users so that both Terraform provisioning and
		// Ansible can reach instances with that user.
		if platform == "gcp" && cfg.SSHPublicKeyPath != "" && cfg.MySSHUser != "" {
			// Merge primary user into the users map (primary user takes precedence
			// over any duplicate entry in the additional-users section).
			merged := map[string]string{}
			for k, v := range cfg.SSHUsers {
				merged[k] = v
			}
			merged[cfg.MySSHUser] = cfg.SSHPublicKeyPath
			mergedKeys := make([]string, 0, len(merged))
			for k := range merged {
				mergedKeys = append(mergedKeys, k)
			}
			sort.Strings(mergedKeys)
			write("")
			write("gce_ssh_users = {")
			for _, k := range mergedKeys {
				write(fmt.Sprintf("  %s = %s", formatHCLVal(k), formatHCLVal(merged[k])))
			}
			write("}")
		}
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
	hasDeleted := false
	for _, id := range ids {
		entries = append(entries, EnvEntry{id, state[id]})
		if state[id].Status == "deleted" {
			hasDeleted = true
		}
	}
	renderPage(w, "index", IndexData{Environments: entries, HasDeleted: hasDeleted})
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

	// For new environments, do NOT seed any default clusters or replica sets.
	// The user will add them explicitly via the form.
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
		PBMVersions:      getPBMReleases(),
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
		"pbm_releases":      getPBMReleases(),
		"pmm_server_images": getPMMServerImages(),
		"psmdb_images":      getPSMDBImages(),
		"pbm_images":        getPBMImages(),
		"pmm_client_images": getPMMClientImages(),
	})
}

// GET /api/regions/{platform}
// Returns available regions for the given cloud platform by querying the
// respective CLI tool (aws / gcloud / az).  On error returns a static
// fallback list so the UI is always usable.
func apiRegionsHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	regions := getCloudRegions(platform)
	writeJSON(w, 200, map[string]interface{}{
		"regions":         regions,
		"grouped_regions": groupRegionsByGeo(platform, regions),
	})
}

// groupRegionsByGeo groups a flat region list into geographic buckets so the
// UI can render them as <optgroup> elements, similar to the OS grouping used
// for machine images.  Each platform uses its own naming convention.
func groupRegionsByGeo(platform string, regions []string) map[string][]string {
	groups := map[string][]string{}
	for _, r := range regions {
		g := regionGeoGroup(platform, r)
		groups[g] = append(groups[g], r)
	}
	return groups
}

// regionGeoGroup returns a human-readable geographic group name for a region.
func regionGeoGroup(platform, region string) string {
	switch platform {
	case "aws":
		switch {
		case strings.HasPrefix(region, "us-"):
			return "US"
		case strings.HasPrefix(region, "ca-"):
			return "Canada"
		case strings.HasPrefix(region, "eu-") || strings.HasPrefix(region, "europe-"):
			return "Europe"
		case strings.HasPrefix(region, "ap-") || strings.HasPrefix(region, "asia-") || strings.HasPrefix(region, "australia-"):
			return "Asia Pacific"
		case strings.HasPrefix(region, "sa-") || strings.HasPrefix(region, "southamerica-"):
			return "South America"
		case strings.HasPrefix(region, "me-") || strings.HasPrefix(region, "af-"):
			return "Middle East & Africa"
		case strings.HasPrefix(region, "il-"):
			return "Middle East & Africa"
		}
	case "gcp":
		switch {
		case strings.HasPrefix(region, "us-") || strings.HasPrefix(region, "northamerica-"):
			return "North America"
		case strings.HasPrefix(region, "southamerica-"):
			return "South America"
		case strings.HasPrefix(region, "europe-"):
			return "Europe"
		case strings.HasPrefix(region, "asia-") || strings.HasPrefix(region, "australia-"):
			return "Asia Pacific"
		case strings.HasPrefix(region, "me-") || strings.HasPrefix(region, "africa-"):
			return "Middle East & Africa"
		}
	case "azure":
		// Check australia first with a specific prefix to avoid substring matches
		// (e.g. 'australiaeast' must not match the 'us' check below).
		if strings.HasPrefix(region, "australia") {
			return "Asia Pacific"
		}
		switch {
		case strings.Contains(region, "us") || strings.Contains(region, "canada"):
			return "North America"
		case strings.Contains(region, "brazil"):
			return "South America"
		case strings.Contains(region, "europe") || strings.Contains(region, "uk") || strings.Contains(region, "france") ||
			strings.Contains(region, "germany") || strings.Contains(region, "norway") || strings.Contains(region, "switzerland") || strings.Contains(region, "sweden"):
			return "Europe"
		case strings.Contains(region, "asia") || strings.Contains(region, "japan") || strings.Contains(region, "korea") ||
			strings.Contains(region, "india") || strings.Contains(region, "china"):
			return "Asia Pacific"
		case strings.Contains(region, "africa") || strings.Contains(region, "uae"):
			return "Middle East & Africa"
		}
	}
	return "Other"
}



// ─── SSH key upload ───────────────────────────────────────────────────────────

// POST /api/upload-ssh-key/{platform}
// Accepts a multipart file upload (field name "ssh_key_file") and saves it
// into terraform/{platform}/ so Terraform's file() function can find it.
// Returns {"path": "<filename>"} — just the filename, relative to the
// Terraform working directory.
func apiUploadSSHKeyHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	if !validPlatform(platform) || platform == "docker" {
		jsonError(w, 400, "invalid platform")
		return
	}
	if err := r.ParseMultipartForm(1 << 20); err != nil { // 1 MB max
		jsonError(w, 400, "failed to parse upload: "+err.Error())
		return
	}
	file, header, err := r.FormFile("ssh_key_file")
	if err != nil {
		jsonError(w, 400, "ssh_key_file field missing: "+err.Error())
		return
	}
	defer file.Close()

	// Sanitise the filename – allow only safe characters to prevent path traversal.
	name := safeFilenameRe.ReplaceAllString(filepath.Base(header.Filename), "_")
	if name == "" {
		name = "id_rsa.pub"
	}

	destDir := filepath.Clean(filepath.Join(terraformDir, platform))
	if err := os.MkdirAll(destDir, 0755); err != nil {
		jsonError(w, 500, "cannot create upload dir: "+err.Error())
		return
	}
	destPath := filepath.Clean(filepath.Join(destDir, name))
	// Restrict to destDir to prevent path-traversal (sanitised name contains no '/')
	// but verify with Clean-normalised paths as an extra safety measure.
	if filepath.Dir(destPath) != destDir {
		jsonError(w, 400, "invalid filename")
		return
	}

	data, err := io.ReadAll(file)
	if err != nil {
		jsonError(w, 500, "read failed: "+err.Error())
		return
	}
	if err := os.WriteFile(destPath, data, 0600); err != nil {
		jsonError(w, 500, "write failed: "+err.Error())
		return
	}
	writeJSON(w, 200, map[string]string{"path": name})
}

// ─── Cloud machine images ─────────────────────────────────────────────────────

// CloudImage represents a single machine image available for a region.
type CloudImage struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
}

// GET /api/images/{platform}?region={region}
// Returns Linux images available in the given region, grouped by OS family.
// The response shape is {"images": {"OS Family": [{"id":..,"name":..}, ...], ...}}
func apiImagesHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	region := r.URL.Query().Get("region")
	if region == "" {
		region = r.URL.Query().Get("location") // Azure uses 'location'
	}
	images, err := getCloudImages(platform, region)
	if err != nil {
		// Return empty groups instead of an error so the UI stays functional.
		slog.Warn("cloud images fetch failed", "platform", platform, "region", region, "err", err)
		images = map[string][]CloudImage{}
	}
	writeJSON(w, 200, map[string]interface{}{"images": images})
}

// getCloudImages queries the relevant CLI for Linux images in the given region.
func getCloudImages(platform, region string) (map[string][]CloudImage, error) {
	cacheKey := fmt.Sprintf("images:%s:%s", platform, region)
	if v, ok := cacheGet(cacheKey); ok {
		return v.(map[string][]CloudImage), nil
	}
	var result map[string][]CloudImage
	var err error
	switch platform {
	case "aws":
		result, err = getAWSImages(region)
	case "gcp":
		result, err = getGCPImages(region)
	case "azure":
		result, err = getAzureImages(region)
	default:
		return map[string][]CloudImage{}, nil
	}
	if err != nil {
		return map[string][]CloudImage{}, err
	}
	cacheSet(cacheKey, result)
	return result, nil
}

// awsImageOwner maps an OS group label to the AWS AMI owner account ID and
// name filter used to retrieve the most-recent images of that type.
var awsImageOwners = []struct {
	Group       string
	OwnerID     string
	NamePattern string
}{
	{"Amazon Linux 2023", "137112412989", "al2023-ami-2023*x86_64"},
	{"Amazon Linux 2", "137112412989", "amzn2-ami-hvm-*-x86_64-gp2"},
	{"Ubuntu 24.04 LTS", "099720109477", "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"},
	{"Ubuntu 22.04 LTS", "099720109477", "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"},
	{"CentOS Stream 9", "125523088429", "CentOS Stream 9*x86_64*"},
	{"Rocky Linux 9", "792107900819", "Rocky-9-EC2*x86_64*"},
	{"Debian 12", "136693071363", "debian-12-amd64-*"},
}

func getAWSImages(region string) (map[string][]CloudImage, error) {
	result := map[string][]CloudImage{}
	for _, o := range awsImageOwners {
		args := []string{
			"ec2", "describe-images",
			"--region", region,
			"--owners", o.OwnerID,
			"--filters",
			fmt.Sprintf("Name=name,Values=%s", o.NamePattern),
			"Name=state,Values=available",
			"Name=architecture,Values=x86_64",
			// Only public images, no paid marketplace entries
			"Name=is-public,Values=true",
			"--query",
			"reverse(sort_by(Images,&CreationDate))[:5].{id:ImageId,name:Name,desc:Description}",
			"--output", "json",
		}
		out, err := execOutput("aws", args...)
		if err != nil {
			slog.Warn("aws describe-images failed", "group", o.Group, "region", region, "err", err)
			continue
		}
		var imgs []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
			Desc string `json:"desc"`
		}
		if err := json.Unmarshal([]byte(out), &imgs); err != nil {
			continue
		}
		group := make([]CloudImage, 0, len(imgs))
		for _, img := range imgs {
			group = append(group, CloudImage{ID: img.ID, Name: img.Name, Description: img.Desc})
		}
		if len(group) > 0 {
			result[o.Group] = group
		}
	}
	return result, nil
}

// gcpImageProjects maps OS family to a GCP image project name.
var gcpImageProjects = []struct {
	Group   string
	Project string
	Family  string
}{
	{"CentOS Stream 9", "centos-cloud", "centos-stream-9"},
	{"Debian 12", "debian-cloud", "debian-12"},
	{"Ubuntu 24.04 LTS", "ubuntu-os-cloud", "ubuntu-2404-lts-amd64"},
	{"Ubuntu 22.04 LTS", "ubuntu-os-cloud", "ubuntu-2204-lts"},
	{"Rocky Linux 9", "rocky-linux-cloud", "rocky-linux-9"},
	{"RHEL 9", "rhel-cloud", "rhel-9"},
}

func getGCPImages(region string) (map[string][]CloudImage, error) {
	result := map[string][]CloudImage{}
	for _, p := range gcpImageProjects {
		args := []string{
			"compute", "images", "list",
			"--project", p.Project,
			"--filter", fmt.Sprintf("family=%s status=READY", p.Family),
			"--sort-by", "~creationTimestamp",
			"--limit", "5",
			"--format", "json(selfLink,name,description)",
		}
		out, err := execOutput("gcloud", args...)
		if err != nil {
			slog.Warn("gcloud images list failed", "group", p.Group, "err", err)
			continue
		}
		var imgs []struct {
			SelfLink    string `json:"selfLink"`
			Name        string `json:"name"`
			Description string `json:"description"`
		}
		if err := json.Unmarshal([]byte(out), &imgs); err != nil {
			continue
		}
		group := make([]CloudImage, 0, len(imgs))
		for _, img := range imgs {
			group = append(group, CloudImage{ID: img.SelfLink, Name: img.Name, Description: img.Description})
		}
		if len(group) > 0 {
			result[p.Group] = group
		}
	}
	return result, nil
}

// azureImagePublishers lists popular Linux image publishers for Azure.
var azureImagePublishers = []struct {
	Group     string
	Publisher string
	Offer     string
}{
	{"Ubuntu 24.04 LTS", "Canonical", "ubuntu-24_04-lts"},
	{"Ubuntu 22.04 LTS", "Canonical", "0001-com-ubuntu-server-jammy"},
	{"Debian 12", "Debian", "debian-12"},
	{"AlmaLinux 9", "almalinux", "almalinux-x86_64"},
	{"Rocky Linux 9", "resf", "rockylinux-x86_64"},
}

func getAzureImages(location string) (map[string][]CloudImage, error) {
	result := map[string][]CloudImage{}
	for _, pub := range azureImagePublishers {
		args := []string{
			"vm", "image", "list",
			"--location", location,
			"--publisher", pub.Publisher,
			"--offer", pub.Offer,
			"--all",
			"--query", "reverse(sort_by([?osType=='Linux'],&version))[:5].{id:urn,name:skus,desc:offer}",
			"--output", "json",
		}
		out, err := execOutput("az", args...)
		if err != nil {
			slog.Warn("az vm image list failed", "group", pub.Group, "location", location, "err", err)
			continue
		}
		var imgs []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
			Desc string `json:"desc"`
		}
		if err := json.Unmarshal([]byte(out), &imgs); err != nil {
			continue
		}
		group := make([]CloudImage, 0, len(imgs))
		for _, img := range imgs {
			group = append(group, CloudImage{ID: img.ID, Name: img.Name, Description: img.Desc})
		}
		if len(group) > 0 {
			result[pub.Group] = group
		}
	}
	return result, nil
}


// getCloudRegions queries the cloud CLI for available regions, with a static
// fallback for each platform when the CLI is not available or returns an error.
func getCloudRegions(platform string) []string {
	key := "regions:" + platform
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	var regions []string
	switch platform {
	case "aws":
		regions = getAWSRegions()
	case "gcp":
		regions = getGCPRegions()
	case "azure":
		regions = getAzureRegions()
	}
	if len(regions) == 0 {
		regions = defaultRegions(platform)
	}
	cacheSet(key, regions)
	return regions
}

func getAWSRegions() []string {
	out, err := execOutput("aws", "ec2", "describe-regions",
		"--query", "Regions[].RegionName", "--output", "json")
	if err != nil {
		slog.Warn("aws describe-regions failed", "err", err)
		return nil
	}
	var names []string
	if err := json.Unmarshal([]byte(out), &names); err != nil {
		slog.Warn("aws describe-regions parse failed", "err", err)
		return nil
	}
	sort.Strings(names)
	return names
}

func getGCPRegions() []string {
	out, err := execOutput("gcloud", "compute", "regions", "list",
		"--format=value(name)")
	if err != nil {
		slog.Warn("gcloud regions list failed", "err", err)
		return nil
	}
	var names []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			names = append(names, line)
		}
	}
	sort.Strings(names)
	return names
}

func getAzureRegions() []string {
	out, err := execOutput("az", "account", "list-locations",
		"--query", "[].name", "--output", "json")
	if err != nil {
		slog.Warn("az list-locations failed", "err", err)
		return nil
	}
	var names []string
	if err := json.Unmarshal([]byte(out), &names); err != nil {
		slog.Warn("az list-locations parse failed", "err", err)
		return nil
	}
	sort.Strings(names)
	return names
}

// defaultRegions returns a static fallback list for each platform.
func defaultRegions(platform string) []string {
	switch platform {
	case "aws":
		return []string{
			"ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
			"ap-south-1", "ap-southeast-1", "ap-southeast-2",
			"ca-central-1", "eu-central-1", "eu-north-1",
			"eu-west-1", "eu-west-2", "eu-west-3",
			"sa-east-1",
			"us-east-1", "us-east-2", "us-west-1", "us-west-2",
		}
	case "gcp":
		return []string{
			"asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2",
			"asia-northeast3", "asia-south1", "asia-southeast1", "asia-southeast2",
			"australia-southeast1",
			"europe-north1", "europe-west1", "europe-west2", "europe-west3",
			"europe-west4", "europe-west6",
			"northamerica-northeast1", "northamerica-northeast2",
			"southamerica-east1",
			"us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
			"us-west3", "us-west4",
		}
	case "azure":
		return []string{
			"australiaeast", "australiasoutheast",
			"brazilsouth",
			"canadacentral", "canadaeast",
			"centralindia", "centralus",
			"eastasia", "eastus", "eastus2",
			"francecentral",
			"germanywestcentral",
			"japaneast", "japanwest",
			"koreacentral",
			"northeurope", "norwayeast",
			"southafricanorth",
			"southcentralus", "southeastasia", "southindia",
			"swedencentral",
			"switzerlandnorth",
			"uaenorth",
			"uksouth", "ukwest",
			"westeurope", "westus", "westus2", "westus3",
		}
	}
	return nil
}

// execOutput runs the given command and returns its combined stdout as a
// trimmed string.  Stderr is discarded so callers only see clean output.
// An error is returned when the process exits with a non-zero status or
// cannot be started (e.g. the CLI tool is not installed).
func execOutput(name string, args ...string) (string, error) {
	cmd := execCommand(name, args...)
	var out strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err != nil {
		return "", err
	}
	return out.String(), nil
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

// DELETE /api/environment/{env_id}  — hard-removes an env from state (purge).
// The destroy action marks it as "deleted" but keeps it visible in the UI;
// this endpoint physically removes the record.
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

// DELETE /api/environments/deleted  — purges all environments whose status is "deleted".
func purgeDeletedEnvironmentsHandler(w http.ResponseWriter, r *http.Request) {
	state, err := loadState()
	if err != nil {
		jsonError(w, 500, "state error: "+err.Error())
		return
	}
	count := 0
	for id, env := range state {
		if env.Status == "deleted" {
			delete(state, id)
			os.Remove(tfvarsPath(id, env.Platform))
			count++
		}
	}
	saveState(state)
	writeJSON(w, 200, map[string]interface{}{"removed": count})
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

// GET /api/environment/{env_id}/inventory
// Returns all Ansible inventory files generated by Terraform for this
// environment (one file per cluster and per replica set).  Files are read
// from the Terraform working directory for the platform, where Terraform
// outputs them as local_file resources named inventory_<name>.
func getInventoryHandler(w http.ResponseWriter, r *http.Request) {
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
	if env.Platform == "docker" {
		writeJSON(w, 200, map[string]interface{}{"files": []interface{}{}})
		return
	}

	tfDir := filepath.Join(terraformDir, env.Platform)

	// Collect names from clusters and replsets.
	var names []string
	for name := range env.Config.Clusters {
		names = append(names, name)
	}
	for name := range env.Config.Replsets {
		names = append(names, name)
	}
	sort.Strings(names)

	type invFile struct {
		Name    string `json:"name"`
		Content string `json:"content"`
	}
	var files []invFile
	for _, name := range names {
		p := filepath.Join(tfDir, "inventory_"+name)
		content, err := os.ReadFile(p)
		if err != nil {
			// File not yet generated (Terraform has not run yet) – skip.
			continue
		}
		files = append(files, invFile{Name: "inventory_" + name, Content: string(content)})
	}

	if len(files) == 0 {
		writeJSON(w, 200, map[string]interface{}{
			"files":   []interface{}{},
			"message": "No inventory files found. Run Provision or Deploy first.",
		})
		return
	}
	writeJSON(w, 200, map[string]interface{}{"files": files})
}

// ─── Host info ────────────────────────────────────────────────────────────────

// HostInfo describes a single running host or container.
type HostInfo struct {
	Name        string `json:"name"`
	IP          string `json:"ip"`
	ConnectCmd  string `json:"connect_cmd"`
	Role        string `json:"role"`   // "mongod", "mongos", "pmm", "minio", "ldap", etc.
	Group       string `json:"group"`  // cluster/replset name, or service name
}

// ServiceURL describes an HTTP service (PMM, Minio console) with an openable URL.
type ServiceURL struct {
	Name  string `json:"name"`
	Label string `json:"label"`
	URL   string `json:"url"`
}

// MongoConnInfo describes a MongoDB connection string for a cluster or replica set.
type MongoConnInfo struct {
	Name       string `json:"name"`
	Type       string `json:"type"` // "cluster" or "replset"
	ConnString string `json:"conn_string"`
}

// GET /api/environment/{env_id}/hosts
// Returns host/container info, connection strings, and service URLs for the
// environment.  For Docker platforms the data is queried live from docker
// inspect.  For cloud platforms the Ansible inventory files are parsed.
func getHostsHandler(w http.ResponseWriter, r *http.Request) {
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

	var hosts []HostInfo
	var serviceURLs []ServiceURL
	var mongoConns []MongoConnInfo
	var msg string

	if env.Platform == "docker" {
		hosts, serviceURLs, mongoConns, msg = collectDockerHosts(envID, env)
	} else {
		hosts, mongoConns, msg = collectCloudHosts(envID, env)
	}

	writeJSON(w, 200, map[string]interface{}{
		"hosts":        hosts,
		"service_urls": serviceURLs,
		"mongo_conns":  mongoConns,
		"message":      msg,
	})
}

// collectDockerHosts uses `docker inspect` to gather container info for a
// Docker-based environment.
func collectDockerHosts(envID string, env *Environment) ([]HostInfo, []ServiceURL, []MongoConnInfo, string) {
	prefix := strDefault(env.Config.Prefix, envID)
	// List all containers whose name starts with the prefix.
	out, err := execOutput("docker", "ps", "-a",
		"--filter", "name="+prefix+"-",
		"--format", "{{.Names}}")
	if err != nil || strings.TrimSpace(out) == "" {
		return nil, nil, nil, "No containers found. Run Deploy first."
	}

	type dockerInspectNet struct {
		IPAddress string `json:"IPAddress"`
	}
	type dockerInspectNetworks struct {
		Networks map[string]dockerInspectNet `json:"Networks"`
	}
	type dockerInspectResult struct {
		Name            string `json:"Name"`
		NetworkSettings dockerInspectNetworks `json:"NetworkSettings"`
	}

	var hosts []HostInfo

	names := strings.Split(strings.TrimSpace(out), "\n")
	for _, rawName := range names {
		name := strings.TrimPrefix(strings.TrimSpace(rawName), "/")
		if name == "" {
			continue
		}
		// Get IP via docker inspect.
		ipOut, err := execOutput("docker", "inspect",
			"--format", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", name)
		ip := strings.TrimSpace(ipOut)
		if err != nil || ip == "" {
			ip = "—"
		}
		connectCmd := fmt.Sprintf("docker exec -it %s bash", name)
		role := guessDockerRole(name, prefix)
		group := guessDockerGroup(name, prefix)
		hosts = append(hosts, HostInfo{
			Name:       name,
			IP:         ip,
			ConnectCmd: connectCmd,
			Role:       role,
			Group:      group,
		})
	}

	// Build service URLs for PMM and Minio.
	var serviceURLs []ServiceURL
	host := "localhost"
	for svcName, svc := range env.Config.PmmServers {
		containerName := prefix + "-" + svcName
		port := svc.PmmPort
		if port == 0 {
			port = 8443
		}
		serviceURLs = append(serviceURLs, ServiceURL{
			Name:  containerName,
			Label: "PMM: " + svcName,
			URL:   fmt.Sprintf("https://%s:%d", host, port),
		})
	}
	for svcName, svc := range env.Config.MinioServers {
		containerName := prefix + "-" + svcName
		consolePort := svc.MinioConsolePort
		if consolePort == 0 {
			consolePort = 9001
		}
		serviceURLs = append(serviceURLs, ServiceURL{
			Name:  containerName,
			Label: "MinIO Console: " + svcName,
			URL:   fmt.Sprintf("http://%s:%d", host, consolePort),
		})
	}

	// Build MongoDB connection strings.
	mongoConns := buildDockerMongoConns(envID, env)

	msg := ""
	if len(hosts) == 0 {
		msg = "No containers found. Run Deploy first."
	}
	return hosts, serviceURLs, mongoConns, msg
}

// guessDockerRole infers a container's role from its name.
func guessDockerRole(name, prefix string) string {
	base := strings.TrimPrefix(name, prefix+"-")
	switch {
	case strings.Contains(base, "svr"):
		return "mongod"
	case strings.Contains(base, "mongos"):
		return "mongos"
	case strings.Contains(base, "arb"):
		return "arbiter"
	case strings.Contains(base, "cfg"):
		return "configsvr"
	case strings.HasPrefix(base, "pmm"):
		return "pmm"
	case strings.HasPrefix(base, "minio"):
		return "minio"
	case strings.HasPrefix(base, "ldap"):
		return "ldap"
	default:
		return "service"
	}
}

// guessDockerGroup extracts the logical group (cluster/replset name) from a
// container name.
func guessDockerGroup(name, prefix string) string {
	base := strings.TrimPrefix(name, prefix+"-")
	// Container names follow the pattern:  {group}-{role}{index}
	// e.g.  myrs-svr0, mycluster-mongos00, pmm-server
	// We split on the last dash-preceded lowercase alpha segment.
	parts := strings.Split(base, "-")
	if len(parts) >= 2 {
		// Last part is the role+index; everything before is the group.
		return strings.Join(parts[:len(parts)-1], "-")
	}
	return base
}

// buildDockerMongoConns creates MongoDB connection strings for Docker envs.
func buildDockerMongoConns(envID string, env *Environment) []MongoConnInfo {
	prefix := strDefault(env.Config.Prefix, envID)
	host := "localhost"
	var conns []MongoConnInfo

	// Replica sets: mongod nodes expose ports 27017, 27018, …
	for name := range env.Config.Replsets {
		containerPrefix := prefix + "-" + name
		// Build rs members list: host:27017,host:27018,...
		count := env.Config.Replsets[name].DataNodesPerReplset
		if count == 0 {
			count = 2
		}
		var members []string
		for i := 0; i < count; i++ {
			members = append(members, fmt.Sprintf("%s:%d", host, 27017+i))
		}
		connStr := fmt.Sprintf("mongodb://%s/?replicaSet=%s", strings.Join(members, ","), containerPrefix)
		conns = append(conns, MongoConnInfo{
			Name:       name,
			Type:       "replset",
			ConnString: connStr,
		})
	}

	// Sharded clusters: connect via mongos on port 27017
	for name := range env.Config.Clusters {
		mongosCount := env.Config.Clusters[name].MongosCount
		if mongosCount == 0 {
			mongosCount = 2
		}
		var mongosHosts []string
		for i := 0; i < mongosCount; i++ {
			mongosHosts = append(mongosHosts, fmt.Sprintf("%s:%d", host, 27017+i))
		}
		connStr := fmt.Sprintf("mongodb://%s/", strings.Join(mongosHosts, ","))
		conns = append(conns, MongoConnInfo{
			Name:       name,
			Type:       "cluster",
			ConnString: connStr,
		})
	}
	return conns
}

// collectCloudHosts parses Ansible inventory files to produce host info for
// cloud environments.
func collectCloudHosts(envID string, env *Environment) ([]HostInfo, []MongoConnInfo, string) {
	tfDir := filepath.Join(terraformDir, env.Platform)
	sshUser := strDefault(env.Config.MySSHUser, "ec2-user")

	var names []string
	for name := range env.Config.Clusters {
		names = append(names, name)
	}
	for name := range env.Config.Replsets {
		names = append(names, name)
	}
	sort.Strings(names)

	var hosts []HostInfo
	for _, name := range names {
		p := filepath.Join(tfDir, "inventory_"+name)
		content, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		groupHosts := parseInventoryHosts(string(content), name, sshUser)
		hosts = append(hosts, groupHosts...)
	}

	var mongoConns []MongoConnInfo
	// For cloud we can't easily determine IPs without running, so we use the
	// first host from each inventory group as the connection target.
	for _, name := range names {
		if _, ok := env.Config.Clusters[name]; ok {
			// Sharded cluster: connect via mongos role
			mongosIPs := hostsWithRole(hosts, name, "mongos")
			if len(mongosIPs) > 0 {
				var members []string
				for _, h := range mongosIPs {
					members = append(members, h.IP+":27017")
				}
				mongoConns = append(mongoConns, MongoConnInfo{
					Name:       name,
					Type:       "cluster",
					ConnString: "mongodb://" + strings.Join(members, ",") + "/",
				})
			}
		} else if _, ok := env.Config.Replsets[name]; ok {
			rsHosts := hostsWithRole(hosts, name, "mongod")
			if len(rsHosts) > 0 {
				var members []string
				for _, h := range rsHosts {
					members = append(members, h.IP+":27017")
				}
				mongoConns = append(mongoConns, MongoConnInfo{
					Name:       name,
					Type:       "replset",
					ConnString: fmt.Sprintf("mongodb://%s/?replicaSet=%s", strings.Join(members, ","), name),
				})
			}
		}
	}

	msg := ""
	if len(hosts) == 0 {
		msg = "No hosts found. Run Provision or Deploy first."
	}
	return hosts, mongoConns, msg
}

// parseInventoryHosts parses a simple Ansible INI-style inventory file and
// returns a HostInfo list.
func parseInventoryHosts(content, group, sshUser string) []HostInfo {
	var hosts []HostInfo
	var currentSection string
	for _, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			currentSection = strings.TrimSuffix(strings.TrimPrefix(line, "["), "]")
			continue
		}
		if strings.HasPrefix(line, "[") {
			continue
		}
		// Host line: hostname  ansible_host=IP  ansible_user=... etc.
		parts := strings.Fields(line)
		if len(parts) == 0 {
			continue
		}
		hostName := parts[0]
		ip := ""
		for _, kv := range parts[1:] {
			if strings.HasPrefix(kv, "ansible_host=") {
				ip = strings.TrimPrefix(kv, "ansible_host=")
			}
		}
		if ip == "" {
			ip = hostName
		}
		role := "mongod"
		sec := strings.ToLower(currentSection)
		switch {
		case strings.Contains(sec, "mongos"):
			role = "mongos"
		case strings.Contains(sec, "cfg") || strings.Contains(sec, "configsvr"):
			role = "configsvr"
		case strings.Contains(sec, "arb"):
			role = "arbiter"
		}
		sshCmd := fmt.Sprintf("ssh %s@%s", sshUser, ip)
		hosts = append(hosts, HostInfo{
			Name:       hostName,
			IP:         ip,
			ConnectCmd: sshCmd,
			Role:       role,
			Group:      group,
		})
	}
	return hosts
}

// hostsWithRole filters a host list by group and role.
func hostsWithRole(hosts []HostInfo, group, role string) []HostInfo {
	var out []HostInfo
	for _, h := range hosts {
		if h.Group == group && h.Role == role {
			out = append(out, h)
		}
	}
	return out
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

	// Build the sorted list of inventory filenames from the known cluster and
	// replset names so Ansible is pointed at exact files rather than a glob.
	var invNames []string
	for name := range env.Config.Clusters {
		invNames = append(invNames, name)
	}
	for name := range env.Config.Replsets {
		invNames = append(invNames, name)
	}
	sort.Strings(invNames)

	// cloudAnsibleCmd builds a shell snippet that runs ansible-playbook against
	// each known inventory file.  For "deploy" it also waits for SSH
	// connectivity on every host (up to 10 minutes) before invoking the
	// playbook, so that cloud VMs have time to finish booting.
	cloudAnsibleCmd := func(playbookPath string, waitForSSH bool) string {
		// Build effective extra-vars: config-level releases first (so the user's
		// explicit Ansible overrides can still take precedence over them).
		// json.Marshal ensures all special characters are properly escaped.
		effectiveVars := make(map[string]string)
		if env.Config.MongoRelease != "" {
			effectiveVars["mongo_release"] = env.Config.MongoRelease
		}
		if env.Config.PbmRelease != "" {
			effectiveVars["pbm_release"] = env.Config.PbmRelease
		}
		// User-specified ansible_vars override any config-level defaults.
		for k, v := range env.Config.AnsibleVars {
			effectiveVars[k] = v
		}

		extraVarsArg := ""
		if len(effectiveVars) > 0 {
			// Build an ordered map using sorted keys for deterministic output.
			type kv struct{ K, V string }
			kvs := make([]kv, 0, len(effectiveVars))
			keys := make([]string, 0, len(effectiveVars))
			for k := range effectiveVars {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				kvs = append(kvs, kv{k, effectiveVars[k]})
			}
			// Encode each key-value pair individually and assemble the JSON object.
			parts := make([]string, 0, len(kvs))
			for _, p := range kvs {
				kb, _ := json.Marshal(p.K)
				vb, _ := json.Marshal(p.V)
				parts = append(parts, string(kb)+":"+string(vb))
			}
			extraVarsArg = " --extra-vars " + shellQuote("{"+strings.Join(parts, ",")+"}")
		}

		var b strings.Builder
		for _, name := range invNames {
			inv := shellQuote("inventory_" + name)
			b.WriteString(fmt.Sprintf(
				`{ [ -f %[1]s ] || { printf "ERROR: inventory file %%s not found\n" %[1]s; exit 1; }; `,
				inv,
			))
			if waitForSSH {
				b.WriteString(fmt.Sprintf(
					`printf "Waiting for SSH on %%s (up to 10 min)…\n" %[1]s; `+
						`_ssh_ready=false; `+
						`for _n in $(seq 1 20); do `+
						`ansible -i %[1]s all -m ping --timeout=10 -o 2>&1 && { _ssh_ready=true; break; }; `+
						`printf "  attempt %%s/20 – not ready yet, retrying in 10s…\n" "$_n"; `+
						`[ "$_n" -lt 20 ] && sleep 10; done; `+
						`$_ssh_ready || { printf "ERROR: timed out waiting for SSH (%%s)\n" %[1]s; exit 1; }; `,
					inv,
				))
			}
			b.WriteString(fmt.Sprintf(
				`printf "==> ansible-playbook -i %%s\n" %[1]s; ansible-playbook -i %[1]s %[2]s%[3]s || exit $?; }`,
				inv, shellQuote(playbookPath), extraVarsArg,
			))
			b.WriteString(" && ")
		}
		// Strip trailing " && " and wrap in a no-op if invNames is empty.
		s := strings.TrimSuffix(b.String(), " && ")
		if s == "" {
			return `printf "WARNING: no clusters or replica sets configured – nothing to run\n"`
		}
		return s
	}

	// sshConfigInjectShell builds a shell snippet that, for each cluster/replset name,
	// reads the terraform-generated ssh_config_<name> file and appends it to
	// ~/.ssh/config inside a clearly delimited block so it can be removed later.
	// This must run BEFORE the ansible-ping wait so hostnames are resolvable.
	sshConfigInjectShell := func() string {
		if platform == "docker" || len(invNames) == 0 {
			return ""
		}
		var b strings.Builder
		b.WriteString(`{ _sshcfg="${HOME}/.ssh/config"; `)
		b.WriteString(`mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"; `)
		b.WriteString(`[ -f "${_sshcfg}" ] || touch "${_sshcfg}"; `)
		b.WriteString(`chmod 600 "${_sshcfg}"; `)
		for _, name := range invNames {
			src := shellQuote("ssh_config_" + name)
			begin := shellQuote("# BEGIN mongodeploy:" + envID + ":" + name)
			end := shellQuote("# END mongodeploy:" + envID + ":" + name)
			b.WriteString(fmt.Sprintf(
				`if [ -f %[1]s ]; then `+
					// Remove existing block idempotently (re-deploy case).
					`awk -v b=%[2]s -v e=%[3]s '$0==b{skip=1;next} skip&&$0==e{skip=0;next} !skip' "${_sshcfg}" > "${_sshcfg}.mongodeploy_tmp" && mv "${_sshcfg}.mongodeploy_tmp" "${_sshcfg}"; `+
					// Append fresh block.
					`printf '\n%%s\n' %[2]s >> "${_sshcfg}"; `+
					`cat %[1]s >> "${_sshcfg}"; `+
					`printf '%%s\n' %[3]s >> "${_sshcfg}"; `+
					`printf '==> Added SSH config block for %[4]s to %%s\n' "${_sshcfg}"; `+
					`fi; `,
				src, begin, end, name,
			))
		}
		b.WriteString("}")
		return " && " + b.String()
	}

	// sshConfigRemoveShell builds a shell snippet that removes the delimited
	// ssh_config blocks that were written by sshConfigInjectShell.
	sshConfigRemoveShell := func() string {
		if platform == "docker" || len(invNames) == 0 {
			return ""
		}
		var b strings.Builder
		b.WriteString(`{ _sshcfg="${HOME}/.ssh/config"; `)
		b.WriteString(`if [ -f "${_sshcfg}" ]; then `)
		for _, name := range invNames {
			begin := shellQuote("# BEGIN mongodeploy:" + envID + ":" + name)
			end := shellQuote("# END mongodeploy:" + envID + ":" + name)
			b.WriteString(fmt.Sprintf(
				`awk -v b=%[1]s -v e=%[2]s '$0==b{skip=1;next} skip&&$0==e{skip=0;next} !skip' "${_sshcfg}" > "${_sshcfg}.mongodeploy_tmp" && mv "${_sshcfg}.mongodeploy_tmp" "${_sshcfg}"; `+
					`printf '==> Removed SSH config block for %[3]s from %%s\n' "${_sshcfg}"; `,
				begin, end, name,
			))
		}
		b.WriteString("fi; }")
		return " && " + b.String()
	}

	var cmd []string
	switch action {
	case "deploy":
		// "Deploy": provision infrastructure with Terraform, then configure
		// with Ansible.  For cloud platforms, inject SSH config before Ansible
		// so that host names written by Terraform are resolvable.
		// Exposed in the UI as the "Deploy" button.
		shellCmd := fmt.Sprintf(
			"terraform init -input=false && terraform apply -auto-approve -input=false -var-file=%s",
			shellQuote(varfile),
		)
		if platform != "docker" {
			shellCmd += sshConfigInjectShell()
			shellCmd += " && " + cloudAnsibleCmd(filepath.Join(ansibleDir, "main.yml"), true)
		}
		cmd = []string{"bash", "-c", shellCmd}

	case "provision":
		// "Provision" (UI label): Cloud-only; run Terraform only (no Ansible).
		// Useful when you want to inspect or edit the inventory before running
		// configuration, or when you only need to (re-)provision infrastructure.
		if platform == "docker" {
			jsonError(w, 400, "provision action is not applicable to Docker environments")
			return
		}
		shellCmd := fmt.Sprintf(
			"terraform init -input=false && terraform apply -auto-approve -input=false -var-file=%s",
			shellQuote(varfile),
		)
		shellCmd += sshConfigInjectShell()
		cmd = []string{"bash", "-c", shellCmd}

	case "configure":
		// "Install" (UI label): Cloud-only; run Ansible only (no Terraform).
		// Allows retrying the software installation step without re-provisioning
		// infrastructure.
		if platform == "docker" {
			jsonError(w, 400, "configure action is not applicable to Docker environments")
			return
		}
		cmd = []string{"bash", "-c",
			cloudAnsibleCmd(filepath.Join(ansibleDir, "main.yml"), true),
		}

	case "reset":
		// Cloud-only: run the reset.yml playbook to wipe and re-initialize the
		// MongoDB configuration on already-running instances.
		if platform == "docker" {
			jsonError(w, 400, "reset action is not applicable to Docker environments")
			return
		}
		cmd = []string{"bash", "-c",
			cloudAnsibleCmd(filepath.Join(ansibleDir, "reset.yml"), false),
		}

	case "destroy":
		shellCmd := fmt.Sprintf(
			"terraform destroy -auto-approve -input=false -var-file=%s",
			shellQuote(varfile),
		)
		if platform != "docker" {
			shellCmd += sshConfigRemoveShell()
		}
		cmd = []string{"bash", "-c", shellCmd}

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
			cmd = []string{"bash", "-c",
				cloudAnsibleCmd(filepath.Join(ansibleDir, "stop.yml"), false),
			}
		}

	case "restart":
		if platform == "docker" {
			prefix := sanitiseShellArg(strDefault(env.Config.Prefix, envID))
			cmd = []string{"bash", "-c",
				fmt.Sprintf("docker ps -aq --filter 'name=%s-' | xargs -r docker restart", prefix),
			}
		} else {
			cmd = []string{"bash", "-c",
				cloudAnsibleCmd(filepath.Join(ansibleDir, "restart.yml"), false),
			}
		}

	default:
		jsonError(w, 400, "unknown action: "+action)
		return
	}

	// Callback: update environment status when a job finishes.
	// For destroy, mark the environment as "deleted" (kept visible in the UI
	// until the user explicitly purges it).
	onComplete := func(status string) {
		st, _ := loadState()
		e, exists := st[envID]
		if !exists {
			return
		}
		if action == "destroy" {
			if status == "success" {
				e.Status = "deleted"
				os.Remove(varfile)
			} else {
				e.Status = "destroy_failed"
			}
			e.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
			st[envID] = e
			saveState(st)
			return
		}
		// Map job status to a human-readable environment status.
		if status == "success" {
			// Map certain actions to semantic statuses instead of "action_success".
			switch action {
			case "restart":
				e.Status = "running"
			case "stop":
				e.Status = "stopped"
			case "reset":
				e.Status = "provisioned"
			case "deploy", "configure":
				// Both deploy and configure represent a fully running environment.
				e.Status = "running"
			default:
				e.Status = action + "_success"
			}
		} else {
			e.Status = action + "_failed"
		}
		now := time.Now().UTC().Format(time.RFC3339)
		e.UpdatedAt = now
		st[envID] = e
		saveState(st)
	}

	jobID := startJob(cmd, tfDir, nil, onComplete)

	env.Status = action + "_in_progress"
	env.LastJobID = jobID
	state[envID] = env
	saveState(state)

	slog.Info("action dispatched", "action", action, "env", envID, "platform", platform, "job", jobID)
	writeJSON(w, 200, map[string]string{"job_id": jobID, "status": env.Status})
}

// GET /api/environment/{env_id}/status — returns the current status of an environment.
func envStatusHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	state, _ := loadState()
	env, ok := state[envID]
	if !ok {
		jsonError(w, 404, "environment not found")
		return
	}
	writeJSON(w, 200, map[string]string{"status": env.Status, "updated_at": env.UpdatedAt})
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
	slog.Info("starting PSMDB Sandbox", "baseDir", baseDir)

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
	mux.HandleFunc("GET /api/regions/{platform}", apiRegionsHandler)
	mux.HandleFunc("GET /api/images/{platform}", apiImagesHandler)
	mux.HandleFunc("POST /api/upload-ssh-key/{platform}", apiUploadSSHKeyHandler)
	mux.HandleFunc("POST /api/environment", saveEnvironmentHandler)
	mux.HandleFunc("DELETE /api/environment/{env_id}", deleteEnvironmentHandler)
	mux.HandleFunc("DELETE /api/environments/deleted", purgeDeletedEnvironmentsHandler)
	mux.HandleFunc("GET /api/environment/{env_id}/tfvars", getTfvarsHandler)
	mux.HandleFunc("GET /api/environment/{env_id}/inventory", getInventoryHandler)
	mux.HandleFunc("GET /api/environment/{env_id}/hosts", getHostsHandler)
	mux.HandleFunc("GET /api/environment/{env_id}/status", envStatusHandler)
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
