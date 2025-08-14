resource "docker_container" "pbm_rs" {
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-${var.pbm_container_suffix}"
  count = var.enable_pbm ? var.data_nodes_per_replset : 0
  image = docker_image.pbm_mongod_rs.image_id
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.rs[count.index].name}:${var.replset_port + count.index}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.rs_volume[count.index].name
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