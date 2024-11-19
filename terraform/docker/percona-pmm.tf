# Create a Docker volume to simulate the attached disk
resource "docker_volume" "pmm_volume" {
  name = "${var.env_tag}-${var.pmm_tag}-data"
}

# Create a Docker container for the PMM server
resource "docker_container" "pmm" {
  name  = "${var.env_tag}-${var.pmm_tag}"
  image = var.pmm_server_image
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.pmm_volume.name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  ports {
    internal = 443
    external = 443
  }  
  restart = "on-failure"

}