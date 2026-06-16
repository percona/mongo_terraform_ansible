resource "docker_container" "pbm_shard" {
  for_each = var.enable_pbm ? local.shard_members : {}
  name     = "${var.cluster_name}-${var.shardsvr_tag}0${each.value.shard_index}svr${each.value.replica_index}-${var.pbm_container_suffix}"
  image    = docker_image.pbm_mongod.image_id
  user     = var.uid
  command = [
    "pbm-agent"
  ]
  env = ["PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.shard[each.key].name}:${var.shardsvr_port}"]
  mounts {
    type   = "volume"
    target = "/data/db"
    source = docker_volume.shard_volume[each.key].name
  }
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  healthcheck {
    test         = ["CMD-SHELL", "pbm version"]
    interval     = "10s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }
  wait    = true
  restart = "on-failure"

  lifecycle {
    replace_triggered_by = [docker_image.pbm_mongod]
  }
}
