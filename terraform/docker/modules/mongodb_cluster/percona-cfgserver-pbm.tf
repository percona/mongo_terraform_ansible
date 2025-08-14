resource "docker_container" "pbm_cfg" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-${var.pbm_container_suffix}"
  image = docker_image.pbm_mongod.image_id
  count = var.enable_pbm ? var.configsvr_count : 0
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.cfg[count.index].name}:${var.configsvr_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.cfg_volume[count.index].name
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