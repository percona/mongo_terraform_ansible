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
  ] : [],
  var.enable_oidc ? [
    "--setParameter", "authenticationMechanisms=MONGODB-OIDC,SCRAM-SHA-256",
    "--setParameter", "oidcIdentityProviders=[{\"issuer\":\"${var.oidc_issuer}\",\"audience\":\"${var.oidc_audience}\",\"clientId\":\"${var.oidc_client_id}\",\"authNamePrefix\":\"${var.oidc_auth_name_prefix}\",\"supportsHumanFlows\":true,\"principalName\":\"${var.oidc_principal_name}\",\"authorizationClaim\":\"${var.oidc_authorization_claim}\"}]"
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
  env = var.enable_oidc && var.pki_certs_volume_name != "" ? ["NODE_EXTRA_CA_CERTS=/etc/ssl/certs/keycloak-ca.crt"] : []
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

resource "null_resource" "mongos_copy_oidc_cert" {
  count      = var.enable_oidc && var.pki_certs_volume_name != "" ? 1 : 0
  depends_on = [docker_container.mongos]

  triggers = {
    container_ids = join(",", docker_container.mongos[*].id)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      docker run --rm -v ${var.pki_certs_volume_name}:/certs alpine:3.21 cat /certs/ca.crt > /tmp/keycloak-ca-${var.cluster_name}-mongos.crt
      chmod 600 /tmp/keycloak-ca-${var.cluster_name}-mongos.crt
      %{for name in docker_container.mongos[*].name~}
      docker cp /tmp/keycloak-ca-${var.cluster_name}-mongos.crt ${name}:/etc/ssl/certs/keycloak-ca.crt
      docker exec --user root ${name} update-ca-trust
      %{endfor~}
      rm -f /tmp/keycloak-ca-${var.cluster_name}-mongos.crt
    EOT
  }
}