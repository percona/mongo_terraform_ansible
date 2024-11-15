resource "docker_volume" "arb_volume" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-data"
}

resource "docker_container" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  image = var.docker_image 
  mounts {
    source = local_file.mongodb_keyfile.filename
    target = "/etc/mongo/mongodb-keyfile.key"
    type   = "bind"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}",  
    "--bind_ip_all",   
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
    test        = ["CMD-SHELL", "mongosh --port 27018 --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true
  restart = "no"
}