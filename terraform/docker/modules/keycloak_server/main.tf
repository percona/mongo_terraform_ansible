terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.6.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
