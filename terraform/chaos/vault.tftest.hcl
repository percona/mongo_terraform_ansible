mock_provider "chaos" {}
mock_provider "local" {}

variables {
  chaos_api_token      = "mock-token"
  prefix               = "vault-merge-test"
  mongodb_distribution = "psmdb"
  vault_encryption     = true
  clusters             = {}
  replsets = {
    rs01 = {}
  }
  enable_pmm       = false
  enable_ca        = false
  enable_seaweedfs = false
}

run "vault_uses_default_os" {
  command = plan

  assert {
    condition     = chaos_instance.vault[0].os == "Ubuntu 24.04"
    error_message = "Vault must resolve an omitted OS to Ubuntu 24.04."
  }
}

run "vault_uses_explicit_os" {
  command = plan

  variables {
    os_image = "Ubuntu 22.04"
  }

  assert {
    condition     = chaos_instance.vault[0].os == "Ubuntu 22.04"
    error_message = "Vault must honor the environment's explicit OS."
  }
}

run "pmm_only_environment_without_vault" {
  command = plan

  variables {
    vault_encryption = false
    replsets         = {}
    enable_pmm       = true
    pmm_bare_clients = {
      client01 = {}
    }
  }

  assert {
    condition     = length(chaos_instance.vault) == 0 && length(chaos_instance.pmm_bare_client) == 1
    error_message = "PMM-only environments must remain usable without Vault."
  }
}
