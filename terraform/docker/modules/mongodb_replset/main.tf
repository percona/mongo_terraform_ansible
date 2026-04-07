terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.6.2"
    }
    null = {
      source = "hashicorp/null"
    }
    minio = {
      source = "aminueza/minio"
    }
  }
}
