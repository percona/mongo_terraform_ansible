resource "docker_volume" "arb_volume" {
  count = var.arbiters_per_replset
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-data"
}

resource "docker_container" "arbiter" {
  count = var.arbiters_per_replset
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  image = var.psmdb_image 
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.arbiters_per_replset)}",  
    "--bind_ip_all",   
    "--port", "${var.arbiter_port}",
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}"
  ]
  ports {
    internal = var.arbiter_port    
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }    
  user = var.uid
  labels { 
    label = "replsetName"
    value = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.arbiters_per_replset)}"
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
  depends_on = [docker_container.init_keyfile_container]
}

resource "docker_volume" "arb_volume_pmm" {
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-pmm-client-data"
  count = var.arbiters_per_replset
}

resource "docker_container" "pmm_arb" {
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}-${var.pmm_client_container_suffix}"
  image = var.pmm_client_image 
  count = var.arbiters_per_replset
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.arb_volume_pmm[count.index].name
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