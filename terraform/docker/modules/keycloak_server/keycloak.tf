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
    "KC_HEALTH_ENABLED=true"
  ]

  command = ["start-dev"]

  volumes {
    volume_name    = docker_volume.keycloak_data.name
    container_path = "/opt/keycloak/data"
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

  healthcheck {
    test     = ["CMD-SHELL", "curl -f -s http://localhost:${var.keycloak_port}/realms/master > /dev/null || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 10
    start_period = "60s"
  }

  wait         = true
  wait_timeout = 300
  restart      = "on-failure"
}

# Create OIDC realm
resource "null_resource" "keycloak_realm" {
  depends_on = [docker_container.keycloak_server]

  provisioner "local-exec" {
    command = <<-EOT
      get_token() {
        curl -sf -X POST \
          "http://localhost:${var.keycloak_external_port}/realms/master/protocol/openid-connect/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=admin-cli" \
          -d "username=${var.keycloak_admin_user}" \
          -d "password=${var.keycloak_admin_password}" \
          -d "grant_type=password" | \
          (command -v jq > /dev/null 2>&1 && jq -r '.access_token' || grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')
      }

      TOKEN=$(get_token)
      curl -sf -X POST \
        "http://localhost:${var.keycloak_external_port}/admin/realms" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"realm": "${var.oidc_realm}", "enabled": true, "displayName": "${var.oidc_realm}"}'
    EOT
  }
}

# Create OIDC client for MongoDB
resource "null_resource" "keycloak_client" {
  depends_on = [null_resource.keycloak_realm]

  provisioner "local-exec" {
    command = <<-EOT
      get_token() {
        curl -sf -X POST \
          "http://localhost:${var.keycloak_external_port}/realms/master/protocol/openid-connect/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=admin-cli" \
          -d "username=${var.keycloak_admin_user}" \
          -d "password=${var.keycloak_admin_password}" \
          -d "grant_type=password" | \
          (command -v jq > /dev/null 2>&1 && jq -r '.access_token' || grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')
      }

      TOKEN=$(get_token)
      curl -sf -X POST \
        "http://localhost:${var.keycloak_external_port}/admin/realms/${var.oidc_realm}/clients" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
          "clientId": "${var.oidc_client_id}",
          "enabled": true,
          "protocol": "openid-connect",
          "publicClient": false,
          "secret": "${var.oidc_client_secret}",
          "standardFlowEnabled": true,
          "directAccessGrantsEnabled": true,
          "serviceAccountsEnabled": true
        }'
    EOT
  }
}

# Create OIDC users in Keycloak
resource "null_resource" "keycloak_users" {
  count      = length(var.oidc_users)
  depends_on = [null_resource.keycloak_realm]

  provisioner "local-exec" {
    command = <<-EOT
      get_token() {
        curl -sf -X POST \
          "http://localhost:${var.keycloak_external_port}/realms/master/protocol/openid-connect/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=admin-cli" \
          -d "username=${var.keycloak_admin_user}" \
          -d "password=${var.keycloak_admin_password}" \
          -d "grant_type=password" | \
          (command -v jq > /dev/null 2>&1 && jq -r '.access_token' || grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')
      }

      TOKEN=$(get_token)

      # Create user and extract user ID from Location header
      USER_ID=$(curl -sf -X POST \
        "http://localhost:${var.keycloak_external_port}/admin/realms/${var.oidc_realm}/users" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
          "username": "${var.oidc_users[count.index].username}",
          "enabled": true,
          "email": "${var.oidc_users[count.index].email}",
          "firstName": "${var.oidc_users[count.index].first_name}",
          "lastName": "${var.oidc_users[count.index].last_name}"
        }' -D - | awk '/^[Ll]ocation:/{gsub(/\r/,"",$2); n=split($2,a,"/"); print a[n]}')

      if [ -z "$USER_ID" ]; then
        echo "Failed to create user ${var.oidc_users[count.index].username} or extract user ID"
        exit 1
      fi

      curl -sf -X PUT \
        "http://localhost:${var.keycloak_external_port}/admin/realms/${var.oidc_realm}/users/$USER_ID/reset-password" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"type": "password", "value": "${var.oidc_users[count.index].password}", "temporary": false}'
    EOT
  }
}
