# Install the Keycloak CA cert into the system trust store of every MongoDB
# container so that both mongod (OpenSSL) and mongosh (pkg-compiled Node.js)
# trust Keycloak's self-signed certificate without requiring --tlsCAFile on
# every connection string.

locals {
  oidc_ca_install_script = "test -f /etc/oidc-certs/ca.crt || { echo >&2 'ERROR: /etc/oidc-certs/ca.crt not found – check pki_certs_volume_name and cert init container'; exit 1; }; cp /etc/oidc-certs/ca.crt /etc/pki/ca-trust/source/anchors/keycloak-ca.crt && update-ca-trust"
}

resource "null_resource" "install_oidc_ca_cfg" {
  count      = var.enable_oidc && var.pki_certs_volume_name != "" ? var.configsvr_count : 0
  depends_on = [docker_container.cfg]

  triggers = {
    container_id = docker_container.cfg[count.index].id
  }

  provisioner "local-exec" {
    command = "docker exec --user root ${docker_container.cfg[count.index].name} sh -c '${local.oidc_ca_install_script}'"
  }
}

resource "null_resource" "install_oidc_ca_shard" {
  count      = var.enable_oidc && var.pki_certs_volume_name != "" ? var.shard_count * var.shardsvr_replicas : 0
  depends_on = [docker_container.shard]

  triggers = {
    container_id = docker_container.shard[count.index].id
  }

  provisioner "local-exec" {
    command = "docker exec --user root ${docker_container.shard[count.index].name} sh -c '${local.oidc_ca_install_script}'"
  }
}

resource "null_resource" "install_oidc_ca_mongos" {
  count      = var.enable_oidc && var.pki_certs_volume_name != "" ? var.mongos_count : 0
  depends_on = [docker_container.mongos]

  triggers = {
    container_id = docker_container.mongos[count.index].id
  }

  provisioner "local-exec" {
    command = "docker exec --user root ${docker_container.mongos[count.index].name} sh -c '${local.oidc_ca_install_script}'"
  }
}
