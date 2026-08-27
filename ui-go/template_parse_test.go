package main

import (
	"html/template"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTemplatesParse(t *testing.T) {
	tmplDir := filepath.Join("templates")
	pages := []string{"configure", "environment", "index", "new_environment"}
	for _, page := range pages {
		t.Run(page, func(t *testing.T) {
			_, err := template.New("").Funcs(funcMap).ParseFiles(
				filepath.Join(tmplDir, "layout.html"),
				filepath.Join(tmplDir, page+".html"),
			)
			if err != nil {
				t.Fatalf("parse %s template: %v", page, err)
			}
		})
	}
}

func TestDockerMongotImageSelectorSupportsCustomRepository(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("templates", "configure.html"))
	if err != nil {
		t.Fatalf("read configure template: %v", err)
	}
	template := string(content)
	for _, want := range []string{
		`{{$mongotNs := imageNamespace $curMongot "percona"}}{{$mongotRepo := imageRepository $curMongot "percona-search-mongodb"}}`,
		`class="docker-image-repository" value="{{$mongotRepo}}" placeholder="repository" aria-label="mongot image repository" {{if not (mongotNamespaceCustom $mongotNs)}}style="display:none"{{end}}`,
		`onDockerMongotNamespaceChange`,
		`/api/docker-tags?namespace=${encodeURIComponent(namespace)}&repo=${encodeURIComponent(repo)}`,
	} {
		if !strings.Contains(template, want) {
			t.Errorf("configure template missing %q", want)
		}
	}
}

func TestCloudTLSConfigurationFields(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("templates", "configure.html"))
	if err != nil {
		t.Fatalf("read configure template: %v", err)
	}
	page := string(content)
	for _, want := range []string{
		`name="cluster_enable_tls[]"`,
		`name="replset_enable_tls[]"`,
		`name="ca_placement"`,
		`name="enable_ca"`,
		`id="ca-settings-body"`,
		`config.enable_ca = fd.has('enable_ca')`,
		`config.enable_tls = [...Object.values(config.clusters), ...Object.values(config.replsets)].some(item => item.enable_tls)`,
		`config.ca_placement = fd.get('ca_placement') || 'dedicated'`,
		`<h2>Certificate Authority</h2>`,
		`['aws', 'gcp', 'azure', 'chaos'].includes(PLATFORM)`,
		`name="ca_cpu_cores"`,
		`name="ca_memory_gb"`,
		`name="ca_volume_size"`,
	} {
		if !strings.Contains(page, want) {
			t.Errorf("configure template missing %q", want)
		}
	}
}

func TestMongoTemplatesPreferTLS(t *testing.T) {
	files := []string{
		"mongod-replicaset.conf.j2",
		"mongod-sharding.conf.j2",
		"mongod-cfgserver.conf.j2",
		"mongos.conf.j2",
	}
	for _, name := range files {
		content, err := os.ReadFile(filepath.Join("..", "ansible", "templates", name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		if !strings.Contains(string(content), "mode: preferTLS") {
			t.Errorf("%s does not configure preferTLS", name)
		}
		if strings.Contains(string(content), "mode: requireTLS") {
			t.Errorf("%s still configures requireTLS", name)
		}
	}

	mainPlaybook, err := os.ReadFile(filepath.Join("..", "ansible", "main.yml"))
	if err != nil {
		t.Fatalf("read main playbook: %v", err)
	}
	if !strings.Contains(string(mainPlaybook), "TLS variable mismatch") {
		t.Error("main playbook is missing the TLS precedence guard")
	}
}

func TestMongoShellUsesDedicatedClientCertificate(t *testing.T) {
	playbooks := []string{
		"add_replset_member.yml",
		"add_shard.yml",
		"mongod_install.yml",
		"mongos_install.yml",
		"sharding_setup.yml",
	}
	for _, name := range playbooks {
		content, err := os.ReadFile(filepath.Join("..", "ansible", name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		if !strings.Contains(string(content), "clientCertificateKeyFile") {
			t.Errorf("%s does not use the dedicated client certificate", name)
		}
	}

	certSetup, err := os.ReadFile(filepath.Join("..", "ansible", "cert_setup.yml"))
	if err != nil {
		t.Fatalf("read cert_setup.yml: %v", err)
	}
	for _, want := range []string{
		"openssl-test-client.cnf.j2",
		`dest: "{{ clientCertificateKeyFile }}"`,
		`owner: "{{ ansible_user }}"`,
		`mode: "0600"`,
	} {
		if !strings.Contains(string(certSetup), want) {
			t.Errorf("cert_setup.yml missing %q", want)
		}
	}
}

func TestPBMUsesDedicatedClientCertificate(t *testing.T) {
	files := []string{
		"pbm_install.yml",
		"restart.yml",
		filepath.Join("templates", "pbm-agent.j2"),
	}
	for _, name := range files {
		content, err := os.ReadFile(filepath.Join("..", "ansible", name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		text := string(content)
		if !strings.Contains(text, "tlsCertificateKeyFile={{ clientCertificateKeyFile }}") {
			t.Errorf("%s does not configure PBM with the client certificate", name)
		}
		if strings.Contains(text, "tlsCertificateKeyFile={{ certificateKeyFile }}") {
			t.Errorf("%s still configures PBM with the server certificate", name)
		}
	}

	pbmInstall, err := os.ReadFile(filepath.Join("..", "ansible", "pbm_install.yml"))
	if err != nil {
		t.Fatalf("read pbm_install.yml: %v", err)
	}
	for _, want := range []string{
		"Grant PBM access to the client TLS certificate",
		`group: "{{ pbm_os_user }}"`,
		`mode: "0640"`,
	} {
		if !strings.Contains(string(pbmInstall), want) {
			t.Errorf("pbm_install.yml missing %q", want)
		}
	}
}

func TestCloudInventoryUsesCanonicalAnsibleUser(t *testing.T) {
	for _, platform := range []string{"aws", "azure", "chaos", "gcp"} {
		for _, name := range []string{"cluster_inventory.tmpl", "replset_inventory.tmpl"} {
			path := filepath.Join("..", "terraform", platform, name)
			content, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read %s: %v", path, err)
			}
			inventory := string(content)
			if !strings.Contains(inventory, "ansible_user=${my_ssh_user}") {
				t.Errorf("%s does not emit ansible_user", path)
			}
			if strings.Contains(inventory, "ansible_ssh_user") {
				t.Errorf("%s still emits legacy ansible_ssh_user", path)
			}
		}
	}
}
