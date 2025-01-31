resource "docker_container" "ycsb" {
  depends_on = [null_resource.docker_build_ycsb]
  name = "${var.env_tag}-${var.ycsb_container_suffix}"
  image = var.ycsb_image 
  command = [ "sleep", "infinity"]
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "/ycsb/bin/ycsb --help"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }   
  wait = false  
  restart = "on-failure"
}
