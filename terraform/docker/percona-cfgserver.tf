resource "docker_volume" "cfg_volume" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-data"
  count = var.configsvr_count
}

resource "docker_container" "cfg" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}"
  image = var.docker_image 
  mounts {
    source = local_file.mongodb_keyfile.filename
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
    test        = ["CMD-SHELL", "mongosh --port 27019 --eval 'db.runCommand({ ping: 1 })'"]
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
  env = [ "PBM_MONGODB_URI=pbm:percona@${docker_container.cfg[count.index].name}:27019" ]
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
  restart = "no"
}