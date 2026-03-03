# Generate self-signed TLS certificate for Keycloak HTTPS
resource "null_resource" "keycloak_certs" {
  triggers = {
    keycloak_server = var.keycloak_server
    cert_dir        = var.keycloak_cert_dir
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p ${var.keycloak_cert_dir}
      openssl req -x509 -newkey rsa:2048 \
        -keyout ${var.keycloak_cert_dir}/tls.key \
        -out ${var.keycloak_cert_dir}/tls.crt \
        -days 730 -nodes \
        -subj "/CN=${var.keycloak_server}" \
        -addext "subjectAltName=DNS:${var.keycloak_server},DNS:localhost,IP:127.0.0.1"
      cp ${var.keycloak_cert_dir}/tls.crt ${var.keycloak_cert_dir}/ca.crt
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

  mounts {
    type      = "bind"
    source    = "${var.keycloak_cert_dir}/tls.crt"
    target    = "/opt/keycloak/certs/tls.crt"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "${var.keycloak_cert_dir}/tls.key"
    target    = "/opt/keycloak/certs/tls.key"
    read_only = true
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
  depends_on   = [null_resource.keycloak_certs]
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
