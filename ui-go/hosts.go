package main

import (
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// execOutput runs the given command and returns its combined stdout as a
// trimmed string.  Stderr is discarded so callers only see clean output.
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

// collectDockerHosts uses `docker inspect` to gather container info for a
// Docker-based environment.
func collectDockerHosts(envID string, env *Environment) ([]HostInfo, []ServiceURL, []MongoConnInfo, string) {
	prefix := strDefault(env.Config.Prefix, envID)
	out, err := execOutput("docker", "ps", "-a",
		"--filter", "name="+prefix+"-",
		"--format", "{{.Names}}")
	if err != nil || strings.TrimSpace(out) == "" {
		return nil, nil, nil, "No containers found. Run Deploy first."
	}

	var hosts []HostInfo

	names := strings.Split(strings.TrimSpace(out), "\n")
	for _, rawName := range names {
		name := strings.TrimPrefix(strings.TrimSpace(rawName), "/")
		if name == "" {
			continue
		}
		// Skip transient init containers – they exit immediately after setup and
		// have no useful IP or connect command to show the user.
		if strings.HasSuffix(name, "-init_keyfile_container") {
			continue
		}
		// Use a newline separator so that containers attached to multiple Docker
		// networks (e.g. pmm-client sidecars that sit on both the default bridge
		// and the custom network) don't produce a concatenated, unparseable IP
		// string like "172.17.0.3172.20.0.5".  We take the first non-empty value.
		ipOut, err := execOutput("docker", "inspect",
			"--format", "{{range .NetworkSettings.Networks}}{{if .IPAddress}}{{.IPAddress}}\n{{end}}{{end}}", name)
		ip := ""
		for _, line := range strings.Split(ipOut, "\n") {
			if line = strings.TrimSpace(line); line != "" {
				ip = line
				break
			}
		}
		if (err != nil || ip == "") && env.HostIPs != nil {
			// Container is stopped – fall back to the last-known IP so the UI
			// continues to show meaningful addresses.
			if cached, ok := env.HostIPs[name]; ok && cached != "" && cached != "—" {
				ip = cached
			}
		}
		if ip == "" {
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

	serviceURLs := configServiceURLs(envID, env)
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
	case strings.HasSuffix(base, "-pbm-agent"):
		return "pbm-agent"
	case strings.HasSuffix(base, "-pbm-cli"):
		return "pbm-cli"
	case strings.HasSuffix(base, "-pmm-client"):
		return "pmm-client"
	case strings.HasSuffix(base, "-pmm"):
		return "pmm"
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
	switch guessDockerRole(name, prefix) {
	case "pmm":
		return "PMM"
	case "pmm-client":
		return "PMM Clients"
	case "pbm-agent", "pbm-cli":
		return "PBM"
	}
	base := strings.TrimPrefix(name, prefix+"-")
	parts := strings.Split(base, "-")
	if len(parts) >= 2 {
		return strings.Join(parts[:len(parts)-1], "-")
	}
	return base
}

// buildDockerMongoConns creates MongoDB connection strings for Docker envs.
func buildDockerMongoConns(envID string, env *Environment) []MongoConnInfo {
	prefix := strDefault(env.Config.Prefix, envID)
	host := "localhost"
	user, pass := mongoAdminCredentials(env)
	encodedPass := url.QueryEscape(pass)
	var conns []MongoConnInfo

	for name := range env.Config.Replsets {
		containerPrefix := prefix + "-" + name
		rs := env.Config.Replsets[name]
		count := rs.DataNodesPerReplset
		if count == 0 {
			count = 2
		}
		basePort := rs.ReplsetPort
		if basePort == 0 {
			basePort = 27017
		}
		var members []string
		for i := 0; i < count; i++ {
			members = append(members, fmt.Sprintf("%s:%d", host, basePort+i))
		}
		connStr := fmt.Sprintf("mongodb://%s:%s@%s/?replicaSet=%s&authSource=admin",
			url.QueryEscape(user), encodedPass, strings.Join(members, ","), containerPrefix)
		conns = append(conns, MongoConnInfo{
			Name:       name,
			Type:       "replset",
			ConnString: connStr,
			ConnUser:   user,
			ConnPass:   pass,
		})
	}

	for name := range env.Config.Clusters {
		mongosCount := env.Config.Clusters[name].MongosCount
		if mongosCount == 0 {
			mongosCount = 2
		}
		// Build connection string using the actual host ports of the mongos
		// containers.  Each container is named "{prefix}-{cluster}-mongos0{i}"
		// (matching the Terraform mongos_tag default "mongos") and exposes a
		// single port.  We query Docker for the external host port so the
		// string is correct regardless of which port Docker chose.
		clusterPrefix := prefix + "-" + name
		var mongosHosts []string
		for i := 0; i < mongosCount; i++ {
			containerName := fmt.Sprintf("%s-mongos0%d", clusterPrefix, i)
			hostPort := dockerContainerHostPort(containerName)
			if hostPort == "" {
				// Docker not available or container not running – fall back to
				// the well-known default port so something is shown.
				hostPort = "27017"
			}
			mongosHosts = append(mongosHosts, fmt.Sprintf("%s:%s", host, hostPort))
		}
		connStr := fmt.Sprintf("mongodb://%s:%s@%s/?authSource=admin",
			url.QueryEscape(user), encodedPass, strings.Join(mongosHosts, ","))
		conns = append(conns, MongoConnInfo{
			Name:       name,
			Type:       "cluster",
			ConnString: connStr,
			ConnUser:   user,
			ConnPass:   pass,
		})
	}
	return conns
}

// dockerContainerHostPort returns the first external host port bound for the
// given Docker container.  It uses "docker inspect" with a Go template that
// iterates over NetworkSettings.Ports (populated for running containers,
// contains the actual auto-assigned port).  HostConfig.PortBindings is NOT
// used because when Terraform omits an explicit external port, Docker records
// HostPort as "0" there (meaning "auto-assign"), and the real port only
// appears in NetworkSettings.Ports once the container is running.
// Returns an empty string when the container is not found, not running, or
// has no port bindings.
func dockerContainerHostPort(containerName string) string {
	out, err := execOutput("docker", "inspect",
		"--format", `{{range $p, $bindings := .NetworkSettings.Ports}}{{range $bindings}}{{.HostPort}} {{end}}{{end}}`,
		containerName)
	if err != nil {
		return ""
	}
	for _, f := range strings.Fields(out) {
		if f != "" && f != "0" {
			return f
		}
	}
	return ""
}

// mongoAdminCredentials returns the MongoDB admin username and password for
// the environment.
func mongoAdminCredentials(env *Environment) (user, pass string) {
	user = "root"
	pass = "percona"
	if v, ok := env.Config.AnsibleVars["mongo_admin_user"]; ok && v != "" {
		user = v
	}
	if v, ok := env.Config.AnsibleVars["mongo_admin_password"]; ok && v != "" {
		pass = v
	}
	return
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
	filePrefix := strDefault(env.Config.Prefix, envID)
	for _, name := range names {
		p := filepath.Join(tfDir, filePrefix+"_inventory_"+name)
		content, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		groupHosts := parseInventoryHosts(string(content), name, sshUser)
		hosts = append(hosts, groupHosts...)
	}

	var mongoConns []MongoConnInfo
	user, pass := mongoAdminCredentials(env)
	encodedPass := url.QueryEscape(pass)
	for _, name := range names {
		if _, ok := env.Config.Clusters[name]; ok {
			mongosHosts := hostsWithRole(hosts, name, "mongos")
			if len(mongosHosts) > 0 {
				var members []string
				for _, h := range mongosHosts {
					members = append(members, h.IP+":27017")
				}
				connStr := fmt.Sprintf("mongodb://%s:%s@%s/?authSource=admin",
					url.QueryEscape(user), encodedPass, strings.Join(members, ","))
				mongoConns = append(mongoConns, MongoConnInfo{
					Name:       name,
					Type:       "cluster",
					ConnString: connStr,
					ConnUser:   user,
					ConnPass:   pass,
				})
			}
		} else if _, ok := env.Config.Replsets[name]; ok {
			rsHosts := hostsWithRole(hosts, name, "mongod")
			if len(rsHosts) > 0 {
				var members []string
				for _, h := range rsHosts {
					members = append(members, h.IP+":27017")
				}
				connStr := fmt.Sprintf("mongodb://%s:%s@%s/?replicaSet=%s&authSource=admin",
					url.QueryEscape(user), encodedPass, strings.Join(members, ","), name)
				mongoConns = append(mongoConns, MongoConnInfo{
					Name:       name,
					Type:       "replset",
					ConnString: connStr,
					ConnUser:   user,
					ConnPass:   pass,
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
	skipSection := false
	for _, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			currentSection = strings.TrimSuffix(strings.TrimPrefix(line, "["), "]")
			skipSection = strings.HasSuffix(currentSection, ":vars") || strings.HasSuffix(currentSection, ":children")
			continue
		}
		if strings.HasPrefix(line, "[") {
			continue
		}
		if skipSection {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) == 0 {
			continue
		}
		hostName := parts[0]
		if strings.Contains(hostName, "=") {
			continue
		}
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
		case strings.Contains(sec, "arb") || strings.Contains(sec, "arbiter"):
			role = "arbiter"
		case strings.Contains(sec, "pmm"):
			role = "pmm"
		case strings.Contains(sec, "minio"):
			role = "minio"
		}
		// Service hosts (minio, pmm) get their own logical group so they appear in
		// a separate subsection rather than inside the replica-set/cluster group.
		hostGroup := group
		switch role {
		case "minio":
			hostGroup = "Minio"
		case "pmm":
			hostGroup = "PMM"
		}
		sshCmd := fmt.Sprintf("ssh %s@%s", sshUser, ip)
		hosts = append(hosts, HostInfo{
			Name:       hostName,
			IP:         ip,
			ConnectCmd: sshCmd,
			Role:       role,
			Group:      hostGroup,
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

// configServiceURLs derives PMM and Minio console URLs from the environment
// configuration.
func configServiceURLs(envID string, env *Environment) []ServiceURL {
	prefix := strDefault(env.Config.Prefix, envID)
	var urls []ServiceURL

	if env.Platform == "docker" {
		host := "localhost"
		for svcName, svc := range env.Config.PmmServers {
			port := svc.PmmExternalPort
			if port == 0 {
				port = svc.PmmPort
			}
			if port == 0 {
				port = 8443
			}
			urls = append(urls, ServiceURL{
				Name:  prefix + "-" + svcName,
				Label: "PMM: " + svcName,
				URL:   fmt.Sprintf("https://%s:%d", host, port),
			})
		}
		for svcName, svc := range env.Config.MinioServers {
			consolePort := svc.MinioConsolePort
			if consolePort == 0 {
				consolePort = 9001
			}
			urls = append(urls, ServiceURL{
				Name:  prefix + "-" + svcName,
				Label: "MinIO Console: " + svcName,
				URL:   fmt.Sprintf("http://%s:%d", host, consolePort),
			})
		}
	} else if env.Platform == "chaos" {
		// CHAOS: Minio console access URL is derived from inventory files.
		// We look for the minio host in the inventory files.
		tfDir := filepath.Join(terraformDir, "chaos")
		var names []string
		for name := range env.Config.Clusters {
			names = append(names, name)
		}
		for name := range env.Config.Replsets {
			names = append(names, name)
		}
		sort.Strings(names)
		minioHost := ""
		minioIP := ""
		filePrefix2 := strDefault(env.Config.Prefix, envID)
		for _, name := range names {
			p := filepath.Join(tfDir, filePrefix2+"_inventory_"+name)
			content, err := os.ReadFile(p)
			if err != nil {
				continue
			}
			// Find the minio group and its host
			inMinio := false
			for _, line := range strings.Split(string(content), "\n") {
				line = strings.TrimSpace(line)
				if line == "[minio]" {
					inMinio = true
					continue
				}
				if strings.HasPrefix(line, "[") {
					inMinio = false
					continue
				}
				if inMinio && line != "" {
					parts := strings.Fields(line)
					minioHost = parts[0]
					for _, kv := range parts[1:] {
						if strings.HasPrefix(kv, "ansible_host=") {
							minioIP = strings.TrimPrefix(kv, "ansible_host=")
						}
					}
					break
				}
			}
			if minioHost != "" {
				break
			}
		}
		if minioHost != "" || minioIP != "" {
			host := minioIP
			if host == "" {
				host = minioHost
			}
			consolePort := env.Config.MinioConsolePort
			if consolePort == 0 {
				consolePort = 9001
			}
			urls = append(urls, ServiceURL{
				Name:  "minio",
				Label: "MinIO Console",
				URL:   fmt.Sprintf("http://%s:%d", host, consolePort),
			})
		}
		// PMM URL for CHAOS (via SSH port forward like other cloud platforms)
		if v := env.Config.EnablePmm; v != nil && *v {
			portStr := env.Config.PortToForward
			if portStr == "" {
				portStr = "23443"
			}
			urls = append(urls, ServiceURL{
				Name:  "pmm",
				Label: "PMM",
				URL:   fmt.Sprintf("https://127.0.0.1:%s", portStr),
			})
		}
	} else {
		// Cloud deployments: PMM port is restricted to the internal subnet by the
		// firewall (source_ranges = subnet CIDR), so it cannot be reached from the
		// client machine via the public IP.  Users access PMM through an SSH local
		// port-forward set up by the generated ssh_config file:
		//   LocalForward <port_to_forward> 127.0.0.1:<pmm_port>
		// Therefore the correct URL is always https://127.0.0.1:<port_to_forward>.
		if v := env.Config.EnablePmm; v != nil && *v {
			portStr := env.Config.PortToForward
			if portStr == "" {
				portStr = "23443"
			}
			urls = append(urls, ServiceURL{
				Name:  "pmm",
				Label: "PMM",
				URL:   fmt.Sprintf("https://127.0.0.1:%s", portStr),
			})
		}
	}
	return urls
}
