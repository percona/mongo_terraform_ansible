package main

import (
	"fmt"
	"io"
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
	case strings.HasSuffix(base, "-pmm-client") || strings.HasSuffix(base, "-pmm"):
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
	if guessDockerRole(name, prefix) == "pmm" {
		return "PMM"
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
	var conns []MongoConnInfo

	for name := range env.Config.Replsets {
		containerPrefix := prefix + "-" + name
		count := env.Config.Replsets[name].DataNodesPerReplset
		if count == 0 {
			count = 2
		}
		var members []string
		for i := 0; i < count; i++ {
			members = append(members, fmt.Sprintf("%s:%d", host, 27017+i))
		}
		connStr := fmt.Sprintf("mongodb://%s:%s@%s/?replicaSet=%s&authSource=admin",
			user, pass, strings.Join(members, ","), containerPrefix)
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
		var mongosHosts []string
		for i := 0; i < mongosCount; i++ {
			mongosHosts = append(mongosHosts, fmt.Sprintf("%s:%d", host, 27017+i))
		}
		connStr := fmt.Sprintf("mongodb://%s:%s@%s/?authSource=admin",
			user, pass, strings.Join(mongosHosts, ","))
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
	user, pass := mongoAdminCredentials(env)
	for _, name := range names {
		if _, ok := env.Config.Clusters[name]; ok {
			mongosHosts := hostsWithRole(hosts, name, "mongos")
			if len(mongosHosts) > 0 {
				var members []string
				for _, h := range mongosHosts {
					members = append(members, h.IP+":27017")
				}
				connStr := fmt.Sprintf("mongodb://%s:%s@%s/?authSource=admin",
					user, pass, strings.Join(members, ","))
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
					user, pass, strings.Join(members, ","), name)
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

// configServiceURLs derives PMM and Minio console URLs from the environment
// configuration.
func configServiceURLs(envID string, env *Environment) []ServiceURL {
	prefix := strDefault(env.Config.Prefix, envID)
	var urls []ServiceURL

	if env.Platform == "docker" {
		host := "localhost"
		for svcName, svc := range env.Config.PmmServers {
			port := svc.PmmPort
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


