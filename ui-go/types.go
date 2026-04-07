package main

import "sort"

// ChaosFirewallRule is a single ingress rule for CHAOS deployments.
type ChaosFirewallRule struct {
	CIDR    string `json:"cidr"`
	Port    string `json:"port"`
	Comment string `json:"comment,omitempty"`
}

// ClusterConfig maps to the Terraform "clusters" map object type.
type ClusterConfig struct {
	EnvTag             string `json:"env_tag"`
	ConfigsvrCount     int    `json:"configsvr_count"`
	ShardCount         int    `json:"shard_count"`
	ShardsvrReplicas   int    `json:"shardsvr_replicas"`
	ArbitersPerReplset *int   `json:"arbiters_per_replset,omitempty"`
	MongosCount        int    `json:"mongos_count"`
	// Docker-only
	PsmdbImage      string `json:"psmdb_image,omitempty"`
	PbmImage        string `json:"pbm_image,omitempty"`
	PmmClientImage  string `json:"pmm_client_image,omitempty"`
	EnablePmm       bool   `json:"enable_pmm,omitempty"`
	EnablePbm       bool   `json:"enable_pbm,omitempty"`
	BindToLocalhost bool   `json:"bind_to_localhost,omitempty"`
	EnableAudit     *bool  `json:"enable_audit,omitempty"`
	AuditFilter     string `json:"audit_filter,omitempty"`
}

// ReplsetConfig maps to the Terraform "replsets" map object type.
type ReplsetConfig struct {
	EnvTag              string `json:"env_tag"`
	DataNodesPerReplset int    `json:"data_nodes_per_replset"`
	ArbitersPerReplset  *int   `json:"arbiters_per_replset,omitempty"`
	// Docker-only port assignment: starting port for data nodes and arbiters.
	// Auto-assigned on save to avoid collisions between multiple replica sets.
	ReplsetPort int `json:"replset_port,omitempty"`
	ArbiterPort int `json:"arbiter_port,omitempty"`
	// Docker-only
	PsmdbImage      string `json:"psmdb_image,omitempty"`
	PbmImage        string `json:"pbm_image,omitempty"`
	PmmClientImage  string `json:"pmm_client_image,omitempty"`
	EnablePmm       bool   `json:"enable_pmm,omitempty"`
	EnablePbm       bool   `json:"enable_pbm,omitempty"`
	BindToLocalhost bool   `json:"bind_to_localhost,omitempty"`
	EnableAudit     *bool  `json:"enable_audit,omitempty"`
	AuditFilter     string `json:"audit_filter,omitempty"`
}

// PmmServerConfig maps to the Docker pmm_servers map object type.
type PmmServerConfig struct {
	EnvTag          string `json:"env_tag"`
	PmmServerImage  string `json:"pmm_server_image,omitempty"`
	PmmPort         int    `json:"pmm_port,omitempty"`
	PmmExternalPort int    `json:"pmm_external_port,omitempty"`
	PmmServerUser   string `json:"pmm_server_user,omitempty"`
	PmmServerPwd    string `json:"pmm_server_pwd,omitempty"`
	BindToLocalhost bool   `json:"bind_to_localhost,omitempty"`
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
	Prefix              string `json:"prefix"`
	MongoRelease        string `json:"mongo_release,omitempty"`
	MongoVersion        string `json:"mongo_version,omitempty"`
	PbmRelease          string `json:"pbm_release,omitempty"`
	PbmVersion          string `json:"pbm_version,omitempty"`
	PmmClientVersion    string `json:"pmm_client_version,omitempty"`
	EnableYcsb          bool   `json:"enable_ycsb,omitempty"`
	YcsbImage           string `json:"ycsb_image,omitempty"`
	YcsbOsImage         string `json:"ycsb_os_image,omitempty"`
	YcsbContainerSuffix string `json:"ycsb_container_suffix,omitempty"`

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
	SSHUsers map[string]string `json:"ssh_users,omitempty"`

	// PMM (cloud)
	EnablePmm     *bool  `json:"enable_pmm,omitempty"`
	PmmType       string `json:"pmm_type,omitempty"`
	PmmVolumeSize int    `json:"pmm_volume_size,omitempty"`
	PmmPort       int    `json:"pmm_port,omitempty"`
	PmmImage      string `json:"pmm_image,omitempty"`
	PmmDiskType   string `json:"pmm_disk_type,omitempty"`

	// Backup
	DefaultBucketName string `json:"default_bucket_name,omitempty"`
	BackupRetention   int    `json:"backup_retention,omitempty"`

	// Machine image / AMI selected for cloud instances.
	MachineImage string `json:"machine_image,omitempty"`

	// CHAOS-specific settings
	ChaosApiToken   string `json:"chaos_api_token,omitempty"`
	EnableMinio     *bool  `json:"enable_minio,omitempty"`
	DeleteAfterDays int    `json:"delete_after_days,omitempty"`
	OsImage         string `json:"os_image,omitempty"`
	// FirewallRules replaces the old SourceRanges single string for CHAOS.
	// Each entry is an independent ingress rule with its own CIDR and port.
	FirewallRules      []ChaosFirewallRule `json:"firewall_rules,omitempty"`
	ShardsvrCpuCores   int                 `json:"shardsvr_cpu_cores,omitempty"`
	ShardsvrMemoryGb   int                 `json:"shardsvr_memory_gb,omitempty"`
	ConfigsvrCpuCores  int                 `json:"configsvr_cpu_cores,omitempty"`
	ConfigsvrMemoryGb  int                 `json:"configsvr_memory_gb,omitempty"`
	MongosCpuCores     int                 `json:"mongos_cpu_cores,omitempty"`
	MongosMemoryGb     int                 `json:"mongos_memory_gb,omitempty"`
	ArbiterCpuCores    int                 `json:"arbiter_cpu_cores,omitempty"`
	ArbiterMemoryGb    int                 `json:"arbiter_memory_gb,omitempty"`
	ReplsetSvrCpuCores int                 `json:"replsetsvr_cpu_cores,omitempty"`
	ReplsetSvrMemoryGb int                 `json:"replsetsvr_memory_gb,omitempty"`
	MinioCpuCores      int                 `json:"minio_cpu_cores,omitempty"`
	MinioMemoryGb      int                 `json:"minio_memory_gb,omitempty"`
	MinioVolumeSize    int                 `json:"minio_volume_size,omitempty"`
	MinioPort          int                 `json:"minio_port,omitempty"`
	MinioConsolePort   int                 `json:"minio_console_port,omitempty"`
	MinioRootUser      string              `json:"minio_root_user,omitempty"`
	MinioRootPassword  string              `json:"minio_root_password,omitempty"`
	PmmCpuCores        int                 `json:"pmm_cpu_cores,omitempty"`
	PmmMemoryGb        int                 `json:"pmm_memory_gb,omitempty"`

	// Per-component instance types and disk sizes (cloud platforms only).
	ShardsvrType         string `json:"shardsvr_type,omitempty"`
	ShardsvrVolumeSize   int    `json:"shardsvr_volume_size,omitempty"`
	ConfigsvrType        string `json:"configsvr_type,omitempty"`
	ConfigsvrVolumeSize  int    `json:"configsvr_volume_size,omitempty"`
	MongosType           string `json:"mongos_type,omitempty"`
	ArbiterType          string `json:"arbiter_type,omitempty"`
	ReplsetSvrType       string `json:"replsetsvr_type,omitempty"`
	ReplsetSvrVolumeSize int    `json:"replsetsvr_volume_size,omitempty"`
	DataDiskType         string `json:"data_disk_type,omitempty"`

	// Docker networking
	NetworkName string `json:"network_name,omitempty"`

	// Topology
	Clusters map[string]ClusterConfig `json:"clusters"`
	Replsets map[string]ReplsetConfig `json:"replsets"`

	// Docker-specific service servers
	PmmServers   map[string]PmmServerConfig   `json:"pmm_servers,omitempty"`
	MinioServers map[string]MinioServerConfig `json:"minio_servers,omitempty"`
	LdapServers  map[string]LdapServerConfig  `json:"ldap_servers,omitempty"`

	// Ansible variable overrides passed via --extra-vars at playbook runtime.
	AnsibleVars map[string]string `json:"ansible_vars,omitempty"`
}

// HistoryEvent records a single user-initiated action and its outcome.
type HistoryEvent struct {
	Action       string `json:"action"`
	StartedAt    string `json:"started_at"`
	Status       string `json:"status"` // "success", "failed", "cancelled"
	DurationSecs int64  `json:"duration_secs,omitempty"`
}

// Environment is one record in the state file.
type Environment struct {
	Platform  string         `json:"platform"`
	Config    Config         `json:"config"`
	Status    string         `json:"status"`
	CreatedAt string         `json:"created_at"`
	UpdatedAt string         `json:"updated_at"`
	LastJobID string         `json:"last_job_id,omitempty"`
	History   []HistoryEvent `json:"history,omitempty"`
	// HostIPs caches the last-known IP address for each Docker container so
	// that the UI can continue to display addresses even when containers are
	// stopped (and docker inspect returns an empty IP).
	HostIPs map[string]string `json:"host_ips,omitempty"`
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
	Platform                      string
	EnvID                         string
	Config                        Config
	DefaultAuditFilter            string
	OSUser                        string // current OS user, used as SSH user default
	DockerDefaultPmmExternalPort  int
	DockerDefaultMinioPort        int
	DockerDefaultMinioConsolePort int
	PSMDBVersions                 []string
	// PBMVersions holds a flat sorted-descending list of all available PBM package
	// versions (e.g. ["2.7.0", "2.6.1", "2.6.0", ...]). PBM uses a single Percona
	// repository so there is no per-major-version grouping.
	PBMVersions []string
	// PSMDBMinorVersions maps major release key → sorted minor versions
	// e.g. {"psmdb-70": ["7.0.12", "7.0.11", ...]}
	PSMDBMinorVersions map[string][]string
	PMMImages          []string
	PSMDBImages        []string
	PBMImages          []string
	PMMClientImages    []string
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
	ServiceURLs    []ServiceURL
	YcsbEnabled    bool
	YcsbAvailable  bool
}

// HostInfo describes a single running host or container.
type HostInfo struct {
	Name       string `json:"name"`
	IP         string `json:"ip"`
	ConnectCmd string `json:"connect_cmd"`
	Role       string `json:"role"`
	Group      string `json:"group"`
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
	Type       string `json:"type"`
	ConnString string `json:"conn_string"`
	ConnUser   string `json:"conn_user"`
	ConnPass   string `json:"conn_pass"`
}

// CloudImage represents a single machine image available for a region.
type CloudImage struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
}

// PrereqTool describes a single prerequisite tool and whether it is installed.
type PrereqTool struct {
	Name        string   `json:"name"`
	Installed   bool     `json:"installed"`
	InstallDoc  string   `json:"install_doc"`  // short URL / reference
	InstallCmds []string `json:"install_cmds"` // copy-pasteable shell commands
}

// PrereqResult is the JSON response from GET /api/prerequisites/{platform}.
type PrereqResult struct {
	Platform string       `json:"platform"`
	OK       bool         `json:"ok"` // true when all tools are installed
	Tools    []PrereqTool `json:"tools"`
}
