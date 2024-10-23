# Create Docker containers for MongoDB Arbiters
resource "docker_container" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  image = var.docker_image 
  command = ["/bin/bash", "-c", "while true; do sleep 30; done;"]
  labels { 
    label = "ansible-group"
    value = floor(count.index / var.arbiters_per_replset )
  }
  labels { 
    label = "ansible-index" 
    value = count.index % var.arbiters_per_replset
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

