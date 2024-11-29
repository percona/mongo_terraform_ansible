resource "docker_volume" "shard_volume" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
}

resource "docker_container" "shard" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  image = var.psmdb_image
  mounts {
    source = abspath(local_file.mongodb_keyfile.filename)
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}",  
    "--bind_ip_all",    
    "--port", "${var.shardsvr_port}",
    "--shardsvr",
    "--keyFile", "/etc/mongo/mongodb-keyfile.key",
    "--profile", "2",
    "--slowms", "200",
    "--rateLimit", "100"
  ]  
  user = var.uid
  ports {
    internal = var.shardsvr_port
  }  
  labels { 
    label = "replsetName"
    value = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}"
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
    source = docker_volume.shard_volume[count.index].name
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

resource "docker_container" "pbm_shard" {
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-${var.pbm_image_suffix}"
  count = var.shard_count * var.shardsvr_replicas
  image = var.custom_image 
  user  = 1001
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=pbm:percona@${docker_container.shard[count.index].name}:${var.shardsvr_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.shard_volume[count.index].name
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

resource "docker_volume" "shard_volume_pmm" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-pmm-client-data"
}

resource "docker_container" "pmm_shard" {
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-${var.pmm_client_container_suffix}"
  image = var.pmm_client_image 
  count = var.shard_count * var.shardsvr_replicas
  env = [ "PMM_AGENT_SERVER_ADDRESS=${docker_container.pmm.name}:${var.pmm_port}", "PMM_AGENT_SERVER_USERNAME=${var.pmm_user}", "PMM_AGENT_SERVER_PASSWORD=${var.pmm_password}", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.shard_volume_pmm[count.index].name
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  ports {
    internal = 42002
  }    
  healthcheck {
    test        = ["CMD-SHELL", "pmm-admin status"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }   
  wait = false  
  restart = "on-failure"
}
