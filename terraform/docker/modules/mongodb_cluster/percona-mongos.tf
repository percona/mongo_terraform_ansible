# Create Docker containers for MongoDB mongos
resource "docker_container" "mongos" {
  count = var.mongos_count
  name = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
  hostname = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
  domainname = var.domain_name  
  image = docker_image.psmdb.image_id
  command = concat([
    "mongos",
    "--configdb", "${lookup({for label in docker_container.cfg[0].labels : label.label => label.value}, "replsetName", null)}/${join(",", [for i in range(var.configsvr_count) : "${docker_container.cfg[i].name}:${var.configsvr_port}" ])}",
    "--bind_ip_all",    
    "--port", "${var.mongos_port}",
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}",
    "--slowms", "200",
    "--rateLimit", "100",
    "--setParameter", "diagnosticDataCollectionDirectoryPath=/var/log/mongo/mongos.diagnostic.data/"        
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
  ports {
    internal = var.mongos_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"    
  }  
  user = var.uid
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  labels { 
    label = "environment"
    value = var.env_tag
  }  
  network_mode = "bridge"
  networks_advanced {
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "mongosh --port ${var.mongos_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }  
  wait = true
  restart = "no"
  depends_on = [docker_container.init_keyfile]
}

resource "docker_volume" "mongos_volume_pmm" {
  name  = "${var.cluster_name}-${var.mongos_tag}0${count.index}-pmm-client-data"
  count = var.mongos_count
}

resource "docker_container" "pmm_mongos" {
  name  = "${var.cluster_name}-${var.mongos_tag}0${count.index}-${var.pmm_client_container_suffix}"
  image = docker_image.pmm_client.image_id  
  count = var.mongos_count
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.mongos_volume_pmm[count.index].name
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