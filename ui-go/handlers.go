package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const dockerReplsetPortStep = 20

// cleanupDockerModuleArtifacts removes files and directories that Terraform
// created inside the docker module directories (modules/mongodb_replset and
// modules/mongodb_cluster) for the given environment. These include:
//   - pbm-storage.conf.{name} files
//   - {name}-*.Dockerfile files (new sanitized naming)
//   - {name}-percona/ subdirectories (old naming, created when the image name
//     contained a "/" which Terraform mistakenly turned into a path separator)
//
// This is safe to call even when the files do not exist.
func cleanupDockerModuleArtifacts(cfg Config) {
	namePrefix := cfg.Prefix
	if namePrefix != "" {
		namePrefix += "-"
	}

	replsetDir := filepath.Join(terraformDir, "docker", "modules", "mongodb_replset")
	clusterDir := filepath.Join(terraformDir, "docker", "modules", "mongodb_cluster")

	for key := range cfg.Replsets {
		cleanupModuleResourceFiles(replsetDir, namePrefix+key)
	}
	for key := range cfg.Clusters {
		cleanupModuleResourceFiles(clusterDir, namePrefix+key)
	}
}

// cleanupModuleResourceFiles removes Terraform-generated artifacts for a single
// named resource (replica-set or cluster) inside a module directory.
func cleanupModuleResourceFiles(moduleDir, resourceName string) {
	// pbm-storage.conf.{resourceName}
	os.Remove(filepath.Join(moduleDir, "pbm-storage.conf."+resourceName))

	// {resourceName}-*.Dockerfile (sanitized image name)
	if matches, _ := filepath.Glob(filepath.Join(moduleDir, resourceName+"-*.Dockerfile")); matches != nil {
		for _, f := range matches {
			os.Remove(f)
		}
	}

	// Old-style subdirectory created when the image name contained "/" and
	// Terraform interpreted it as a directory separator (e.g. {resourceName}-percona/).
	if entries, _ := filepath.Glob(filepath.Join(moduleDir, resourceName+"-*")); entries != nil {
		for _, entry := range entries {
			if info, err := os.Stat(entry); err == nil && info.IsDir() {
				os.RemoveAll(entry)
			}
		}
	}
}

func chaosAPIReachabilityError() string {
	return "CHAOS API is unreachable from this UI host. Connect to Percona VPN and try again."
}

func chaosAPIProbeURL() string {
	if v := strings.TrimSpace(os.Getenv("CHAOS_API_PROBE_URL")); v != "" {
		return v
	}
	return "https://chaos.percona.com"
}

func canReachChaosAPI() error {
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodHead, chaosAPIProbeURL(), nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		var dnsErr *net.DNSError
		if errors.As(err, &dnsErr) {
			return dnsErr
		}
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 500 {
		return fmt.Errorf("unexpected CHAOS API probe status %d", resp.StatusCode)
	}
	return nil
}

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
	dockerDefaultPmmExternalPort := 8443
	dockerDefaultMinioPort := 9000
	dockerDefaultMinioConsolePort := 9001
	state, _ := loadState()
	if envID != "" {
		if env, ok := state[envID]; ok {
			cfg = env.Config
		}
	}
	if platform == "docker" {
		occupied := dockerOccupiedServicePorts(state, envID)
		dockerDefaultPmmExternalPort = nextFreeDockerPort(8443, occupied)
		dockerDefaultMinioPort, dockerDefaultMinioConsolePort = nextFreeDockerPortPair(9000, occupied)
	}

	// Get current OS user for SSH user field default.
	osUser := ""
	if u, err := user.Current(); err == nil {
		osUser = u.Username
	}
	if osUser == "" {
		osUser = os.Getenv("USER")
	}

	renderPage(w, "configure", ConfigureData{
		Platform:                      platform,
		EnvID:                         envID,
		Config:                        cfg,
		DefaultAuditFilter:            defaultAuditFilter,
		OSUser:                        osUser,
		DockerDefaultPmmExternalPort:  dockerDefaultPmmExternalPort,
		DockerDefaultMinioPort:        dockerDefaultMinioPort,
		DockerDefaultMinioConsolePort: dockerDefaultMinioConsolePort,
		PSMDBVersions:                 cachedPSMDBVersions(),
		PBMVersions:                   cachedPBMVersions(),
		PSMDBMinorVersions:            cachedPSMDBMinorVersionsByMajor(),
		PMMImages:                     cachedPMMServerImages(),
		PSMDBImages:                   cachedPSMDBImages(),
		PBMImages:                     cachedPBMImages(),
		PMMClientImages:               cachedPMMClientImages(),
		SortedClusters:                sortedClusters(cfg.Clusters),
		SortedReplsets:                sortedReplsets(cfg.Replsets),
		SortedPmmServers:              sortedPmmServers(cfg.PmmServers),
		SortedMinio:                   sortedMinioServers(cfg.MinioServers),
		SortedLdap:                    sortedLdapServers(cfg.LdapServers),
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
		ServiceURLs:    configServiceURLs(envID, env),
		YcsbEnabled:    env.Config.EnableYcsb,
		YcsbAvailable:  env.Status == "provisioned" || env.Status == "running" || env.Status == "stopped",
	})
}

type ycsbActionRequest struct {
	Target string `json:"target"`
	Kind   string `json:"kind"`
	Action string `json:"action"`
}

type ycsbStatusResponse struct {
	Running map[string]bool `json:"running"`
}

func ycsbDockerContainerName(envID string, env *Environment) string {
	prefix := strDefault(env.Config.Prefix, envID)
	if prefix == "" {
		prefix = envID
	}
	return prefix + "-ycsb"
}

func ycsbCloudHost(envID string, env *Environment) string {
	tfDir := filepath.Join(terraformDir, env.Platform)
	filePrefix := strDefault(env.Config.Prefix, envID)
	var names []string
	for name := range env.Config.Clusters {
		names = append(names, name)
	}
	for name := range env.Config.Replsets {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		p := filepath.Join(tfDir, filePrefix+"_inventory_"+name)
		content, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for _, h := range parseInventoryHosts(string(content), name, strDefault(env.Config.MySSHUser, "ec2-user")) {
			if h.Role == "ycsb" {
				return h.Name
			}
		}
	}
	return ""
}

func ycsbDockerMongoURL(envID string, env *Environment, kind, target string) (string, error) {
	user, pass := mongoAdminCredentials(env)
	if kind == "cluster" {
		cfg, ok := env.Config.Clusters[target]
		if !ok {
			return "", fmt.Errorf("unknown cluster %q", target)
		}
		prefix := strDefault(env.Config.Prefix, envID)
		if prefix == "" {
			prefix = envID
		}
		mongosPort := 27017
		if cfg.MongosCount == 0 {
			cfg.MongosCount = 2
		}
		return fmt.Sprintf("mongodb://%s:%s@%s-%s-mongos00:%d/?authSource=admin",
			urlQueryEscape(user), urlQueryEscape(pass), prefix, target, mongosPort), nil
	}
	if kind == "replset" {
		cfg, ok := env.Config.Replsets[target]
		if !ok {
			return "", fmt.Errorf("unknown replica set %q", target)
		}
		memberCount := cfg.DataNodesPerReplset
		if memberCount == 0 {
			memberCount = 2
		}
		basePort := cfg.ReplsetPort
		if basePort == 0 {
			basePort = 27017
		}
		var members []string
		for i := 0; i < memberCount; i++ {
			members = append(members, fmt.Sprintf("%s-svr%d:%d", target, i, basePort+i))
		}
		prefix := strDefault(env.Config.Prefix, envID)
		if prefix != "" {
			for i, member := range members {
				members[i] = prefix + "-" + member
			}
		}
		replsetName := target
		if prefix != "" {
			replsetName = prefix + "-" + target
		}
		return fmt.Sprintf("mongodb://%s:%s@%s/?replicaSet=%s&authSource=admin",
			urlQueryEscape(user), urlQueryEscape(pass), strings.Join(members, ","), replsetName), nil
	}
	return "", fmt.Errorf("unknown target kind %q", kind)
}

func ycsbCloudMongoURL(envID string, env *Environment, kind, target string) (string, error) {
	hosts, _, _ := collectCloudHosts(envID, env)
	user, pass := mongoAdminCredentials(env)
	if kind == "cluster" {
		mongosHosts := hostsWithRole(hosts, target, "mongos")
		if len(mongosHosts) == 0 {
			return "", fmt.Errorf("no mongos hosts found for cluster %q", target)
		}
		return fmt.Sprintf("mongodb://%s:%s@%s/?authSource=admin",
			urlQueryEscape(user), urlQueryEscape(pass), mongosHosts[0].Name+":27017"), nil
	}
	if kind == "replset" {
		rsHosts := hostsWithRole(hosts, target, "mongod")
		if len(rsHosts) == 0 {
			return "", fmt.Errorf("no mongod hosts found for replica set %q", target)
		}
		var members []string
		for _, h := range rsHosts {
			members = append(members, h.Name+":27017")
		}
		return fmt.Sprintf("mongodb://%s:%s@%s/?replicaSet=%s&authSource=admin",
			urlQueryEscape(user), urlQueryEscape(pass), strings.Join(members, ","), cloudReplsetName(env, target)), nil
	}
	return "", fmt.Errorf("unknown target kind %q", kind)
}

func ycsbStartCommand(mongoURL string) string {
	return fmt.Sprintf("nohup /opt/ycsb/bin/ycsb run mongodb -s -P /opt/ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url=%s > /tmp/ycsb-run.log 2>&1 < /dev/null & echo $! > /tmp/ycsb-run.pid && tail -n 20 /tmp/ycsb-run.log || true", shellQuote(mongoURL))
}

func ycsbCloudInstallPath() string {
	return "/opt/ycsb/bin/ycsb"
}

func ycsbDockerInstallPath() string {
	return "/ycsb/bin/ycsb"
}

func ycsbActionShell(envID string, env *Environment, req ycsbActionRequest) (string, error) {
	if !env.Config.EnableYcsb {
		return "", fmt.Errorf("YCSB is not enabled for this environment")
	}
	if req.Kind != "cluster" && req.Kind != "replset" {
		return "", fmt.Errorf("invalid target kind %q", req.Kind)
	}
	if req.Action != "load" && req.Action != "start" && req.Action != "stop" {
		return "", fmt.Errorf("invalid YCSB action %q", req.Action)
	}
	if req.Target == "" {
		return "", fmt.Errorf("target is required")
	}

	var mongoURL string
	var err error
	if env.Platform == "docker" {
		mongoURL, err = ycsbDockerMongoURL(envID, env, req.Kind, req.Target)
	} else {
		mongoURL, err = ycsbCloudMongoURL(envID, env, req.Kind, req.Target)
	}
	if err != nil {
		return "", err
	}

	if env.Platform == "docker" {
		container := shellQuote(ycsbDockerContainerName(envID, env))
		binary := ycsbDockerInstallPath()
		var inner string
		switch req.Action {
		case "load":
			inner = fmt.Sprintf("%s load mongodb -P /ycsb/workloads/workloada -p mongodb.url=%s", binary, shellQuote(mongoURL))
		case "start":
			inner = fmt.Sprintf("if [ -f /tmp/ycsb-run.pid ] && kill -0 \"$(cat /tmp/ycsb-run.pid)\" 2>/dev/null; then echo 'YCSB workload is already running'; exit 1; fi; nohup %s run mongodb -s -P /ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url=%s > /tmp/ycsb-run.log 2>&1 < /dev/null & echo $! > /tmp/ycsb-run.pid; echo 'YCSB workload started'; sleep 1; tail -n 20 /tmp/ycsb-run.log || true", binary, shellQuote(mongoURL))
		case "stop":
			inner = "if [ -f /tmp/ycsb-run.pid ] && kill -0 \"$(cat /tmp/ycsb-run.pid)\" 2>/dev/null; then kill \"$(cat /tmp/ycsb-run.pid)\" && rm -f /tmp/ycsb-run.pid && echo 'YCSB workload stopped'; else pkill -f '/ycsb/bin/ycsb run mongodb' >/dev/null 2>&1 && echo 'YCSB workload stopped' || { echo 'No running YCSB workload found'; exit 1; }; fi"
		}
		return fmt.Sprintf("docker exec %s sh -lc %s", container, shellQuote(inner)), nil
	}

	host := ycsbCloudHost(envID, env)
	if host == "" {
		return "", fmt.Errorf("YCSB host not found. Run Provision or Deploy first")
	}
	binary := ycsbCloudInstallPath()
	var remote string
	switch req.Action {
	case "load":
		remote = fmt.Sprintf("%s load mongodb -P /opt/ycsb/workloads/workloada -p mongodb.url=%s", binary, shellQuote(mongoURL))
	case "start":
		remote = fmt.Sprintf("if [ -f /tmp/ycsb-run.pid ] && kill -0 \"$(cat /tmp/ycsb-run.pid)\" 2>/dev/null; then echo 'YCSB workload is already running'; exit 1; fi; nohup %s run mongodb -s -P /opt/ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url=%s > /tmp/ycsb-run.log 2>&1 < /dev/null & echo $! > /tmp/ycsb-run.pid; echo 'YCSB workload started'; sleep 1; tail -n 20 /tmp/ycsb-run.log || true", binary, shellQuote(mongoURL))
	case "stop":
		remote = "if [ -f /tmp/ycsb-run.pid ] && kill -0 \"$(cat /tmp/ycsb-run.pid)\" 2>/dev/null; then kill \"$(cat /tmp/ycsb-run.pid)\" && rm -f /tmp/ycsb-run.pid && echo 'YCSB workload stopped'; else pkill -f '/opt/ycsb/bin/ycsb run mongodb' >/dev/null 2>&1 && echo 'YCSB workload stopped' || { echo 'No running YCSB workload found'; exit 1; }; fi"
	}
	return fmt.Sprintf("ssh %s %s", shellQuote(host), shellQuote(remote)), nil
}

func ycsbStatusShell(envID string, env *Environment) (string, error) {
	if !env.Config.EnableYcsb {
		return "", fmt.Errorf("YCSB is not enabled for this environment")
	}
	check := `if [ -f /tmp/ycsb-run.pid ] && kill -0 "$(cat /tmp/ycsb-run.pid)" 2>/dev/null; then printf '{"running":true}\n'; else printf '{"running":false}\n'; fi`
	if env.Platform == "docker" {
		return fmt.Sprintf("docker exec %s sh -lc %s", shellQuote(ycsbDockerContainerName(envID, env)), shellQuote(check)), nil
	}
	host := ycsbCloudHost(envID, env)
	if host == "" {
		return "", fmt.Errorf("YCSB host not found. Run Provision or Deploy first")
	}
	return fmt.Sprintf("ssh %s %s", shellQuote(host), shellQuote(check)), nil
}

func ycsbRunningTargetKey(kind, target string) string {
	return kind + ":" + target
}

func ycsbStatus(envID string, env *Environment) ycsbStatusResponse {
	resp := ycsbStatusResponse{Running: map[string]bool{}}
	if !env.Config.EnableYcsb {
		return resp
	}
	shellCmd, err := ycsbStatusShell(envID, env)
	if err != nil {
		return resp
	}
	out, err := execOutput("bash", "-c", shellCmd)
	if err != nil {
		return resp
	}
	var payload struct {
		Running bool `json:"running"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &payload); err != nil {
		return resp
	}
	for name := range env.Config.Clusters {
		resp.Running[ycsbRunningTargetKey("cluster", name)] = payload.Running
	}
	for name := range env.Config.Replsets {
		resp.Running[ycsbRunningTargetKey("replset", name)] = payload.Running
	}
	return resp
}

func urlQueryEscape(s string) string {
	replacer := strings.NewReplacer(
		"%", "%25",
		":", "%3A",
		"/", "%2F",
		"?", "%3F",
		"#", "%23",
		"[", "%5B",
		"]", "%5D",
		"@", "%40",
	)
	return replacer.Replace(s)
}

// POST /api/environment/{env_id}/ycsb
func environmentYCSBActionHandler(w http.ResponseWriter, r *http.Request) {
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
	var body ycsbActionRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, 400, "invalid JSON")
		return
	}
	shellCmd, err := ycsbActionShell(envID, env, body)
	if err != nil {
		jsonError(w, 400, err.Error())
		return
	}
	tfDir := filepath.Join(terraformDir, env.Platform)
	actionName := "ycsb_" + body.Action + "_" + body.Kind + "_" + body.Target
	startedAtTime := time.Now()
	startedAt := startedAtTime.UTC().Format(time.RFC3339)
	onComplete := func(status string) {
		durationSecs := int64(time.Since(startedAtTime).Seconds())
		st, _ := loadState()
		e, exists := st[envID]
		if !exists {
			return
		}
		outcomeStatus := "success"
		if status != "success" {
			outcomeStatus = "failed"
		}
		e.History = append(e.History, HistoryEvent{
			Action:       actionName,
			StartedAt:    startedAt,
			Status:       outcomeStatus,
			DurationSecs: durationSecs,
		})
		if status == "success" {
			e.Status = "running"
		} else {
			e.Status = actionName + "_failed"
		}
		e.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
		st[envID] = e
		saveState(st)
	}
	jobID := startJob([]string{"bash", "-c", shellCmd}, tfDir, nil, onComplete)
	env.Status = actionName + "_in_progress"
	env.LastJobID = jobID
	state[envID] = env
	saveState(state)
	writeJSON(w, 200, map[string]string{"job_id": jobID, "status": env.Status})
}

// GET /api/environment/{env_id}/ycsb/status
func environmentYCSBStatusHandler(w http.ResponseWriter, r *http.Request) {
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
	writeJSON(w, 200, ycsbStatus(envID, env))
}

// GET /api/versions
func apiVersionsHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]interface{}{
		"psmdb_versions":       getPSMDBVersions(),
		"pbm_versions":         getPBMVersions(),
		"pmm_server_images":    getPMMServerImages(),
		"psmdb_images":         getPSMDBImages(),
		"pbm_images":           getPBMImages(),
		"pmm_client_images":    getPMMClientImages(),
		"psmdb_minor_versions": getPSMDBMinorVersionsByMajor(),
	})
}

// GET /api/regions/{platform}
func apiRegionsHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	regions := getCloudRegions(platform)
	writeJSON(w, 200, map[string]interface{}{
		"regions":         regions,
		"grouped_regions": groupRegionsByGeo(platform, regions),
	})
}

// POST /api/upload-ssh-key/{platform}
func apiUploadSSHKeyHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	if !validPlatform(platform) || platform == "docker" {
		jsonError(w, 400, "invalid platform")
		return
	}
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		jsonError(w, 400, "failed to parse upload: "+err.Error())
		return
	}
	file, header, err := r.FormFile("ssh_key_file")
	if err != nil {
		jsonError(w, 400, "ssh_key_file field missing: "+err.Error())
		return
	}
	defer file.Close()

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

// GET /api/images/{platform}?region={region}
func apiImagesHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	region := r.URL.Query().Get("region")
	if region == "" {
		region = r.URL.Query().Get("location")
	}
	images, err := getCloudImages(platform, region)
	if err != nil {
		slog.Warn("cloud images fetch failed", "platform", platform, "region", region, "err", err)
		images = map[string][]CloudImage{}
	}
	writeJSON(w, 200, map[string]interface{}{"images": images})
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
		payload.EnvID = secureID(4)
	}
	if !envIDRe.MatchString(payload.EnvID) {
		jsonError(w, 400, "invalid env_id: use letters, digits, hyphens and underscores (max 40 chars)")
		return
	}
	if !validPlatform(payload.Platform) {
		jsonError(w, 400, "invalid platform")
		return
	}

	// Default the prefix to the environment name for all platforms so resources
	// are namespaced consistently. Users can override this in the form.
	if payload.Config.Prefix == "" {
		payload.Config.Prefix = payload.EnvID
	}

	// For Docker deployments, auto-assign unique port ranges to replica sets
	// that don't yet have a port assigned, to prevent collisions.
	state, err := loadState()
	if err != nil {
		jsonError(w, 500, "state load failed: "+err.Error())
		return
	}

	if payload.Platform == "docker" {
		assignDockerReplsetPorts(&payload.Config)
		if err := validateDockerPortConflicts(payload.EnvID, payload.Config, state); err != nil {
			jsonError(w, 400, err.Error())
			return
		}
	}

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

	if env != nil {
		p := tfvarsPath(envID, env.Platform)
		os.Remove(p)
		os.Remove(tfstatePath(envID, env.Platform))
		os.Remove(tfstateBackupPath(envID, env.Platform))
		if env.Platform == "docker" {
			cleanupDockerModuleArtifacts(env.Config)
		}
	} else {
		for _, pl := range platforms {
			os.Remove(tfvarsPath(envID, pl))
			os.Remove(tfstatePath(envID, pl))
			os.Remove(tfstateBackupPath(envID, pl))
		}
	}
	writeJSON(w, 200, map[string]string{"status": "deleted"})
}

// DELETE /api/environments/deleted
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
			os.Remove(tfstatePath(id, env.Platform))
			os.Remove(tfstateBackupPath(id, env.Platform))
			if env.Platform == "docker" {
				cleanupDockerModuleArtifacts(env.Config)
			}
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
	filePrefix := strDefault(env.Config.Prefix, envID)
	var files []invFile
	for _, name := range names {
		p := filepath.Join(tfDir, filePrefix+"_inventory_"+name)
		content, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		files = append(files, invFile{Name: filePrefix + "_inventory_" + name, Content: string(content)})
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

// GET /api/environment/{env_id}/hosts
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
		// Persist any newly discovered IPs so they survive container stop.
		if len(hosts) > 0 {
			updated := false
			if env.HostIPs == nil {
				env.HostIPs = make(map[string]string)
			}
			for _, h := range hosts {
				if h.IP != "" && h.IP != "—" {
					if env.HostIPs[h.Name] != h.IP {
						env.HostIPs[h.Name] = h.IP
						updated = true
					}
				}
			}
			if updated {
				state[envID] = env
				saveState(state) //nolint:errcheck
			}
		}
	} else {
		hosts, mongoConns, msg = collectCloudHosts(envID, env)
		serviceURLs = configServiceURLs(envID, env)
	}

	writeJSON(w, 200, map[string]interface{}{
		"hosts":        hosts,
		"service_urls": serviceURLs,
		"mongo_conns":  mongoConns,
		"message":      msg,
	})
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

	if platform == "chaos" {
		switch action {
		case "deploy", "stop", "restart", "destroy":
			if err := canReachChaosAPI(); err != nil {
				slog.Warn("chaos api unreachable", "env", envID, "action", action, "err", err)
				jsonError(w, http.StatusBadGateway, chaosAPIReachabilityError())
				return
			}
		}
	}

	if _, err := os.Stat(varfile); os.IsNotExist(err) {
		if wErr := writeTfvars(envID, platform, env.Config); wErr != nil {
			jsonError(w, 500, "tfvars not found and could not be regenerated: "+wErr.Error())
			return
		}
	}

	var invNames []string
	for name := range env.Config.Clusters {
		invNames = append(invNames, name)
	}
	for name := range env.Config.Replsets {
		invNames = append(invNames, name)
	}
	sort.Strings(invNames)

	// filePrefix is prepended to generated inventory and ssh_config filenames so
	// that multiple environments sharing the same Terraform directory do not
	// overwrite each other's files (e.g. "myenv_inventory_cl01").
	filePrefix := strDefault(env.Config.Prefix, envID)

	cloudAnsibleCmd := func(playbookPath string, waitForSSH bool) string {
		effectiveVars := make(map[string]string)
		// Note: mongo_release, mongo_version, pbm_release, pbm_version are now written
		// into the inventory [all:vars] section via Terraform variables, so they are
		// not included here in --extra-vars.
		for k, v := range env.Config.AnsibleVars {
			effectiveVars[k] = v
		}

		extraVarsArg := ""
		if len(effectiveVars) > 0 {
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
			inv := shellQuote(filePrefix + "_inventory_" + name)
			b.WriteString(fmt.Sprintf(
				`{ [ -f %[1]s ] || { printf "ERROR: inventory file %%s not found\n" %[1]s; exit 1; }; `,
				inv,
			))
			if waitForSSH {
				b.WriteString(fmt.Sprintf(
					`printf "Waiting for SSH on %%s (up to 10 min)…\n" %[1]s; `+
						`_ssh_ready=false; `+
						`for _n in $(seq 1 20); do `+
						`ansible -i %[1]s all -m ping --timeout=10 2>&1 && { _ssh_ready=true; break; }; `+
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
		s := strings.TrimSuffix(b.String(), " && ")
		if s == "" {
			return `printf "WARNING: no clusters or replica sets configured – nothing to run\n"`
		}
		return s
	}

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
			src := shellQuote(filePrefix + "_ssh_config_" + name)
			begin := shellQuote("# BEGIN mongodeploy:" + envID + ":" + name)
			end := shellQuote("# END mongodeploy:" + envID + ":" + name)
			b.WriteString(fmt.Sprintf(
				`if [ -f %[1]s ]; then `+
					`awk -v b=%[2]s -v e=%[3]s '$0==b{skip=1;next} skip&&$0==e{skip=0;next} !skip' "${_sshcfg}" > "${_sshcfg}.mongodeploy_tmp" && mv "${_sshcfg}.mongodeploy_tmp" "${_sshcfg}"; `+
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

	// Per-environment Terraform state file: stored alongside the tfvars file in
	// the platform directory so different environments do not share state and
	// can be operated concurrently.
	envStateFile := envID + ".tfstate" // relative to tfDir (the CWD for terraform)
	backendPathArg := shellQuote("path=" + envStateFile)

	var cmd []string
	switch action {
	case "deploy":
		shellCmd := fmt.Sprintf(
			"terraform init -reconfigure -input=false -backend-config=%s && terraform apply -auto-approve -input=false -var-file=%s",
			backendPathArg,
			shellQuote(varfile),
		)
		if platform != "docker" {
			shellCmd += sshConfigInjectShell()
			shellCmd += " && " + cloudAnsibleCmd(filepath.Join(ansibleDir, "main.yml"), true)
		}
		cmd = []string{"bash", "-c", shellCmd}

	case "provision":
		if platform == "docker" {
			jsonError(w, 400, "provision action is not applicable to Docker environments")
			return
		}
		shellCmd := fmt.Sprintf(
			"terraform init -reconfigure -input=false -backend-config=%s && terraform apply -auto-approve -input=false -var-file=%s",
			backendPathArg,
			shellQuote(varfile),
		)
		shellCmd += sshConfigInjectShell()
		cmd = []string{"bash", "-c", shellCmd}

	case "configure":
		if platform == "docker" {
			jsonError(w, 400, "configure action is not applicable to Docker environments")
			return
		}
		cmd = []string{"bash", "-c",
			cloudAnsibleCmd(filepath.Join(ansibleDir, "main.yml"), true),
		}

	case "reset":
		if platform == "docker" {
			jsonError(w, 400, "reset action is not applicable to Docker environments")
			return
		}
		cmd = []string{"bash", "-c",
			cloudAnsibleCmd(filepath.Join(ansibleDir, "reset.yml"), false),
		}

	case "destroy":
		shellCmd := fmt.Sprintf(
			"terraform init -reconfigure -input=false -backend-config=%s && terraform destroy -auto-approve -input=false -var-file=%s",
			backendPathArg,
			shellQuote(varfile),
		)
		if platform != "docker" {
			shellCmd += sshConfigRemoveShell()
		}
		cmd = []string{"bash", "-c", shellCmd}

	case "stop":
		if platform == "docker" {
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

	startedAtTime := time.Now()
	startedAt := startedAtTime.UTC().Format(time.RFC3339)

	onComplete := func(status string) {
		durationSecs := int64(time.Since(startedAtTime).Seconds())
		st, _ := loadState()
		e, exists := st[envID]
		if !exists {
			return
		}
		// Record the event in the environment's history.
		outcomeStatus := "success"
		if status != "success" {
			outcomeStatus = "failed"
		}
		e.History = append(e.History, HistoryEvent{
			Action:       action,
			StartedAt:    startedAt,
			Status:       outcomeStatus,
			DurationSecs: durationSecs,
		})
		if action == "destroy" {
			if status == "success" {
				e.Status = "deleted"
				os.Remove(varfile)
				os.Remove(tfstatePath(envID, platform))
				os.Remove(tfstateBackupPath(envID, platform))
				if platform == "docker" {
					cleanupDockerModuleArtifacts(e.Config)
				}
			} else {
				e.Status = "destroy_failed"
			}
			e.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
			st[envID] = e
			saveState(st)
			return
		}
		if status == "success" {
			switch action {
			case "restart":
				e.Status = "running"
			case "stop":
				e.Status = "stopped"
			case "reset":
				e.Status = "provisioned"
			case "deploy", "configure":
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

	extraEnv := map[string]string{
		"ANSIBLE_CONFIG": filepath.Join(ansibleDir, "ansible.cfg"),
	}
	// For CHAOS environments, pass the API token via an environment variable so
	// it is never written to the tfvars file on disk.
	if platform == "chaos" && env.Config.ChaosApiToken != "" {
		extraEnv["CHAOS_API_TOKEN"] = env.Config.ChaosApiToken
	}

	jobID := startJob(cmd, tfDir, extraEnv, onComplete)

	env.Status = action + "_in_progress"
	env.LastJobID = jobID
	state[envID] = env
	saveState(state)

	slog.Info("action dispatched", "action", action, "env", envID, "platform", platform, "job", jobID)
	writeJSON(w, 200, map[string]string{"job_id": jobID, "status": env.Status})
}

// GET /api/environment/{env_id}/chaos/reachability
func chaosReachabilityHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	state, _ := loadState()
	env, ok := state[envID]
	if !ok {
		jsonError(w, 404, "environment not found")
		return
	}
	if env.Platform != "chaos" {
		jsonError(w, 400, "reachability check is only available for chaos environments")
		return
	}
	if err := canReachChaosAPI(); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]interface{}{
			"reachable": false,
			"error":     chaosAPIReachabilityError(),
		})
		return
	}
	writeJSON(w, 200, map[string]bool{"reachable": true})
}

// GET /api/environment/{env_id}/history
func envHistoryHandler(w http.ResponseWriter, r *http.Request) {
	envID := r.PathValue("env_id")
	state, _ := loadState()
	env, ok := state[envID]
	if !ok {
		jsonError(w, 404, "environment not found")
		return
	}
	history := env.History
	if history == nil {
		history = []HistoryEvent{}
	}
	writeJSON(w, 200, history)
}

// GET /api/environment/{env_id}/status
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

	for i := 0; i < 20; i++ {
		if _, err := os.Stat(logPath); err == nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	var pos int64
	ctx := r.Context()
	for {
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
	writeJSON(w, 200, map[string]string{"log": stripAnsi(string(content)), "status": status})
}

// assignDockerReplsetPorts auto-assigns unique port ranges to Docker replica
// sets that don't yet have a replset_port set, to avoid collisions when
// multiple replica sets are deployed in the same Docker environment.
// Each replica set receives a block of 20 ports (enough for 7 data nodes + 3
// arbiters). Existing non-zero port assignments are preserved; only zero-valued
// ones receive a new assignment starting above the current maximum.
func assignDockerReplsetPorts(cfg *Config) {
	if len(cfg.Replsets) == 0 {
		return
	}

	occupied := make(map[int]struct{})
	maxPort := 27017 - dockerReplsetPortStep

	for _, nr := range sortedReplsets(cfg.Replsets) {
		rs := nr.Config
		if rs.ReplsetPort > maxPort {
			maxPort = rs.ReplsetPort
		}
		if rs.ReplsetPort == 0 {
			continue
		}
		for _, port := range dockerReplsetPorts(rs) {
			occupied[port] = struct{}{}
		}
	}

	for _, svc := range cfg.PmmServers {
		port := svc.PmmExternalPort
		if port == 0 {
			port = svc.PmmPort
		}
		if port != 0 {
			occupied[port] = struct{}{}
		}
	}
	for _, svc := range cfg.MinioServers {
		if svc.MinioPort != 0 {
			occupied[svc.MinioPort] = struct{}{}
		}
		if svc.MinioConsolePort != 0 {
			occupied[svc.MinioConsolePort] = struct{}{}
		}
	}
	for _, svc := range cfg.LdapServers {
		if svc.LdapPort != 0 {
			occupied[svc.LdapPort] = struct{}{}
		}
	}

	nextPort := maxPort + dockerReplsetPortStep
	if nextPort < 27017 {
		nextPort = 27017
	}
	for _, nr := range sortedReplsets(cfg.Replsets) {
		rs := cfg.Replsets[nr.Name]
		if rs.ReplsetPort == 0 {
			for !dockerReplsetPortRangeFree(nextPort, rs, occupied) {
				nextPort += dockerReplsetPortStep
			}
			rs.ReplsetPort = nextPort
			rs.ArbiterPort = nextPort
			for _, port := range dockerReplsetPorts(rs) {
				occupied[port] = struct{}{}
			}
			nextPort += dockerReplsetPortStep
		} else if rs.ArbiterPort == 0 {
			rs.ArbiterPort = rs.ReplsetPort
		}
		cfg.Replsets[nr.Name] = rs
	}
}

func dockerReplsetPortRangeFree(startPort int, rs ReplsetConfig, occupied map[int]struct{}) bool {
	candidate := rs
	candidate.ReplsetPort = startPort
	candidate.ArbiterPort = startPort
	for _, port := range dockerReplsetPorts(candidate) {
		if _, exists := occupied[port]; exists {
			return false
		}
	}
	return true
}

func dockerReplsetPorts(rs ReplsetConfig) []int {
	if rs.ReplsetPort == 0 {
		return nil
	}

	arbiterBase := rs.ArbiterPort
	if arbiterBase == 0 {
		arbiterBase = rs.ReplsetPort
	}
	dataNodes := rs.DataNodesPerReplset
	if dataNodes <= 0 {
		dataNodes = 2
	}
	arbiters := 0
	if rs.ArbitersPerReplset != nil {
		arbiters = *rs.ArbitersPerReplset
	}
	if arbiters < 0 {
		arbiters = 0
	}

	ports := make([]int, 0, dataNodes+arbiters)
	for i := 0; i < dataNodes; i++ {
		ports = append(ports, rs.ReplsetPort+i)
	}
	for i := 0; i < arbiters; i++ {
		ports = append(ports, arbiterBase+dataNodes+i)
	}
	return ports
}

func dockerOccupiedServicePorts(state map[string]*Environment, excludeEnvID string) map[int]struct{} {
	occupied := make(map[int]struct{})
	for envID, env := range state {
		if envID == excludeEnvID || env == nil || env.Platform != "docker" || env.Status != "running" {
			continue
		}
		for _, svc := range env.Config.PmmServers {
			port := svc.PmmExternalPort
			if port == 0 {
				port = svc.PmmPort
			}
			if port > 0 {
				occupied[port] = struct{}{}
			}
		}
		for _, svc := range env.Config.MinioServers {
			if svc.MinioPort > 0 {
				occupied[svc.MinioPort] = struct{}{}
			}
			if svc.MinioConsolePort > 0 {
				occupied[svc.MinioConsolePort] = struct{}{}
			}
		}
	}
	return occupied
}

func nextFreeDockerPort(start int, occupied map[int]struct{}) int {
	port := start
	for {
		if _, exists := occupied[port]; !exists {
			return port
		}
		port++
	}
}

func nextFreeDockerPortPair(start int, occupied map[int]struct{}) (int, int) {
	port := start
	for {
		if _, exists := occupied[port]; exists {
			port++
			continue
		}
		if _, exists := occupied[port+1]; exists {
			port++
			continue
		}
		return port, port + 1
	}
}

func addDockerConfigPortUsers(cfg Config, portUsers map[int][]string, labelPrefix string) {
	addPortUser := func(port int, user string) {
		if port <= 0 {
			return
		}
		portUsers[port] = append(portUsers[port], user)
	}

	for _, nr := range sortedReplsets(cfg.Replsets) {
		for _, port := range dockerReplsetPorts(nr.Config) {
			addPortUser(port, fmt.Sprintf("%sreplica set", labelPrefix))
		}
	}
	for _, ns := range sortedPmmServers(cfg.PmmServers) {
		port := ns.Config.PmmExternalPort
		if port == 0 {
			port = ns.Config.PmmPort
		}
		addPortUser(port, fmt.Sprintf("%sPMM server", labelPrefix))
	}
	for _, ns := range sortedMinioServers(cfg.MinioServers) {
		addPortUser(ns.Config.MinioPort, fmt.Sprintf("%sMinIO API", labelPrefix))
		addPortUser(ns.Config.MinioConsolePort, fmt.Sprintf("%sMinIO console", labelPrefix))
	}
	for _, ns := range sortedLdapServers(cfg.LdapServers) {
		addPortUser(ns.Config.LdapPort, fmt.Sprintf("%sLDAP server", labelPrefix))
	}
}

func validateDockerPortConflicts(envID string, cfg Config, state map[string]*Environment) error {
	portUsers := make(map[int][]string)
	addDockerConfigPortUsers(cfg, portUsers, "this environment ")

	for otherEnvID, env := range state {
		if otherEnvID == envID || env == nil || env.Platform != "docker" || env.Status != "running" {
			continue
		}
		addDockerConfigPortUsers(env.Config, portUsers, fmt.Sprintf("environment %s ", otherEnvID))
	}

	var conflicts []string
	for port, users := range portUsers {
		if len(users) < 2 {
			continue
		}
		sort.Strings(users)
		conflicts = append(conflicts, fmt.Sprintf("port %d is used by %s", port, strings.Join(users, " and ")))
	}
	if len(conflicts) == 0 {
		return nil
	}
	sort.Strings(conflicts)
	return fmt.Errorf("docker port conflicts detected:\n- %s", strings.Join(conflicts, "\n- "))
}
