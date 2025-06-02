locals {
  ycsb_dockerfile_content = templatefile("${path.module}/ycsb.Dockerfile.tmpl", {
    ycsb_os_image    = var.ycsb_os_image        
  })    
}

# Write YCSB Dockerfile to disk
resource "local_file" "ycsb_dockerfile_content" {
  filename = "${path.module}/${var.ycsb_image}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

# Get base OS image
resource "docker_image" "ycsb_os" {
  name         = var.ycsb_os_image
  keep_locally = true  
}

# Build YCSB Docker image
resource "docker_image" "ycsb" {
  depends_on = [
    docker_image.ycsb_os
  ]  
  name = var.ycsb_image
  build {
    context    = path.module
    dockerfile = "${var.ycsb_image}.Dockerfile"
  }
}

# Create YCSB container
resource "docker_container" "ycsb" {
  name = "${var.ycsb_container_suffix}"
  image = docker_image.ycsb.image_id
  command = [ "sleep", "infinity"]
  network_mode = "bridge"
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
