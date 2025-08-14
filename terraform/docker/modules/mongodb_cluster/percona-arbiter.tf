resource "docker_volume" "arb_volume" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-data"
}

resource "docker_container" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  hostname = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  domainname = var.domain_name
  image = docker_image.psmdb.image_id 
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}",  
    "--bind_ip_all",   
    "--port", "${var.arbiter_port}",
    "--shardsvr",
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}"
  ]
  ports {
    internal = var.arbiter_port  
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }    
  user = var.uid
  labels { 
    label = "replsetName"
    value = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}"
  }  
  labels { 
    label = "environment" 
    value = var.env_tag
  }
  network_mode = "bridge"     
  networks_advanced {
    name = "${var.network_name}"
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
  depends_on = [docker_container.init_keyfile]
}