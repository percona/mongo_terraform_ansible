resource "docker_container" "ycsb" {
  name = "${var.env_tag}-${var.ycsb_container_suffix}"
  image = var.ycsb_image 
  command = [ "sleep", "infinity"]
  networks_advanced {
    name = "${var.network_name}"
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
