# Wait for Vault to write TLS certs to the shared PKI volume before starting Keycloak.
# This ensures there is no race condition when Terraform's module-level depends_on
# does not guarantee null_resource provisioners in vault_server finish first.
resource "null_resource" "wait_for_vault_certs" {
  count = var.pki_certs_volume_name != "" && var.vault_container_name != "" ? 1 : 0

  triggers = {
    vault_container  = var.vault_container_name
    pki_volume       = var.pki_certs_volume_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      RETRIES=40
      INTERVAL=5
      COUNT=0
      echo "Waiting for PKI certs to appear in vault container '${var.vault_container_name}'..."
      until docker exec ${var.vault_container_name} sh -c 'test -f /pki/tls.crt && test -f /pki/ca.crt && test -f /pki/tls.key'; do
        COUNT=$((COUNT + 1))
        if [ "$COUNT" -ge "$RETRIES" ]; then
          echo "Timed out waiting for PKI certs in ${var.vault_container_name}:/pki"
          exit 1
        fi
        echo "PKI certs not ready yet, retrying in ${INTERVAL}s ($COUNT/$RETRIES)..."
        sleep $INTERVAL
      done
      echo "PKI certs are ready in volume ${var.pki_certs_volume_name}"
    EOT
  }
}

# Keycloak Docker container image
data "docker_registry_image" "keycloak" {
  name = var.keycloak_image
}

resource "docker_image" "keycloak" {
  name          = var.keycloak_image
  pull_triggers = [data.docker_registry_image.keycloak.sha256_digest]
  keep_locally  = true
}

# Keycloak Server volume
resource "docker_volume" "keycloak_data" {
  name = "${var.keycloak_server}-data"
}

# Keycloak Server container
resource "docker_container" "keycloak_server" {
  name  = var.keycloak_server
  image = docker_image.keycloak.image_id

  env = [
    "KEYCLOAK_ADMIN=${var.keycloak_admin_user}",
    "KEYCLOAK_ADMIN_PASSWORD=${var.keycloak_admin_password}",
    "KC_HTTP_PORT=${var.keycloak_port}",
    "KC_HEALTH_ENABLED=true",
    "KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/certs/tls.crt",
    "KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/certs/tls.key",
    "KC_HTTPS_PORT=${var.keycloak_https_port}",
    "KC_HOSTNAME_URL=https://${var.keycloak_server}:${var.keycloak_https_port}"
  ]

  command = ["start-dev"]

  volumes {
    volume_name    = docker_volume.keycloak_data.name
    container_path = "/opt/keycloak/data"
  }

  volumes {
    volume_name    = var.pki_certs_volume_name
    container_path = "/opt/keycloak/certs"
    read_only      = true
  }

  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }

  ports {
    internal = var.keycloak_port
    external = var.keycloak_external_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }

  ports {
    internal = var.keycloak_https_port
    external = var.keycloak_https_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }

  healthcheck {
    test     = ["CMD-SHELL", "bash -c '</dev/tcp/localhost/${var.keycloak_port}' 2>/dev/null || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 10
    start_period = "60s"
  }

  wait         = true
  wait_timeout = 300
  restart      = "on-failure"
  depends_on   = [null_resource.wait_for_vault_certs]
}

# Create OIDC realm
resource "null_resource" "keycloak_realm" {
  depends_on = [docker_container.keycloak_server]

  provisioner "local-exec" {
    command = <<-EOT
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:${var.keycloak_port} \
        --realm master \
        --user ${var.keycloak_admin_user} \
        --password ${var.keycloak_admin_password}
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh create realms \
        -s realm=${var.oidc_realm} \
        -s enabled=true \
        -s displayName=${var.oidc_realm}
    EOT
  }
}

# Create OIDC client for MongoDB
resource "null_resource" "keycloak_client" {
  depends_on = [null_resource.keycloak_realm]

  provisioner "local-exec" {
    command = <<-EOT
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:${var.keycloak_port} \
        --realm master \
        --user ${var.keycloak_admin_user} \
        --password ${var.keycloak_admin_password}
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh create clients \
        -r ${var.oidc_realm} \
        -s clientId=${var.oidc_client_id} \
        -s enabled=true \
        -s protocol=openid-connect \
        -s publicClient=false \
        -s secret=${var.oidc_client_secret} \
        -s standardFlowEnabled=true \
        -s directAccessGrantsEnabled=true \
        -s serviceAccountsEnabled=true
    EOT
  }
}

# Create OIDC users in Keycloak
resource "null_resource" "keycloak_users" {
  count      = length(var.oidc_users)
  depends_on = [null_resource.keycloak_realm]

  provisioner "local-exec" {
    command = <<-EOT
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:${var.keycloak_port} \
        --realm master \
        --user ${var.keycloak_admin_user} \
        --password ${var.keycloak_admin_password}
      USER_ID=$(docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh create users \
        -r ${var.oidc_realm} \
        -s username=${var.oidc_users[count.index].username} \
        -s enabled=true \
        -s email=${var.oidc_users[count.index].email} \
        -s firstName=${var.oidc_users[count.index].first_name} \
        -s lastName=${var.oidc_users[count.index].last_name} \
        -i)
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh set-password \
        -r ${var.oidc_realm} \
        --userid "$USER_ID" \
        --new-password ${var.oidc_users[count.index].password}
    EOT
  }
}
