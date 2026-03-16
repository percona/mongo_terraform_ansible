terraform {
  required_version = ">= 1.0"
  required_providers {
    chaos = {
      source  = "percona/chaos"
      version = "~> 1.0"
    }
  }
}
