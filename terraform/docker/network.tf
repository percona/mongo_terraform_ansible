resource "docker_network" "mongo_network" {
  name = "${var.network_name}"
}