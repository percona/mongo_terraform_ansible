resource "docker_network" "mongo_network" {
  name = "${var.env_tag}-${var.network_name}"
}