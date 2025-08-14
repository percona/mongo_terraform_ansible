resource "docker_volume" "shard_volume_pmm" {
  count = var.enable_pmm ? var.shard_count * var.shardsvr_replicas : 0
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-pmm-client-data"
}

resource "docker_container" "pmm_shard" {
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-${var.pmm_client_container_suffix}"
  image = docker_image.pmm_client.image_id  
  count = var.enable_pmm ? var.shard_count * var.shardsvr_replicas : 0
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.shard_volume_pmm[count.index].name
  }
  network_mode = "bridge"
  networks_advanced {
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "pmm-admin status"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }   
  wait = false  
  restart = "on-failure"
}