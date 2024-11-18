resource "docker_volume" "arb_volume" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-data"
}

resource "docker_container" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  image = var.psmdb_image 
  mounts {
    source = abspath(local_file.mongodb_keyfile.filename)
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}",  
    "--bind_ip_all",   
    "--port", "${var.shardsvr_port}",
    "--shardsvr",
    "--keyFile", "/etc/mongo/mongodb-keyfile.key"
  ]
  #env = [ "MONGO_INITDB_ROOT_USERNAME=mongoadmin", "MONGO_INITDB_ROOT_PASSWORD=secret" ]
  labels { 
    label = "replsetName"
    value = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}"
  }  
  labels { 
    label = "ansible-group"
    value = floor(count.index / var.arbiters_per_replset )
  }
  labels { 
    label = "ansible-index" 
    value = count.index % var.arbiters_per_replset
  }
  labels { 
    label = "environment" 
    value = var.env_tag
  }      
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.arb_volume[count.index].name
  } 
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.shardsvr_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true
  restart = "no"
}

resource "docker_volume" "arb_volume_pmm" {
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-pmm-client-data"
  count = var.shard_count * var.arbiters_per_replset
}

resource "docker_container" "pmm_arb" {
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-pmm"
  image = var.pmm_client_image 
  count = var.shard_count * var.arbiters_per_replset
#  command = [
#    "pbm-agent"
#  ]  
  env = [ "PMM_AGENT_SERVER_ADDRESS=${docker_container.pmm.name}:443", "PMM_AGENT_SERVER_USERNAME=admin", "PMM_AGENT_SERVER_PASSWORD=admin", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=1", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.arb_volume_pmm[count.index].name
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