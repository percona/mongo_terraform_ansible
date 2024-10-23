# Create Docker volumes
resource "docker_volume" "cfg_volume" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-data"
  count = var.configsvr_count
}

# Create Docker containers for MongoDB Config Server
resource "docker_container" "cfg" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}"
  image = var.docker_image 
  command = ["/bin/bash", "-c", "while true; do sleep 30; done;"]
  count = var.configsvr_count
  labels { 
    label = "ansible-group"
    value = "cfg"
  }
  labels { 
    label = "environment"
    value = var.env_tag
  }  

  mounts {
    type = "volume"
    target = "/var/lib/mongo"
    source = docker_volume.cfg_volume[count.index].name
  }

  networks_advanced {
    name = docker_network.mongo_network.id
  }

  restart = "on-failure"
}