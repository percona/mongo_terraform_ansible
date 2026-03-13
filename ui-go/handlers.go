package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

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
	if envID != "" {
		state, _ := loadState()
		if env, ok := state[envID]; ok {
			cfg = env.Config
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
		ServiceURLs:    configServiceURLs(envID, env),
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
	var files []invFile
	for _, name := range names {
		p := filepath.Join(tfDir, "inventory_"+name)
		content, err := os.ReadFile(p)
		if err != nil {
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

	cloudAnsibleCmd := func(playbookPath string, waitForSSH bool) string {
		effectiveVars := make(map[string]string)
		if env.Config.MongoRelease != "" {
			effectiveVars["mongo_release"] = env.Config.MongoRelease
		}
		if env.Config.PbmRelease != "" {
			effectiveVars["pbm_release"] = env.Config.PbmRelease
		}
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
			src := shellQuote("ssh_config_" + name)
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

	var cmd []string
	switch action {
	case "deploy":
		shellCmd := fmt.Sprintf(
			"terraform init -input=false && terraform apply -auto-approve -input=false -var-file=%s -state=%s",
			shellQuote(varfile),
			shellQuote(envStateFile),
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
			"terraform init -input=false && terraform apply -auto-approve -input=false -var-file=%s -state=%s",
			shellQuote(varfile),
			shellQuote(envStateFile),
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
			"terraform destroy -auto-approve -input=false -var-file=%s -state=%s",
			shellQuote(varfile),
			shellQuote(envStateFile),
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

	jobID := startJob(cmd, tfDir, nil, onComplete)

	env.Status = action + "_in_progress"
	env.LastJobID = jobID
	state[envID] = env
	saveState(state)

	slog.Info("action dispatched", "action", action, "env", envID, "platform", platform, "job", jobID)
	writeJSON(w, 200, map[string]string{"job_id": jobID, "status": env.Status})
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
