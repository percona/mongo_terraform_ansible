
# Create a Docker container for the Grafana renderer
resource "docker_container" "renderer" {
  name  = var.renderer_tag
  image = var.renderer_image
  env = [ "IGNORE_HTTPS_ERRORS=true" ]
  networks_advanced {
    name = docker_network.mongo_network.id
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

# Create a Docker container for Watchtower
resource "docker_container" "watchtower" {
  name  = var.watchtower_tag
  image = var.watchtower_image
  env = [ "WATCHTOWER_HTTP_API_TOKEN=${var.watchtower_token}", "WATCHTOWER_HTTP_API_UPDATE=1" ]
  mounts {
    target = "/var/run/docker.sock"
    source = "/var/run/docker.sock"
    type   = "bind"
  }  
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  wait = true
  restart = "on-failure"
}

# Create a Docker volume for PMM Server data
resource "docker_volume" "pmm_volume" {
  name = "${var.pmm_host}-data"
}

# Create a Docker container for the PMM server
resource "docker_container" "pmm" {
  name  = var.pmm_host
  depends_on = [
    docker_container.renderer,
    docker_container.watchtower
  ]  
  image = var.pmm_server_image
  env = [ "GF_RENDERING_SERVER_URL=http://${docker_container.renderer.name}:${var.renderer_port}/render", "GF_RENDERING_CALLBACK_URL=https://${var.pmm_host}:${var.pmm_port}/graph/", "PMM_WATCHTOWER_HOST=http://${docker_container.watchtower.name}:${var.watchtower_port}","PMM_WATCHTOWER_TOKEN=${var.watchtower_token}" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.pmm_volume.name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  ports {
    internal = var.pmm_port
    external = var.pmm_external_port
    #ip = "127.0.0.1"  
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