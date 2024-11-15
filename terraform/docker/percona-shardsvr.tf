resource "docker_volume" "shard_volume" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
}

resource "docker_container" "shard" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  image = var.docker_image
  mounts {
    source = local_file.mongodb_keyfile.filename
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}",  
    "--bind_ip_all",    
    "--shardsvr",
    "--keyFile", "/etc/mongo/mongodb-keyfile.key"
  ]  
  #env = [ "MONGO_INITDB_ROOT_USERNAME=mongoadmin", "MONGO_INITDB_ROOT_PASSWORD=secret" ]
  labels { 
    label = "replsetName"
    value = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}"
  }    
  labels { 
    label = "ansible-group"
    value = floor(count.index / var.shardsvr_replicas )
  }
  labels { 
    label = "ansible-index"
    value = count.index % var.shardsvr_replicas
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
    test        = ["CMD-SHELL", "mongosh --port 27018 --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }
  wait = true
  restart = "no"
}

resource "docker_container" "pbm_shard" {
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-pbm"
  count = var.shard_count * var.shardsvr_replicas
  image = var.custom_image 
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=pbm:percona@${docker_container.shard[count.index].name}:27018" ]
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
  restart = "no"
}