data "docker_registry_image" "vault" {
  name = var.vault_image
}

resource "docker_image" "vault" {
  name = var.vault_image
  pull_triggers = [data.docker_registry_image.vault.sha256_digest]
}

resource "docker_volume" "vault_data" {
  name = var.vault_data_volume
}

resource "docker_container" "vault" {
  name  = var.vault_container_name
  image = docker_image.vault.latest
  ports {
    internal = var.vault_port
    external = var.vault_port
  }
  volumes {
    volume_name    = docker_volume.vault_data.name
    container_path = "/vault"
  }
  env = [
    "VAULT_DEV_ROOT_TOKEN_ID=${var.vault_token}",
    "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:${var.vault_port}"
  ]
  command = ["server", "-dev"]
}

# Provision Vault with PKI and KV secrets engines
resource "null_resource" "vault_init" {
  depends_on = [docker_container.vault]

  provisioner "local-exec" {
    command = <<EOT
      export VAULT_ADDR=${var.vault_addr}
      export VAULT_TOKEN=${var.vault_token}

      vault secrets enable -path=pki pki
      vault write pki/root/generate/internal \
        common_name="${var.vault_pki_common_name}" ttl=8760h

      vault write pki/roles/${var.vault_pki_role} \
        allowed_domains="${var.vault_cert_domain}" \
        allow_subdomains=true \
        max_ttl="72h"

      vault secrets enable -path=${var.vault_kv_path_prefix} kv

      vault kv put ${var.vault_kv_path} key=$(openssl rand -base64 32)

      mkdir -p ./certs

      CERT_JSON=$(vault write -format=json pki/issue/${var.vault_pki_role} common_name="mongo1.${var.vault_cert_domain}")
      echo $CERT_JSON | jq -r .data.certificate > ./certs/mongo.crt
      echo $CERT_JSON | jq -r .data.issuing_ca > ./certs/ca.crt
      echo $CERT_JSON | jq -r .data.private_key > ./certs/mongo.key
EOT
  }
}