package main

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

const chaosProviderExampleVersion = "1.0.0"

// toolInstalled returns true when the named executable can be found on PATH.
func toolInstalled(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func chaosProviderTarget() string {
	return runtime.GOOS + "_" + runtime.GOARCH
}

func standardTerraformPluginRoot() (string, error) {
	if runtime.GOOS == "windows" {
		if appData := os.Getenv("APPDATA"); appData != "" {
			return filepath.Join(appData, "terraform.d", "plugins"), nil
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".terraform.d", "plugins"), nil
}

func chaosProviderInstalledIn(pluginRoot string) bool {
	pattern := filepath.Join(
		pluginRoot,
		"registry.terraform.io",
		"percona",
		"chaos",
		"*",
		chaosProviderTarget(),
		"terraform-provider-chaos*",
	)
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return false
	}
	for _, match := range matches {
		info, err := os.Stat(match)
		if err == nil && !info.IsDir() {
			return true
		}
	}
	return false
}

func chaosProviderInstalled() bool {
	pluginRoot, err := standardTerraformPluginRoot()
	if err != nil {
		return false
	}
	return chaosProviderInstalledIn(pluginRoot)
}

func chaosProviderInstallPath() (string, error) {
	pluginRoot, err := standardTerraformPluginRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(
		pluginRoot,
		"registry.terraform.io",
		"percona",
		"chaos",
		chaosProviderExampleVersion,
		chaosProviderTarget(),
	), nil
}

func chaosProviderMissingError() string {
	installPath, err := chaosProviderInstallPath()
	if err != nil {
		return "CHAOS Terraform provider percona/chaos is not installed and the standard Terraform plugin directory could not be determined: " + err.Error()
	}
	return fmt.Sprintf(
		"CHAOS Terraform provider percona/chaos is not installed for %s. Install terraform-provider-chaos under %s and retry.",
		chaosProviderTarget(),
		installPath,
	)
}

// platformPrereqs returns the prerequisite tool list for a given platform.
// Each entry has install guidance appropriate for the host OS.
func platformPrereqs(platform string) []PrereqTool {
	terraform := PrereqTool{
		Name:       "terraform",
		InstallDoc: "https://developer.hashicorp.com/terraform/install",
		InstallCmds: []string{
			"# macOS (Homebrew)",
			"brew tap hashicorp/tap && brew install hashicorp/tap/terraform",
			"",
			"# Linux (apt)",
			"wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg",
			`echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list`,
			"sudo apt-get update && sudo apt-get install -y terraform",
		},
	}
	ansible := PrereqTool{
		Name:       "ansible",
		InstallDoc: "https://docs.ansible.com/ansible/latest/installation_guide/",
		InstallCmds: []string{
			"# macOS (pip)",
			"pip3 install --user ansible",
			"",
			"# Linux (apt)",
			"sudo apt-get update && sudo apt-get install -y ansible",
			"",
			"# Linux (pip)",
			"pip3 install --user ansible",
		},
	}
	dockerCLI := PrereqTool{
		Name:       "docker",
		InstallDoc: "https://docs.docker.com/engine/install/",
		InstallCmds: []string{
			"# macOS – install Docker Desktop",
			"brew install --cask docker",
			"",
			"# Linux (convenience script)",
			"curl -fsSL https://get.docker.com | sh",
			"sudo usermod -aG docker $USER   # then log out / in",
		},
	}
	awsCLI := PrereqTool{
		Name:       "aws",
		InstallDoc: "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html",
		InstallCmds: []string{
			"# macOS (Homebrew)",
			"brew install awscli",
			"",
			"# Linux",
			`curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip`,
			"unzip awscliv2.zip && sudo ./aws/install",
		},
	}
	gcloudCLI := PrereqTool{
		Name:       "gcloud",
		InstallDoc: "https://cloud.google.com/sdk/docs/install",
		InstallCmds: []string{
			"# macOS (Homebrew)",
			"brew install --cask google-cloud-sdk",
			"",
			"# Linux",
			"curl https://sdk.cloud.google.com | bash",
			"exec -l $SHELL",
			"gcloud init",
		},
	}
	azureCLI := PrereqTool{
		Name:       "az",
		InstallDoc: "https://learn.microsoft.com/cli/azure/install-azure-cli",
		InstallCmds: []string{
			"# macOS (Homebrew)",
			"brew install azure-cli",
			"",
			"# Linux (apt)",
			"curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash",
		},
	}
	chaosProvider := PrereqTool{
		Name:       "terraform-provider-chaos",
		InstallDoc: "https://developer.hashicorp.com/terraform/cli/config/config-file#implied-local-mirror-directories",
		InstallCmds: []string{
			"Install terraform-provider-chaos in the standard local Terraform plugin path:",
			filepath.Join("~", ".terraform.d", "plugins", "registry.terraform.io", "percona", "chaos", chaosProviderExampleVersion, chaosProviderTarget()),
		},
	}

	var tools []PrereqTool
	switch platform {
	case "docker":
		tools = []PrereqTool{dockerCLI, terraform}
	case "aws":
		tools = []PrereqTool{terraform, ansible, awsCLI}
	case "gcp":
		tools = []PrereqTool{terraform, ansible, gcloudCLI}
	case "azure":
		tools = []PrereqTool{terraform, ansible, azureCLI}
	case "chaos":
		tools = []PrereqTool{terraform, ansible, chaosProvider}
	default:
		tools = []PrereqTool{terraform, ansible}
	}

	for i := range tools {
		if tools[i].Name == "terraform-provider-chaos" {
			tools[i].Installed = chaosProviderInstalled()
		} else {
			tools[i].Installed = toolInstalled(tools[i].Name)
		}
	}
	return tools
}

// GET /api/prerequisites/{platform}
func apiPrerequisitesHandler(w http.ResponseWriter, r *http.Request) {
	platform := r.PathValue("platform")
	if !validPlatform(platform) {
		jsonError(w, 400, "unknown platform: "+platform)
		return
	}
	tools := platformPrereqs(platform)
	ok := true
	for _, t := range tools {
		if !t.Installed {
			ok = false
			break
		}
	}
	result := PrereqResult{
		Platform: platform,
		OK:       ok,
		Tools:    tools,
	}
	w.Header().Set("Content-Type", "application/json")
	writeJSON(w, http.StatusOK, result)
}
