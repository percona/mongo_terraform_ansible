resource "docker_container" "pbm_rs" {
  for_each = var.enable_pbm ? local.replset_members : {}
  name     = "${var.rs_name}-${var.replset_tag}${each.value.member_index}-${var.pbm_container_suffix}"
  image    = docker_image.pbm_mongod_rs.image_id
  user     = var.uid
  command = [
    "pbm-agent"
  ]
  env = ["PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.rs[each.key].name}:${var.replset_port + each.value.member_index}"]
  mounts {
    type   = "volume"
    target = "/data/db"
    source = docker_volume.rs_volume[each.key].name
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
    replace_triggered_by = [docker_image.pbm_mongod_rs]
  }
}
