resource "docker_volume" "cfg_volume" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-data"
  count = var.configsvr_count
}

resource "docker_container" "cfg" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}"
  image = var.psmdb_image 
  mounts {
    source = abspath(local_file.mongodb_keyfile.filename)
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  count = var.configsvr_count
  command = [
    "mongod",
    "--replSet", "${var.env_tag}-${var.configsvr_tag}",  
    "--bind_ip_all",    
    "--configsvr",
    "--port", "${var.configsvr_port}",
    "--dbpath", "/data/db",
    "--keyFile", "/etc/mongo/mongodb-keyfile.key"
  ]  
  #env = [ "MONGO_INITDB_ROOT_USERNAME=mongoadmin", "MONGO_INITDB_ROOT_PASSWORD=secret" ]
  labels { 
    label = "replsetName"
    value = "${var.env_tag}-${var.configsvr_tag}"
  }    
  labels { 
    label = "ansible-group"
    value = "cfg"
  }
  labels { 
    label = "environment"
    value = var.env_tag
  }  
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.cfg_volume[count.index].name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.configsvr_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }
  wait = true
  restart = "no"
}

resource "docker_container" "pbm_cfg" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-pbm"
  image = var.custom_image 
  count = var.configsvr_count
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=pbm:percona@${docker_container.cfg[count.index].name}:${var.configsvr_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.cfg_volume[count.index].name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "pbm version"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true  
  restart = "on-failure"
}

resource "docker_volume" "cfg_volume_pmm" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-pmm-client-data"
  count = var.configsvr_count
}

resource "docker_container" "pmm_cfg" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-pmm"
  image = var.pmm_client_image 
  count = var.configsvr_count
#  command = [
#    "pbm-agent"
#  ]  
  env = [ "PMM_AGENT_SERVER_ADDRESS=${docker_container.pmm.name}:443", "PMM_AGENT_SERVER_USERNAME=admin", "PMM_AGENT_SERVER_PASSWORD=admin", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=1", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.cfg_volume_pmm[count.index].name
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