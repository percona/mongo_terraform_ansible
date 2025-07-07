resource "docker_volume" "rs_volume" {
  count = var.data_nodes_per_replset
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-data"
}

resource "docker_container" "rs" {
  count = var.data_nodes_per_replset
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}${var.domain_name != "" ? ".${var.domain_name}" : ""}"
  hostname = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}"
  domainname = var.domain_name
  image = docker_image.psmdb.image_id 
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  command = concat(
  [
    "mongod",
    "--replSet", "${var.rs_name}",  
    "--bind_ip_all",    
    "--port", "${var.replset_port + count.index}",
    "--oplogSize", "200",
    "--wiredTigerCacheSizeGB", "0.25",      
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}",
    "--profile", "2",
    "--slowms", "200",
    "--rateLimit", "100"
  ],
  var.enable_ldap ? [
    "--setParameter", "authenticationMechanisms=PLAIN,SCRAM-SHA-256",
    "--ldapQueryUser","${var.ldap_bind_dn}",
    "--ldapQueryPassword","${var.ldap_bind_pw}",
    "--ldapUserToDNMapping","[{\"match\": \"(.+)\", \"ldapQuery\": \"${var.ldap_user_search_base}??sub?(uid={0})\"}]",
    "--ldapServers","${var.ldap_servers}",
    "--ldapTransportSecurity","none"
  ] : []
  )
  user = var.uid
  ports {
    internal = var.replset_port + count.index
    external = var.replset_port + count.index
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }  
  labels { 
    label = "replsetName"
    value = "${var.rs_name}"
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
    source = docker_volume.rs_volume[count.index].name
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.replset_port + count.index} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }
  wait = true
  restart = "no"
  depends_on = [docker_container.init_keyfile]
}

resource "docker_container" "pbm_rs" {
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-${var.pbm_container_suffix}"
  count = var.data_nodes_per_replset
  image = docker_image.pbm_mongod.image_id
  user  = var.uid
  command = [
    "pbm-agent"
  ]  
  env = [ "PBM_MONGODB_URI=${var.mongodb_pbm_user}:${var.mongodb_pbm_password}@${docker_container.rs[count.index].name}:${var.replset_port + count.index}" ]
  mounts {
    type = "volume"
    target = "/data/db"
    source = docker_volume.rs_volume[count.index].name
  }
  network_mode = "bridge"
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
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-pmm-client-data"
}

resource "docker_container" "pmm_rs" {
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-${var.pmm_client_container_suffix}"
  image = docker_image.pmm_client.image_id  
  count = var.data_nodes_per_replset
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.rs_volume_pmm[count.index].name
  }
  network_mode = "bridge"
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
