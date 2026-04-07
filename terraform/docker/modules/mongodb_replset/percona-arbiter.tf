resource "docker_volume" "arb_volume" {
  count = var.arbiters_per_replset
  name  = "${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset}-data"
}

resource "docker_container" "arbiter" {
  count      = var.arbiters_per_replset
  name       = "${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset}${var.domain_name != "" ? ".${var.domain_name}" : ""}"
  hostname   = "${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset}"
  domainname = var.domain_name
  image      = docker_image.psmdb.image_id
  mounts {
    source    = docker_volume.keyfile_volume.id
    target    = var.keyfile_path
    type      = "volume"
    read_only = true
  }
  command = concat(
    [
      "mongod",
      "--replSet", "${var.rs_name}",
      "--bind_ip_all",
      "--port", "${var.arbiter_port + var.data_nodes_per_replset + count.index}",
      "--keyFile", "${var.keyfile_path}/${var.keyfile_name}"
    ],
    var.enable_audit ? [
      "--auditDestination", "file",
      "--auditFormat", "JSON",
      "--auditPath", "/var/log/mongodb-audit.json",
      "--auditFilter", "${var.audit_filter}",
      "--setParameter", "auditAuthorizationSuccess=true"
    ] : []
  )
  ports {
    internal = var.arbiter_port + var.data_nodes_per_replset + count.index
    external = var.arbiter_port + var.data_nodes_per_replset + count.index
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }
  user = var.uid
  labels {
    label = "replsetName"
    value = var.rs_name
  }
  labels {
    label = "environment"
    value = var.env_tag
  }
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  mounts {
    type   = "volume"
    target = "/data/db"
    source = docker_volume.arb_volume[count.index].name
  }
  healthcheck {
    test         = ["CMD-SHELL", "mongosh --port ${var.arbiter_port + var.data_nodes_per_replset + count.index} --eval 'db.runCommand({ ping: 1 })'"]
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
