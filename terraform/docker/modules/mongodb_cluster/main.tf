terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
    minio = {
      source = "aminueza/minio"
    }    
  }
}

resource "docker_image" "psmdb_image" {
  name         = var.psmdb_image
  keep_locally = !var.force_pull_latest
}

resource "docker_image" "pmm_client_image" {
  name         = var.pmm_client_image
  keep_locally = !var.force_pull_latest
}