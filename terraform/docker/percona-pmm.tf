
# Create a Docker container for the Grafana renderer container
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

# Create a Docker volume to simulate the attached disk
resource "docker_volume" "pmm_volume" {
  name = "${var.pmm_host}-data"
}

# Create a Docker container for the PMM server
resource "docker_container" "pmm" {
  name  = var.pmm_host
  depends_on = [
    docker_container.renderer
  ]  
  image = var.pmm_server_image
  env = [ "GF_RENDERING_SERVER_URL=http://${docker_container.renderer.name}:${var.renderer_port}/render", "GF_RENDERING_CALLBACK_URL=https://${var.pmm_host}:${var.pmm_port}/graph/" ]
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