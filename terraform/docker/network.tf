resource "docker_network" "mongo_network" {
  name = "${local.name_prefix}${var.network_name}"
}