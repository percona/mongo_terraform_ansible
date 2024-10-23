# Create Docker volumes to replace Google Compute Disks for shard servers
resource "docker_volume" "shard_volume" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
}

# Create Docker containers to replace Google Compute Instances for shard servers
resource "docker_container" "shard" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  image = var.docker_image
  command = ["/bin/bash", "-c", "while true; do sleep 30; done;"]
  labels { 
    label = "ansible-group"
    value = floor(count.index / var.shardsvr_replicas )
  }
  labels { 
    label = "ansible-index"
    value = count.index % var.shardsvr_replicas
  }
  labels { 
    label = "environment"
    value = var.env_tag
  }  

  networks_advanced {
    name = docker_network.mongo_network.id
  }

  mounts {
    type = "volume"
    target = "/var/lib/mongo"
    source = docker_volume.shard_volume[count.index].name
  }

  restart = "always"
}
