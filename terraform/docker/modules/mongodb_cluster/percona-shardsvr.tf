resource "docker_volume" "shard_volume" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
}

resource "docker_container" "shard" {
  count = var.shard_count * var.shardsvr_replicas
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  hostname  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  domainname = var.domain_name
  image = docker_image.psmdb.image_id 
  mounts {
    source = docker_volume.keyfile_volume.name
    target = "${var.keyfile_path}"
    type   = "volume"
    read_only = true
  }  
  command = concat([
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
    internal = var.shardsvr_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0" 
  }  
  labels { 
    label = "replsetName"
    value = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}"
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
  depends_on = [docker_container.init_keyfile]
}