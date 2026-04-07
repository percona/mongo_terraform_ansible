# Create Docker containers for MongoDB mongos
resource "docker_container" "mongos" {
  count      = var.mongos_count
  name       = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
  hostname   = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
  domainname = var.domain_name
  image      = docker_image.psmdb.image_id
  command = concat([
    "mongos",
    "--configdb", "${lookup({ for label in docker_container.cfg[0].labels : label.label => label.value }, "replsetName", null)}/${join(",", [for i in range(var.configsvr_count) : "${docker_container.cfg[i].name}:${var.configsvr_port}"])}",
    "--bind_ip_all",
    "--port", "${var.mongos_port}",
    "--keyFile", "${var.keyfile_path}/${var.keyfile_name}",
    "--slowms", "200",
    "--rateLimit", "100",
    "--setParameter", "diagnosticDataCollectionDirectoryPath=/var/log/mongo/mongos.diagnostic.data/"
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
    internal = var.mongos_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }
  user = var.uid
  mounts {
    source    = docker_volume.keyfile_volume.name
    target    = var.keyfile_path
    type      = "volume"
    read_only = true
  }
  labels {
    label = "environment"
    value = var.env_tag
  }
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  healthcheck {
    test         = ["CMD-SHELL", "mongosh --port ${var.mongos_port} --eval 'db.runCommand({ ping: 1 })'"]
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
