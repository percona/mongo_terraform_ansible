resource "docker_volume" "rs_volume" {
  count = var.data_nodes_per_replset
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}svr${count.index % var.data_nodes_per_replset}-data"
}

resource "docker_container" "rs" {
  count = var.data_nodes_per_replset
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}svr${count.index % var.data_nodes_per_replset}"
  image = var.psmdb_image
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  command = [
    "mongod",
    "--replSet", "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}",  
    "--bind_ip_all",    
    "--port", "${var.replset_port}",
    "--oplogSize", "200",
    "--wiredTigerCacheSizeGB", "0.25",      
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}",
    "--profile", "2",
    "--slowms", "200",
    "--rateLimit", "100"
  ]  
  user = var.uid
  ports {
    internal = var.replset_port
  }  
  labels { 
    label = "replsetName"
    value = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}"
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
    source = docker_volume.rs_volume[count.index].name
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.replset_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }
  wait = true
  restart = "no"
  depends_on = [docker_container.init_keyfile_container]
}

resource "docker_container" "pbm_rs" {
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}svr${count.index % var.data_nodes_per_replset}-${var.pbm_container_suffix}"
  count = var.data_nodes_per_replset
  image = var.custom_image 
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.rs[count.index].name}:${var.replset_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.rs_volume[count.index].name
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

resource "docker_volume" "rs_volume_pmm" {
  count = var.data_nodes_per_replset
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}svr${count.index % var.data_nodes_per_replset}-pmm-client-data"
}

resource "docker_container" "pmm_rs" {
  name  = "${var.rs_name}-${var.replset_tag}0${floor(count.index / var.data_nodes_per_replset)}svr${count.index % var.data_nodes_per_replset}-${var.pmm_client_container_suffix}"
  image = var.pmm_client_image 
  count = var.data_nodes_per_replset
  env = [ "PMM_AGENT_SERVER_ADDRESS=${var.pmm_host}:${var.pmm_port}", "PMM_AGENT_SERVER_USERNAME=${var.pmm_user}", "PMM_AGENT_SERVER_PASSWORD=${var.pmm_password}", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.rs_volume_pmm[count.index].name
  }
  networks_advanced {
    name = "${var.network_name}"
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
