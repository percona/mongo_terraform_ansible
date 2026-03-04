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

# Provision Vault KV secrets engine and store MongoDB encryption key
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

      # Enable KV secrets engine and store MongoDB encryption key
      vault secrets enable -path=${var.vault_kv_path_prefix} kv
      vault kv put ${var.vault_kv_path} key=$(openssl rand -base64 32)

      VAULT_EOF
    EOT
  }
}