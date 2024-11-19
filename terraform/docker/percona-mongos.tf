# Create Docker containers for MongoDB mongos
resource "docker_container" "mongos" {
  count = var.mongos_count
  name  = "${var.env_tag}-${var.mongos_tag}0${count.index}"
  image = var.psmdb_image
  command = [
    "mongos",
    "--configdb", "${lookup({for label in docker_container.cfg[0].labels : label.label => label.value}, "replsetName", null)}/${join(",", [for i in range(var.configsvr_count) : "${docker_container.cfg[i].name}:${var.configsvr_port}" ])}",
    "--bind_ip_all",    
    "--port", "${var.mongos_port}",
    "--keyFile", "/etc/mongo/mongodb-keyfile.key"
  ]    
  ports {
    internal = var.mongos_port
    external = var.mongos_port
  }  
  mounts {
    source = abspath(local_file.mongodb_keyfile.filename)
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  labels { 
    label = "environment"
    value = var.env_tag
  }  
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.mongos_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }  
  wait = true
  restart = "no"
}

resource "docker_volume" "mongos_volume_pmm" {
  name  = "${var.env_tag}-${var.mongos_tag}0${count.index}-pmm-client-data"
  count = var.mongos_count
}

resource "docker_container" "pmm_mongos" {
  name  = "${var.env_tag}-${var.mongos_tag}0${count.index}-pmm"
  image = var.pmm_client_image 
  count = var.mongos_count
  env = [ "PMM_AGENT_SERVER_ADDRESS=${docker_container.pmm.name}:443", "PMM_AGENT_SERVER_USERNAME=admin", "PMM_AGENT_SERVER_PASSWORD=admin", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=1", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.mongos_volume_pmm[count.index].name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "pmm-admin status"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true  
  restart = "on-failure"
}