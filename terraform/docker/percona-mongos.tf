# Create Docker containers for MongoDB mongos
resource "docker_container" "mongos" {
  count = var.mongos_count
  name  = "${var.env_tag}-${var.mongos_tag}0${count.index}"
  image = var.docker_image
  command = ["/bin/bash", "-c", "while true; do sleep 30; done;"]
  labels { 
    label = "ansible-group"
    value = "cfg"
  }
  labels { 
    label = "environment"
    value = var.env_tag
  }  
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  restart = "on-failure"
}
