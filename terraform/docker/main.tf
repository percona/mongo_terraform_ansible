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

provider "docker" {
    host = "unix:///Users/ivangroenewold/.docker/run/docker.sock"
}
