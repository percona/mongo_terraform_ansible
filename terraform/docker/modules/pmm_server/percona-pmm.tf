# Create a Docker container for the Grafana renderer
resource "docker_image" "renderer" {
  name         = var.renderer_image
  keep_locally = true
}

resource "docker_container" "renderer" {
  name  = var.renderer_tag
  hostname = var.renderer_tag
  image = docker_image.renderer.image_id
  env = [ "IGNORE_HTTPS_ERRORS=true" ]
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  healthcheck {
    test        = ["CMD", "node", "--version" ]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }    
  wait = true
  restart = "on-failure"
}

resource "docker_image" "watchtower" {
  name         = var.watchtower_image
  keep_locally = true
}

# Create a Docker container for Watchtower
resource "docker_container" "watchtower" {
  name  = var.watchtower_tag
  hostname = var.watchtower_tag
  image = docker_image.watchtower.image_id
  env = [ "WATCHTOWER_HTTP_API_TOKEN=${var.watchtower_token}", "WATCHTOWER_HTTP_API_UPDATE=1" ]
  mounts {
    target = var.docker_socket
    source = var.docker_socket
    type   = "bind"
  }  
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  wait = true
  restart = "on-failure"
}

# Create a Docker volume for PMM Server data
resource "docker_volume" "pmm_volume" {
  name = "${var.pmm_host}-data"
}

resource "docker_image" "pmm" {
  name         = var.pmm_server_image
  keep_locally = true
}

# Create a Docker container for the PMM server
resource "docker_container" "pmm" {
  name  = var.pmm_host
  hostname  = var.pmm_host
  domainname = var.domain_name
  depends_on = [
    docker_container.renderer
  ]  
  image = docker_image.pmm.image_id
  env = [ "GF_RENDERING_SERVER_URL=http://${docker_container.renderer.name}:${var.renderer_port}/render", "GF_RENDERING_CALLBACK_URL=https://${var.pmm_host}:${var.pmm_port}/graph/", "PMM_WATCHTOWER_HOST=http://${docker_container.watchtower.name}:${var.watchtower_port}","PMM_WATCHTOWER_TOKEN=${var.watchtower_token}" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.pmm_volume.name
  }
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  ports {
    internal = var.pmm_port
    external = var.pmm_external_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }  
  healthcheck {
    test        = ["CMD", "curl", "-k", "-f", "https://${var.pmm_host}:${var.pmm_port}/v1/readyz" ]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }    
  wait = true
  restart = "on-failure"
}

resource "null_resource" "change_pmm_admin_password" {
  depends_on = [
    docker_container.pmm
  ]

  provisioner "local-exec" {
    command = <<-EOT
      docker exec -t ${var.pmm_host} bash -c  "grafana cli --homepath /usr/share/grafana --config=/etc/grafana/grafana.ini admin reset-admin-password ${var.pmm_server_pwd}"
    EOT
  }
}