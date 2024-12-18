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
    "--port", "${var.arbiter_port}",
    "--shardsvr",
    "--keyFile", "${var.keyfile_path}"
  ]
  ports {
    internal = var.arbiter_port    
  }    
  user = var.uid
  labels { 
    label = "replsetName"
    value = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}"
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
    test        = ["CMD-SHELL", "mongosh --port ${var.arbiter_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "10s"
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
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-${var.pmm_client_container_suffix}"
  image = var.pmm_client_image 
  count = var.shard_count * var.arbiters_per_replset
  env = [ "PMM_AGENT_SERVER_ADDRESS=${docker_container.pmm.name}:${var.pmm_port}", "PMM_AGENT_SERVER_USERNAME=${var.pmm_user}", "PMM_AGENT_SERVER_PASSWORD=${var.pmm_password}", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.arb_volume_pmm[count.index].name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  ports {
    internal = var.pmm_client_port
  }    
  healthcheck {
    test        = ["CMD-SHELL", "pmm-admin status"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }   
  wait = false  
  restart = "on-failure"
}