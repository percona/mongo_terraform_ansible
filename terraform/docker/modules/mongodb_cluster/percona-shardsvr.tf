resource "docker_volume" "shard_volume" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
}

resource "docker_container" "shard" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  image = var.psmdb_image
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}",  
    "--bind_ip_all",    
    "--port", "${var.shardsvr_port}",
    "--shardsvr",
    "--oplogSize", "200",
    "--wiredTigerCacheSizeGB", "0.25",      
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}",
    "--profile", "2",
    "--slowms", "200",
    "--rateLimit", "100"
  ]  
  user = var.uid
  ports {
    internal = var.shardsvr_port
    ip = "127.0.0.1" 
  }  
  labels { 
    label = "replsetName"
    value = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}"
  }    
  labels { 
    label = "environment"
    value = var.env_tag
  }  
  networks_advanced {
    name = "${var.network_name}"
  }
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.shard_volume[count.index].name
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.shardsvr_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }
  wait = true
  restart = "no"
  depends_on = [docker_container.init_keyfile_container]
}

resource "docker_container" "pbm_shard" {
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-${var.pbm_container_suffix}"
  count = var.shard_count * var.shardsvr_replicas
  image = var.pbm_mongod_image 
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.shard[count.index].name}:${var.shardsvr_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.shard_volume[count.index].name
  }
  networks_advanced {
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "pbm version"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true    
  restart = "on-failure"
}

resource "docker_volume" "shard_volume_pmm" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-pmm-client-data"
}

resource "docker_container" "pmm_shard" {
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-${var.pmm_client_container_suffix}"
  image = var.pmm_client_image 
  count = var.shard_count * var.shardsvr_replicas
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.shard_volume_pmm[count.index].name
  }
  networks_advanced {
    name = "${var.network_name}"
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
