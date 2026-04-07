resource "docker_volume" "cfg_volume" {
  name  = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-data"
  count = var.configsvr_count
}

resource "docker_container" "cfg" {
  name       = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  hostname   = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  domainname = var.domain_name
  image      = docker_image.psmdb.image_id
  mounts {
    source    = docker_volume.keyfile_volume.name
    target    = var.keyfile_path
    type      = "volume"
    read_only = true
  }
  count = var.configsvr_count
  command = concat([
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
    ],
    var.enable_audit ? [
      "--auditDestination", "file",
      "--auditFormat", "JSON",
      "--auditPath", "/var/log/mongodb-audit.json",
      "--auditFilter", "${var.audit_filter}",
      "--setParameter", "auditAuthorizationSuccess=true"
    ] : [],
    var.enable_ldap ? [
      "--setParameter", "authenticationMechanisms=PLAIN,SCRAM-SHA-256",
      "--ldapQueryUser", "${var.ldap_bind_dn}",
      "--ldapQueryPassword", "${var.ldap_bind_pw}",
      "--ldapUserToDNMapping", "[{\"match\": \"(.+)\", \"ldapQuery\": \"${var.ldap_user_search_base}??sub?(uid={0})\"}]",
      "--ldapServers", "${var.ldap_servers}",
      "--ldapTransportSecurity", "none"
    ] : []
  )
  ports {
    internal = var.configsvr_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
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
    type   = "volume"
    target = "/data/db"
    source = docker_volume.cfg_volume[count.index].name
  }
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  healthcheck {
    test         = ["CMD-SHELL", "mongosh --port ${var.configsvr_port} --eval 'db.runCommand({ ping: 1 })'"]
    interval     = "10s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }
  wait       = true
  restart    = "no"
  depends_on = [null_resource.init_keyfile]

  lifecycle {
    replace_triggered_by = [docker_image.psmdb]
  }
}
