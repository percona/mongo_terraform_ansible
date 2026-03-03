data "docker_registry_image" "vault" {
  name = var.vault_image
}

resource "docker_image" "vault" {
  name          = var.vault_image
  pull_triggers = [data.docker_registry_image.vault.sha256_digest]
  keep_locally  = true
}

resource "docker_volume" "vault_data" {
  name = var.vault_data_volume
}

# Shared Docker volume for PKI certificates (CA cert, Keycloak TLS cert+key)
resource "docker_volume" "pki_certs" {
  name = var.pki_certs_volume_name
}

resource "docker_container" "vault" {
  name  = var.vault_container_name
  image = docker_image.vault.image_id
  ports {
    internal = var.vault_port
    external = var.vault_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }
  volumes {
    volume_name    = docker_volume.vault_data.name
    container_path = "/vault"
  }
  volumes {
    volume_name    = docker_volume.pki_certs.name
    container_path = "/pki"
  }
  env = [
    "VAULT_DEV_ROOT_TOKEN_ID=${var.vault_token}",
    "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:${var.vault_port}"
  ]
  command = ["server", "-dev"]
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  healthcheck {
    test         = ["CMD", "vault", "status"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "15s"
  }
  wait         = true
  wait_timeout = 120
  restart      = "on-failure"
}

# Provision Vault with PKI (CA + Keycloak TLS cert) and KV secrets engines
resource "null_resource" "vault_init" {
  depends_on = [docker_container.vault]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      docker exec -i \
        -e VAULT_ADDR=http://localhost:${var.vault_port} \
        -e VAULT_TOKEN=${var.vault_token} \
        ${var.vault_container_name} sh << 'VAULT_EOF'
      set -e

      # Enable PKI secrets engine
      vault secrets enable -path=pki pki

      # Generate internal root CA (8760h = 1 year)
      vault write pki/root/generate/internal \
        common_name="${var.vault_pki_common_name}" \
        ttl=8760h

      # Write CA certificate to shared PKI volume
      vault read -field=certificate pki/cert/ca > /pki/ca.crt

      # Create PKI role for Keycloak TLS certificate
      vault write pki/roles/${var.vault_keycloak_role} \
        allowed_domains="${var.keycloak_common_name},localhost" \
        allow_bare_domains=true \
        allow_subdomains=false \
        allow_ip_sans=true \
        max_ttl=8760h

      # Issue Keycloak TLS cert and extract cert+key to shared PKI volume.
      # Both fields come from the SAME issuance (they must match), so we save
      # the JSON output once and extract with grep+sed (no jq in vault image).
      vault write -format=json \
        pki/issue/${var.vault_keycloak_role} \
        common_name="${var.keycloak_common_name}" \
        alt_names="localhost" \
        ip_sans="127.0.0.1" \
        > /tmp/kc.json
      grep '"certificate":' /tmp/kc.json \
        | sed 's/.*"certificate": "//;s/"[,}]*$//' \
        | sed 's/\\n/\n/g' > /pki/tls.crt
      grep '"private_key":' /tmp/kc.json \
        | sed 's/.*"private_key": "//;s/"[,}]*$//' \
        | sed 's/\\n/\n/g' > /pki/tls.key

      # Enable KV secrets engine and store MongoDB encryption key
      vault secrets enable -path=${var.vault_kv_path_prefix} kv
      vault kv put ${var.vault_kv_path} key=$(openssl rand -base64 32)

      # Create PKI role and issue certificate for MongoDB TLS (optional)
      vault write pki/roles/${var.vault_pki_role} \
        allowed_domains="${var.vault_cert_domain}" \
        allow_subdomains=true \
        max_ttl=72h
      # Issue MongoDB TLS cert. Same single-issuance approach (cert+key must match).
      vault write -format=json \
        pki/issue/${var.vault_pki_role} \
        common_name="mongo1.${var.vault_cert_domain}" \
        > /tmp/mongo.json
      grep '"certificate":' /tmp/mongo.json \
        | sed 's/.*"certificate": "//;s/"[,}]*$//' \
        | sed 's/\\n/\n/g' > /pki/mongo.crt
      grep '"private_key":' /tmp/mongo.json \
        | sed 's/.*"private_key": "//;s/"[,}]*$//' \
        | sed 's/\\n/\n/g' > /pki/mongo.key

      VAULT_EOF
    EOT
  }
}