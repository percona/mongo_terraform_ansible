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
		port := dockerContainerPorts(name)
		hosts = append(hosts, HostInfo{
			Name:       name,
			IP:         ip,
			Port:       port,
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
	case strings.HasPrefix(base, "ycsb"):
		return "ycsb"
	case strings.HasPrefix(base, "pcsm"):
		return "pcsm"
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
	case "ycsb":
		return "YCSB"
	case "pcsm":
		return "ClusterSync"
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

func cloudReplsetName(env *Environment, group string) string {
	_ = env
	return group
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

// dockerContainerPorts returns the host-side ports bound for the given Docker
// container for display in the Hosts & Connections table.  Only the external
// (host-reachable) HostPort values from NetworkSettings.Ports are used, so
// the displayed port matches what is actually accessible from the host machine.
// Multiple ports are comma-separated.
func dockerContainerPorts(containerName string) string {
	out, err := execOutput("docker", "inspect",
		"--format", `{{range $p, $bindings := .NetworkSettings.Ports}}{{range $bindings}}{{.HostPort}} {{end}}{{end}}`,
		containerName)
	if err != nil {
		return "—"
	}
	ports := make(map[string]struct{})
	for _, f := range strings.Fields(out) {
		if f != "" && f != "0" {
			ports[f] = struct{}{}
		}
	}
	if len(ports) == 0 {
		return "—"
	}
	var ordered []string
	for port := range ports {
		ordered = append(ordered, port)
	}
	sort.Strings(ordered)
	return strings.Join(ordered, ", ")
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
	sshPrivateKeyPath := strings.TrimSpace(env.Config.SSHPrivateKeyPath)

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
		groupHosts := parseInventoryHosts(string(content), name, sshUser, sshPrivateKeyPath)
		applyConfiguredCloudServicePorts(groupHosts, env)
		hosts = append(hosts, groupHosts...)
	}
	hosts = uniqueHosts(hosts)

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
				if topologyUsesTLS(env.Config, name) {
					connStr += "&tls=true&tlsAllowInvalidCertificates=true"
				}
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
					url.QueryEscape(user), encodedPass, strings.Join(members, ","), cloudReplsetName(env, name))
				if topologyUsesTLS(env.Config, name) {
					connStr += "&tls=true&tlsAllowInvalidCertificates=true"
				}
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

// uniqueHosts removes shared services repeated in each topology inventory while
// preserving the first inventory's ordering and host metadata.
func uniqueHosts(hosts []HostInfo) []HostInfo {
	seen := make(map[string]struct{}, len(hosts))
	unique := make([]HostInfo, 0, len(hosts))
	for _, host := range hosts {
		if _, ok := seen[host.Name]; ok {
			continue
		}
		seen[host.Name] = struct{}{}
		unique = append(unique, host)
	}
	return unique
}

// parseInventoryHosts parses a simple Ansible INI-style inventory file and
// returns a HostInfo list.
func parseInventoryHosts(content, group, sshUser, sshPrivateKeyPath string) []HostInfo {
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
		isArbiter := false
		for _, kv := range parts[1:] {
			if strings.HasPrefix(kv, "ansible_host=") {
				ip = strings.TrimPrefix(kv, "ansible_host=")
			}
			if strings.EqualFold(kv, "arbiter=True") || strings.EqualFold(kv, "arbiter=true") {
				isArbiter = true
			}
		}
		if ip == "" {
			ip = hostName
		}
		role := "mongod"
		sec := strings.ToLower(currentSection)
		switch {
		case isArbiter:
			role = "arbiter"
		case strings.Contains(sec, "mongos"):
			role = "mongos"
		case strings.Contains(sec, "cfg") || strings.Contains(sec, "configsvr"):
			role = "configsvr"
		case strings.Contains(sec, "arb") || strings.Contains(sec, "arbiter"):
			role = "arbiter"
		case strings.Contains(sec, "pmm"):
			role = "pmm"
		case sec == "ca":
			role = "ca"
		case strings.Contains(sec, "minio"):
			role = "minio"
		case strings.Contains(sec, "ycsb"):
			role = "ycsb"
		case strings.Contains(sec, "pcsm"):
			role = "pcsm"
		case strings.Contains(sec, "ldap"):
			role = "ldap"
		}
		// Service hosts (minio, pmm) get their own logical group so they appear in
		// a separate subsection rather than inside the replica-set/cluster group.
		hostGroup := group
		switch role {
		case "minio":
			hostGroup = "Minio"
		case "pmm":
			hostGroup = "PMM"
		case "ca":
			hostGroup = "CA"
		case "ycsb":
			hostGroup = "YCSB"
		case "ldap":
			hostGroup = "LDAP"
		case "pcsm":
			hostGroup = "ClusterSync"
		}
		sshCmd := fmt.Sprintf("ssh %s@%s", sshUser, ip)
		if sshPrivateKeyPath != "" {
			sshCmd = fmt.Sprintf("ssh -i %s %s@%s", shellQuote(sshPrivateKeyPath), sshUser, ip)
		}
		hosts = append(hosts, HostInfo{
			Name:       hostName,
			IP:         ip,
			Port:       cloudHostPort(role, sec),
			ConnectCmd: sshCmd,
			Role:       role,
			Group:      hostGroup,
		})
	}
	return hosts
}

func cloudHostPort(role, section string) string {
	switch role {
	case "mongos", "mongod":
		return "27017"
	case "configsvr":
		return "27019"
	case "arbiter":
		if strings.Contains(section, "shard") || strings.Contains(section, "cluster") {
			return "27018"
		}
		return "27017"
	case "pmm":
		return "8443"
	case "minio":
		return "9000, 9001"
	case "ldap":
		return "389"
	default:
		return "—"
	}
}

func applyConfiguredCloudServicePorts(hosts []HostInfo, env *Environment) {
	for i := range hosts {
		switch hosts[i].Role {
		case "pmm":
			port := env.Config.PmmPort
			if port == 0 {
				port = 8443
			}
			hosts[i].Port = fmt.Sprintf("%d", port)
		case "minio":
			servicePort := env.Config.MinioPort
			if servicePort == 0 {
				servicePort = 9000
			}
			consolePort := env.Config.MinioConsolePort
			if consolePort == 0 {
				consolePort = 9001
			}
			hosts[i].Port = fmt.Sprintf("%d, %d", servicePort, consolePort)
		}
	}
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

func phpLDAPadminURL(host string) string {
	return fmt.Sprintf("http://%s:%d/phpldapadmin", host, 80)
}

// configServiceURLs derives web console URLs from the environment configuration.
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
		for svcName := range env.Config.LdapServers {
			urls = append(urls, ServiceURL{
				Name:  prefix + "-" + svcName,
				Label: "LDAP Console: " + svcName,
				URL:   fmt.Sprintf("http://%s:%d", host, 80),
			})
		}
	} else if env.Platform == "chaos" {
		// CHAOS service URLs should point at the real instance addresses rather
		// than localhost SSH forwards, so derive them from the inventory files.
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
		pmmHost := ""
		pmmIP := ""
		ldapHost := ""
		ldapIP := ""
		filePrefix2 := strDefault(env.Config.Prefix, envID)
		for _, name := range names {
			p := filepath.Join(tfDir, filePrefix2+"_inventory_"+name)
			content, err := os.ReadFile(p)
			if err != nil {
				continue
			}
			inMinio := false
			inPmm := false
			inLDAP := false
			for _, line := range strings.Split(string(content), "\n") {
				line = strings.TrimSpace(line)
				if line == "[minio]" {
					inMinio = true
					inPmm = false
					inLDAP = false
					continue
				}
				if line == "[pmm]" {
					inPmm = true
					inMinio = false
					inLDAP = false
					continue
				}
				if line == "[ldap]" {
					inLDAP = true
					inMinio = false
					inPmm = false
					continue
				}
				if strings.HasPrefix(line, "[") {
					inMinio = false
					inPmm = false
					inLDAP = false
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
				}
				if inPmm && line != "" {
					parts := strings.Fields(line)
					pmmHost = parts[0]
					for _, kv := range parts[1:] {
						if strings.HasPrefix(kv, "ansible_host=") {
							pmmIP = strings.TrimPrefix(kv, "ansible_host=")
						}
					}
				}
				if inLDAP && line != "" {
					parts := strings.Fields(line)
					ldapHost = parts[0]
					for _, kv := range parts[1:] {
						if strings.HasPrefix(kv, "ansible_host=") {
							ldapIP = strings.TrimPrefix(kv, "ansible_host=")
						}
					}
				}
			}
			if (minioHost != "" || minioIP != "") && (pmmHost != "" || pmmIP != "") && (ldapHost != "" || ldapIP != "") {
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
		if v := env.Config.EnablePmm; v != nil && *v {
			host := pmmIP
			if host == "" {
				host = pmmHost
			}
			if host != "" {
				port := env.Config.PmmPort
				if port == 0 {
					port = 8443
				}
				urls = append(urls, ServiceURL{
					Name:  "pmm",
					Label: "PMM",
					URL:   fmt.Sprintf("https://%s:%d", host, port),
				})
			}
		}
		if ldapHost != "" || ldapIP != "" {
			host := ldapIP
			if host == "" {
				host = ldapHost
			}
			urls = append(urls, ServiceURL{
				Name:  "ldap",
				Label: "LDAP Console",
				URL:   phpLDAPadminURL(host),
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
		// phpLDAPadmin is exposed directly on the LDAP server's public HTTP port.
		// Use the generated inventory to obtain the provisioned address.
		hosts, _, _ := collectCloudHosts(envID, env)
		for _, host := range hosts {
			if host.Role != "ldap" || host.IP == "" || host.IP == "—" {
				continue
			}
			urls = append(urls, ServiceURL{
				Name:  "ldap",
				Label: "LDAP Console",
				URL:   phpLDAPadminURL(host.IP),
			})
			break
		}
	}
	return urls
}
