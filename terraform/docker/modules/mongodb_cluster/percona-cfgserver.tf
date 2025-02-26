resource "docker_volume" "cfg_volume" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-data"
  count = var.configsvr_count
}

resource "docker_container" "cfg" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  image = var.psmdb_image 
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  count = var.configsvr_count
  command = [
    "mongod",
    "--replSet", "${var.cluster_name}-${var.configsvr_tag}",  
    "--bind_ip_all",    
    "--configsvr",
    "--port", "${var.configsvr_port}",
    "--dbpath", "/data/db",
    "--oplogSize", "200",
    "--wiredTigerCacheSizeGB", "0.25",    
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}",
    "--profile", "2",
    "--slowms", "200",
    "--rateLimit", "100"
  ]  
  ports {
    internal = var.configsvr_port
  }  
  user = var.uid
  labels { 
    label = "replsetName"
    value = "${var.cluster_name}-${var.configsvr_tag}"
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
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.configsvr_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }
  wait = true
  restart = "no"
  depends_on = [docker_container.init_keyfile_container]
}

resource "docker_container" "pbm_cfg" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-${var.pbm_container_suffix}"
  image = var.custom_image 
  count = var.configsvr_count
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.cfg[count.index].name}:${var.configsvr_port}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.cfg_volume[count.index].name
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

resource "docker_volume" "cfg_volume_pmm" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-pmm-client-data"
  count = var.configsvr_count
}

resource "docker_container" "pmm_cfg" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-${var.pmm_client_container_suffix}"
  image = var.pmm_client_image 
  count = var.configsvr_count
  env = [ "PMM_AGENT_SERVER_ADDRESS=${var.pmm_host}:${var.pmm_port}", "PMM_AGENT_SERVER_USERNAME=${var.pmm_user}", "PMM_AGENT_SERVER_PASSWORD=${var.pmm_password}", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.cfg_volume_pmm[count.index].name
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
