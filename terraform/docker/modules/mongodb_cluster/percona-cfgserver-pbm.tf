resource "docker_container" "pbm_cfg" {
  for_each = var.enable_pbm ? local.cfg_members : {}
  name     = "${var.cluster_name}-${var.configsvr_tag}0${each.value}-${var.pbm_container_suffix}"
  image    = docker_image.pbm_mongod.image_id
  user     = var.uid
  command = [
    "pbm-agent"
  ]
  env = ["PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.cfg[each.key].name}:${var.configsvr_port}"]
  mounts {
    type   = "volume"
    target = "/data/db"
    source = docker_volume.cfg_volume[each.key].name
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
