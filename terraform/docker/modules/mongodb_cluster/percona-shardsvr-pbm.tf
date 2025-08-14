resource "docker_container" "pbm_shard" {
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-${var.pbm_container_suffix}"
  count = var.enable_pbm ? var.shard_count * var.shardsvr_replicas : 0
  image = docker_image.pbm_mongod.image_id
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.shard[count.index].name}:${var.shardsvr_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.shard_volume[count.index].name
  }
  network_mode = "bridge"
  networks_advanced {
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "pbm version"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true    
  restart = "on-failure"
}