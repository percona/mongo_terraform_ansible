# PBM CLI container
resource "docker_container" "pbm_cli" {
  name  = "${var.env_tag}-${var.pbm_cli_container_suffix}"
  count = 1
  image = var.pbm_image 
  command = ["/bin/sh", "-c", "while true; do sleep 86400; done;"]
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.shard[0].name}:${var.configsvr_port}" ]
  mounts {
    source      = abspath(local_file.storage_config.filename)
    target      = "/etc/pbm-storage.conf"
    type        = "bind"
  }  
  networks_advanced {
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "pbm version"]
    interval    = "10s"
    timeout     = "5s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true     
  restart = "on-failure"
}