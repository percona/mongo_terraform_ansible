# Docker volume for Keycloak TLS certificate and CA cert (shared with MongoDB containers)
resource "docker_volume" "keycloak_certs" {
  name = var.pki_certs_volume_name
}

# Generate a self-signed TLS certificate using the Terraform TLS provider
resource "tls_private_key" "keycloak" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "keycloak" {
  private_key_pem = tls_private_key.keycloak.private_key_pem

  subject {
    common_name = var.keycloak_server
  }

  validity_period_hours = 8760 # 1 year

  is_ca_certificate = true

  dns_names    = [var.keycloak_server, "localhost"]
  ip_addresses = ["127.0.0.1"]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "cert_signing",
    "crl_signing",
  ]
}

# Alpine image used by the cert init container
data "docker_registry_image" "alpine" {
  name = "alpine:3.21"
}

resource "docker_image" "alpine" {
  name          = "alpine:3.21"
  pull_triggers = [data.docker_registry_image.alpine.sha256_digest]
  keep_locally  = true
}

# Write the generated cert and key into the shared Docker volume so that
# Keycloak and MongoDB containers can mount it directly — no docker cp needed.
resource "docker_container" "init_keycloak_certs" {
  name         = "${var.keycloak_server}-init-certs"
  image        = docker_image.alpine.image_id
  network_mode = "bridge"
  command = [
    "sh", "-c",
    join(" && ", [
      "printf '%s' \"$TLS_CERT\" | base64 -d > /certs/tls.crt",
      "cp /certs/tls.crt /certs/ca.crt",
      "printf '%s' \"$TLS_KEY\" | base64 -d > /certs/tls.key",
      "chmod 644 /certs/tls.crt /certs/tls.key /certs/ca.crt",
    ])
  ]
  env = [
    "TLS_CERT=${base64encode(tls_self_signed_cert.keycloak.cert_pem)}",
    "TLS_KEY=${base64encode(tls_private_key.keycloak.private_key_pem)}",
  ]
  mounts {
    target = "/certs"
    source = docker_volume.keycloak_certs.name
    type   = "volume"
  }
  # must_run = false: this is an ephemeral init container; it exits after writing
  # the certs to the volume and must not be kept running.
  must_run = false
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
    volume_name    = docker_volume.keycloak_certs.name
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
    external = var.keycloak_https_external_port
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
  depends_on   = [docker_container.init_keycloak_certs]
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
      CLIENT_ID=$(docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh create clients \
        -r ${var.oidc_realm} \
        -s clientId=${var.oidc_client_id} \
        -s enabled=true \
        -s protocol=openid-connect \
        -s publicClient=true \
        -s standardFlowEnabled=true \
        -s directAccessGrantsEnabled=true \
        -i)
      if [ -z "$CLIENT_ID" ]; then
        echo "ERROR: Failed to create Keycloak client '${var.oidc_client_id}' - no client ID returned. Check Keycloak logs for details."
        exit 1
      fi
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:${var.keycloak_port} \
        --realm master \
        --user ${var.keycloak_admin_user} \
        --password ${var.keycloak_admin_password}
      docker exec ${var.keycloak_server} /opt/keycloak/bin/kcadm.sh update "clients/$CLIENT_ID" \
        -r ${var.oidc_realm} \
        -s 'attributes={"oauth2.device.authorization.grant.enabled":"true"}'
    EOT
  }
}

# Create OIDC users in Keycloak
resource "null_resource" "keycloak_users" {
  count      = length(var.oidc_users)
  depends_on = [null_resource.keycloak_client]

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
