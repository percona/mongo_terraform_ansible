package main

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// tfvarsPath returns the path for the env's tfvars file.
func tfvarsPath(envID, platform string) string {
	return filepath.Join(terraformDir, platform, envID+".tfvars")
}

// tfstatePath returns the path for the env's Terraform state file.
// Terraform also writes a backup alongside it; use tfstateBackupPath for that.
func tfstatePath(envID, platform string) string {
	return filepath.Join(terraformDir, platform, envID+".tfstate")
}

// tfstateBackupPath returns the path for the env's Terraform state backup file.
func tfstateBackupPath(envID, platform string) string {
	return filepath.Join(terraformDir, platform, envID+".tfstate.backup")
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
	normalizeTopologyUseTLS(&cfg)
	normalizeCAProvisioning(&cfg)
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
	writeVar("enable_pcsm", cfg.ClusterSync.Enabled)
	if cfg.ClusterSync.Enabled {
		if platform == "docker" {
			writeVar("pcsm_image", strDefault(cfg.ClusterSync.Image, "percona/percona-clustersync-mongodb:0.9.0"))
			writeVar("pcsm_env_file", clusterSyncEnvPath(envID))
			writeVar("pcsm_cpus", intDefault(cfg.ClusterSync.CPUs, 2))
			writeVar("pcsm_memory_mb", intDefault(cfg.ClusterSync.MemoryMB, 1024))
		} else if platform == "chaos" {
			writeVar("pcsm_version", strDefault(cfg.ClusterSync.Version, "0.9.0"))
			writeVar("pcsm_cpu_cores", intDefault(cfg.ClusterSync.CPUs, 2))
			memoryGB := max(4, intDefault(cfg.ClusterSync.MemoryMB, 4096)/1024)
			if !containsInt([]int{4, 8, 16, 32}, memoryGB) {
				memoryGB = 4
			}
			writeVar("pcsm_memory_gb", memoryGB)
		} else {
			writeVar("pcsm_version", strDefault(cfg.ClusterSync.Version, "0.9.0"))
			if cfg.ClusterSync.InstanceType != "" {
				writeVar("pcsm_type", cfg.ClusterSync.InstanceType)
			}
		}
	}

	if platform != "docker" {
		if platform == "aws" || platform == "gcp" || platform == "azure" || platform == "chaos" {
			writeVar("enable_ca", boolDefault(cfg.EnableCA, false))
			writeVar("ca_placement", strDefault(cfg.CAPlacement, "dedicated"))
		}
		writeOptStr("mongodb_distribution", cfg.MongoDBDistribution)
		writeOptStr("mongo_release", cfg.MongoRelease)
		writeOptStr("mongo_version", cfg.MongoVersion)
		writeOptStr("mongo_repo", cfg.MongoRepo)

		// Cloud-only simple vars
		writeOptStr("project_id", cfg.ProjectID)
		writeOptStr("region", cfg.Region)
		writeOptStr("location", cfg.Location)
		writeOptStr("source_ranges", cfg.SourceRanges)
		writeOptStr("my_ssh_user", cfg.MySSHUser)
		writeOptStr("ssh_private_key_path", cfg.SSHPrivateKeyPath)
		if platform != "chaos" {
			writeOptStr("subnet_cidr", cfg.SubnetCIDR)
			if platform == "aws" {
				writeOptStr("ssh_public_key_path", cfg.SSHPublicKeyPath)
			}
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
		}

		if len(cfg.SSHUsers) > 0 && platform == "azure" {
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

		writeVar("enable_ycsb", cfg.EnableYcsb)

		if platform == "chaos" {
			// CHAOS-specific vars
			// Note: chaos_api_token is intentionally NOT written to the tfvars file because
			// it is sensitive. It is passed at runtime via the CHAOS_API_TOKEN environment
			// variable (see handlers.go).
			writeOptInt("delete_after_days", cfg.DeleteAfterDays)
			// Firewall rules: new structured per-rule list replaces source_ranges string.
			// For backward compat, also write source_ranges if FirewallRules is empty.
			if len(cfg.FirewallRules) > 0 {
				write("")
				write("firewall_rules = [")
				for _, r := range cfg.FirewallRules {
					comment := r.Comment
					if comment == "" {
						comment = "Custom access rule"
					}
					write("  {")
					write(fmt.Sprintf("    source   = %s", formatHCLVal(r.CIDR)))
					write(fmt.Sprintf("    port     = %s", formatHCLVal(r.Port)))
					write(`    protocol = "tcp"`)
					write(fmt.Sprintf("    comment  = %s", formatHCLVal(comment)))
					write("  },")
				}
				write("]")
			} else {
				writeOptStr("source_ranges", cfg.SourceRanges)
			}
			// PMM
			if cfg.EnablePmm != nil {
				writeVar("enable_pmm", *cfg.EnablePmm)
			}
			writeOptInt("pmm_port", cfg.PmmPort)
			writeOptInt("pmm_volume_size", cfg.PmmVolumeSize)
			writeOptInt("pmm_cpu_cores", cfg.PmmCpuCores)
			writeOptInt("pmm_memory_gb", cfg.PmmMemoryGb)
			writeOptStr("pmm_image", cfg.PmmImage)
			if boolDefault(cfg.EnableCA, false) && cfg.CAPlacement == "dedicated" {
				writeVar("ca_cpu_cores", intDefault(cfg.CACpuCores, 2))
				writeVar("ca_memory_gb", intDefault(cfg.CAMemoryGb, 4))
				writeVar("ca_volume_size", intDefault(cfg.CAVolumeSize, 20))
			}
			// Minio
			enableMinio := cfg.EnableMinio != nil && *cfg.EnableMinio
			if cfg.EnableMinio != nil {
				writeVar("enable_minio", *cfg.EnableMinio)
			}
			if enableMinio {
				writeOptStr("minio_root_user", cfg.MinioRootUser)
				writeOptStr("minio_root_password", cfg.MinioRootPassword)
				writeOptInt("minio_port", cfg.MinioPort)
				writeOptInt("minio_console_port", cfg.MinioConsolePort)
				writeOptInt("minio_cpu_cores", cfg.MinioCpuCores)
				writeOptInt("minio_memory_gb", cfg.MinioMemoryGb)
				writeOptInt("minio_volume_size", cfg.MinioVolumeSize)
			}
			// Backup
			writeOptStr("default_bucket_name", cfg.DefaultBucketName)
			writeOptInt("backup_retention", cfg.BackupRetention)
			// Per-component CPU/memory (CHAOS uses cpu_cores/memory_gb not instance types)
			writeOptInt("shardsvr_cpu_cores", cfg.ShardsvrCpuCores)
			writeOptInt("shardsvr_memory_gb", cfg.ShardsvrMemoryGb)
			writeOptInt("shardsvr_volume_size", cfg.ShardsvrVolumeSize)
			writeOptInt("configsvr_cpu_cores", cfg.ConfigsvrCpuCores)
			writeOptInt("configsvr_memory_gb", cfg.ConfigsvrMemoryGb)
			writeOptInt("configsvr_volume_size", cfg.ConfigsvrVolumeSize)
			writeOptInt("mongos_cpu_cores", cfg.MongosCpuCores)
			writeOptInt("mongos_memory_gb", cfg.MongosMemoryGb)
			writeOptInt("arbiter_cpu_cores", cfg.ArbiterCpuCores)
			writeOptInt("arbiter_memory_gb", cfg.ArbiterMemoryGb)
			writeOptInt("replsetsvr_cpu_cores", cfg.ReplsetSvrCpuCores)
			writeOptInt("replsetsvr_memory_gb", cfg.ReplsetSvrMemoryGb)
			writeOptInt("replsetsvr_volume_size", cfg.ReplsetSvrVolumeSize)
		} else {
			// Non-CHAOS cloud vars
			// PMM
			writeOptStr("pmm_type", cfg.PmmType)
			writeOptInt("pmm_volume_size", cfg.PmmVolumeSize)
			writeOptInt("pmm_port", cfg.PmmPort)
			writeOptStr("pmm_disk_type", cfg.PmmDiskType)
			writeOptStr("pmm_image", cfg.PmmImage)
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

			// Per-component instance types and disk sizes
			writeOptStr("data_disk_type", cfg.DataDiskType)
			writeOptStr("shardsvr_type", cfg.ShardsvrType)
			writeOptInt("shardsvr_volume_size", cfg.ShardsvrVolumeSize)
			writeOptStr("configsvr_type", cfg.ConfigsvrType)
			writeOptInt("configsvr_volume_size", cfg.ConfigsvrVolumeSize)
			writeOptStr("mongos_type", cfg.MongosType)
			writeOptStr("arbiter_type", cfg.ArbiterType)
			writeOptStr("replsetsvr_type", cfg.ReplsetSvrType)
			writeOptInt("replsetsvr_volume_size", cfg.ReplsetSvrVolumeSize)

			regionKey := cfg.Region
			if platform == "azure" {
				regionKey = cfg.Location
			}
			if cfg.MachineImage != "" {
				if platform == "gcp" {
					write("")
					writeVar("image", cfg.MachineImage)
				} else if platform != "azure" && regionKey != "" {
					write("")
					write("image = {")
					write(fmt.Sprintf("  %s = %s", formatHCLVal(regionKey), formatHCLVal(cfg.MachineImage)))
					write("}")
				}
			}

			if platform == "gcp" && cfg.SSHPublicKeyPath != "" && cfg.MySSHUser != "" {
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
		}

		if len(cfg.LdapServers) > 0 {
			write("")
			write("ldap_servers = {")
			for _, ns := range sortedLdapServers(cfg.LdapServers) {
				n, s := ns.Name, ns.Config
				write(fmt.Sprintf("  %q = {", n))
				write(fmt.Sprintf("    domain = %s", formatHCLVal(strDefault(s.LdapDomain, "example.com"))))
				if s.LdapAdminPassword != "" {
					write(fmt.Sprintf("    admin_password = %s", formatHCLVal(s.LdapAdminPassword)))
				}
				write("  }")
			}
			write("}")
		}
	} else {
		// Docker-only
		writeOptStr("network_name", cfg.NetworkName)
		writeVar("enable_ycsb", cfg.EnableYcsb)
		writeOptStr("ycsb_image", cfg.YcsbImage)
		writeOptStr("ycsb_os_image", cfg.YcsbOsImage)
		writeOptStr("ycsb_container_suffix", cfg.YcsbContainerSuffix)
	}

	// ── Docker credential helpers ─────────────────────────────────────────────
	// Credentials entered in the UI are stored in cfg.AnsibleVars (keyed by
	// Ansible variable name).  For Docker environments Ansible is not invoked,
	// so we read the credential values here and inject them as Terraform
	// per-cluster/replset variables.
	dockerMongoRootPassword := ""
	if platform == "docker" && len(cfg.AnsibleVars) > 0 {
		dockerMongoRootPassword = cfg.AnsibleVars["mongo_admin_password"]
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
			write(fmt.Sprintf("    arbiters_per_replset = %s", formatHCLVal(intPtrDefault(c.ArbitersPerReplset, 1))))
			write(fmt.Sprintf("    mongos_count = %s", formatHCLVal(intDefault(c.MongosCount, 2))))
			write(fmt.Sprintf("    enable_audit = %s", formatHCLVal(boolDefault(c.EnableAudit, false))))
			if strings.TrimSpace(c.AuditFilter) != "" {
				write(fmt.Sprintf("    audit_filter = %s", formatHCLVal(c.AuditFilter)))
			}
			if platform != "docker" {
				write(fmt.Sprintf("    use_tls = %s", formatHCLVal(boolDefault(c.UseTLS, cfg.UseTLS))))
				write(fmt.Sprintf("    enable_pmm = %s", formatHCLVal(boolDefault(c.EnablePmm, false))))
				write(fmt.Sprintf("    enable_pbm = %s", formatHCLVal(boolDefault(c.EnablePbm, false))))
				write(fmt.Sprintf("    enable_mongot = %s", formatHCLVal(boolDefault(c.EnableMongot, false))))
				if c.MongotSource != "" {
					write(fmt.Sprintf("    mongot_source = %s", formatHCLVal(c.MongotSource)))
				}
				if c.MongotRepo != "" {
					write(fmt.Sprintf("    mongot_repo = %s", formatHCLVal(c.MongotRepo)))
				}
				if c.MongotVersion != "" {
					write(fmt.Sprintf("    mongot_version = %s", formatHCLVal(c.MongotVersion)))
				}
				if platform == "chaos" && c.OsImage != "" {
					write(fmt.Sprintf("    os_image = %s", formatHCLVal(c.OsImage)))
				}
				if c.MongoDBDistribution != "" {
					write(fmt.Sprintf("    mongodb_distribution = %s", formatHCLVal(c.MongoDBDistribution)))
				}
				if c.MongoRelease != "" {
					write(fmt.Sprintf("    mongo_release = %s", formatHCLVal(c.MongoRelease)))
				}
				if c.MongoVersion != "" {
					write(fmt.Sprintf("    mongo_version = %s", formatHCLVal(c.MongoVersion)))
				}
				if c.MongoRepo != "" {
					write(fmt.Sprintf("    mongo_repo = %s", formatHCLVal(c.MongoRepo)))
				}
				if c.PbmVersion != "" {
					write(fmt.Sprintf("    pbm_version = %s", formatHCLVal(c.PbmVersion)))
				}
				if c.PbmRepo != "" {
					write(fmt.Sprintf("    pbm_repo = %s", formatHCLVal(c.PbmRepo)))
				}
				if c.PmmClientVersion != "" {
					write(fmt.Sprintf("    pmm_client_version = %s", formatHCLVal(c.PmmClientVersion)))
				}
				if c.PmmClientRepo != "" {
					write(fmt.Sprintf("    pmm_client_repo = %s", formatHCLVal(c.PmmClientRepo)))
				}
				if c.LdapServer != "" {
					write(fmt.Sprintf("    ldap_server = %s", formatHCLVal(c.LdapServer)))
				}
			}
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
				if c.MongotImage != "" {
					write(fmt.Sprintf("    mongot_image = %s", formatHCLVal(c.MongotImage)))
				}
				write(fmt.Sprintf("    enable_pmm = %s", formatHCLVal(boolDefault(c.EnablePmm, false))))
				write(fmt.Sprintf("    enable_pbm = %s", formatHCLVal(boolDefault(c.EnablePbm, false))))
				write(fmt.Sprintf("    enable_mongot = %s", formatHCLVal(boolDefault(c.EnableMongot, false))))
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(c.BindToLocalhost)))
				if dockerMongoRootPassword != "" {
					write(fmt.Sprintf("    mongodb_root_password = %s", formatHCLVal(dockerMongoRootPassword)))
				}
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
			write(fmt.Sprintf("    arbiters_per_replset = %s", formatHCLVal(intPtrDefault(r.ArbitersPerReplset, 1))))
			write(fmt.Sprintf("    enable_audit = %s", formatHCLVal(boolDefault(r.EnableAudit, false))))
			if strings.TrimSpace(r.AuditFilter) != "" {
				write(fmt.Sprintf("    audit_filter = %s", formatHCLVal(r.AuditFilter)))
			}
			if platform != "docker" {
				write(fmt.Sprintf("    use_tls = %s", formatHCLVal(boolDefault(r.UseTLS, cfg.UseTLS))))
				write(fmt.Sprintf("    enable_pmm = %s", formatHCLVal(boolDefault(r.EnablePmm, false))))
				write(fmt.Sprintf("    enable_pbm = %s", formatHCLVal(boolDefault(r.EnablePbm, false))))
				write(fmt.Sprintf("    enable_mongot = %s", formatHCLVal(boolDefault(r.EnableMongot, false))))
				if r.MongotSource != "" {
					write(fmt.Sprintf("    mongot_source = %s", formatHCLVal(r.MongotSource)))
				}
				if r.MongotRepo != "" {
					write(fmt.Sprintf("    mongot_repo = %s", formatHCLVal(r.MongotRepo)))
				}
				if r.MongotVersion != "" {
					write(fmt.Sprintf("    mongot_version = %s", formatHCLVal(r.MongotVersion)))
				}
				if platform == "chaos" && r.OsImage != "" {
					write(fmt.Sprintf("    os_image = %s", formatHCLVal(r.OsImage)))
				}
				if r.MongoDBDistribution != "" {
					write(fmt.Sprintf("    mongodb_distribution = %s", formatHCLVal(r.MongoDBDistribution)))
				}
				if r.MongoRelease != "" {
					write(fmt.Sprintf("    mongo_release = %s", formatHCLVal(r.MongoRelease)))
				}
				if r.MongoVersion != "" {
					write(fmt.Sprintf("    mongo_version = %s", formatHCLVal(r.MongoVersion)))
				}
				if r.MongoRepo != "" {
					write(fmt.Sprintf("    mongo_repo = %s", formatHCLVal(r.MongoRepo)))
				}
				if r.PbmVersion != "" {
					write(fmt.Sprintf("    pbm_version = %s", formatHCLVal(r.PbmVersion)))
				}
				if r.PbmRepo != "" {
					write(fmt.Sprintf("    pbm_repo = %s", formatHCLVal(r.PbmRepo)))
				}
				if r.PmmClientVersion != "" {
					write(fmt.Sprintf("    pmm_client_version = %s", formatHCLVal(r.PmmClientVersion)))
				}
				if r.PmmClientRepo != "" {
					write(fmt.Sprintf("    pmm_client_repo = %s", formatHCLVal(r.PmmClientRepo)))
				}
				if r.LdapServer != "" {
					write(fmt.Sprintf("    ldap_server = %s", formatHCLVal(r.LdapServer)))
				}
			}
			if platform == "docker" {
				if r.ReplsetPort != 0 {
					write(fmt.Sprintf("    replset_port = %s", formatHCLVal(r.ReplsetPort)))
				}
				if r.ArbiterPort != 0 {
					write(fmt.Sprintf("    arbiter_port = %s", formatHCLVal(r.ArbiterPort)))
				}
				if r.ArbiterBasePort != 0 {
					write(fmt.Sprintf("    arbiter_base_port = %s", formatHCLVal(r.ArbiterBasePort)))
				}
				if r.PsmdbImage != "" {
					write(fmt.Sprintf("    psmdb_image = %s", formatHCLVal(r.PsmdbImage)))
				}
				if r.PbmImage != "" {
					write(fmt.Sprintf("    pbm_image = %s", formatHCLVal(r.PbmImage)))
				}
				if r.PmmClientImage != "" {
					write(fmt.Sprintf("    pmm_client_image = %s", formatHCLVal(r.PmmClientImage)))
				}
				if r.MongotImage != "" {
					write(fmt.Sprintf("    mongot_image = %s", formatHCLVal(r.MongotImage)))
				}
				write(fmt.Sprintf("    enable_pmm = %s", formatHCLVal(boolDefault(r.EnablePmm, false))))
				write(fmt.Sprintf("    enable_pbm = %s", formatHCLVal(boolDefault(r.EnablePbm, false))))
				write(fmt.Sprintf("    enable_mongot = %s", formatHCLVal(boolDefault(r.EnableMongot, false))))
				write(fmt.Sprintf("    bind_to_localhost = %s", formatHCLVal(r.BindToLocalhost)))
				if dockerMongoRootPassword != "" {
					write(fmt.Sprintf("    mongodb_root_password = %s", formatHCLVal(dockerMongoRootPassword)))
				}
			}
			write("  }")
		}
		write("}")
	}

	// ── Docker service blocks ─────────────────────────────────────────────────
	if platform == "docker" {
		write("")
		if len(cfg.PmmServers) == 0 {
			write("pmm_servers = {}")
		} else {
			write("pmm_servers = {")
			for _, ns := range sortedPmmServers(cfg.PmmServers) {
				n, s := ns.Name, ns.Config
				write(fmt.Sprintf("  %q = {", n))
				write(fmt.Sprintf("    env_tag = %s", formatHCLVal(strDefault(s.EnvTag, "test"))))
				if s.PmmServerImage != "" {
					write(fmt.Sprintf("    pmm_server_image = %s", formatHCLVal(s.PmmServerImage)))
				}
				internalPort := s.PmmPort
				if internalPort == 0 {
					internalPort = 8443
				}
				if internalPort != 0 {
					write(fmt.Sprintf("    pmm_port = %s", formatHCLVal(internalPort)))
				}
				externalPort := s.PmmExternalPort
				if externalPort == 0 {
					externalPort = internalPort
				}
				if externalPort != 0 {
					write(fmt.Sprintf("    pmm_external_port = %s", formatHCLVal(externalPort)))
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

		write("")
		if len(cfg.MinioServers) == 0 {
			write("minio_servers = {}")
		} else {
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
