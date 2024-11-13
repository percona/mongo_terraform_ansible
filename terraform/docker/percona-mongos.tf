# Create Docker containers for MongoDB mongos
resource "docker_container" "mongos" {
  count = var.mongos_count
  name  = "${var.env_tag}-${var.mongos_tag}0${count.index}"
  image = var.docker_image
  command = [
    "mongos",
    "--configdb", "${lookup({for label in docker_container.cfg[0].labels : label.label => label.value}, "replsetName", null)}/${join(",", [for i in range(var.configsvr_count) : "${docker_container.cfg[i].name}:27019" ])}",
    "--bind_ip_all",    
    "--keyFile", "/etc/mongo/mongodb-keyfile.key"
  ]    
  mounts {
    source = local_file.mongodb_keyfile.filename
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  labels { 
    label = "ansible-group"
    value = "cfg"
  }
  labels { 
    label = "environment"
    value = var.env_tag
  }  
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port 27017 --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }  
  wait = true
  restart = "on-failure"
}
