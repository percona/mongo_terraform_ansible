data "docker_registry_image" "pmm_client" {
  name = var.pmm_client_image
}

resource "docker_image" "pmm_client" {
  name         = var.pmm_client_image
  pull_triggers = [data.docker_registry_image.pmm_client.sha256_digest]
  keep_locally = true
}
