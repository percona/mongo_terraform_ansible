resource "docker_image" "pcsm" {
  count        = var.enable_pcsm ? 1 : 0
  name         = var.pcsm_image
  keep_locally = true
}

resource "docker_container" "pcsm" {
  count = var.enable_pcsm ? 1 : 0

  name     = "${local.name_prefix}pcsm"
  hostname = "${local.name_prefix}pcsm"
  image    = docker_image.pcsm[0].image_id
  # The generated URI file is deliberately 0600 on the host. Running as root
  # avoids weakening those permissions for the image's unprivileged UID.
  user       = "0:0"
  entrypoint = ["/bin/sh", "-c"]
  command = [
    "set -a; . /run/secrets/pcsm.env; set +a; : \"$${PCSM_SOURCE_URI:?PCSM_SOURCE_URI is required}\"; : \"$${PCSM_TARGET_URI:?PCSM_TARGET_URI is required}\"; exec /pcsm-entry.sh pcsm"
  ]

  cpus   = tostring(var.pcsm_cpus)
  memory = var.pcsm_memory_mb

  # Selectors are nonsecret operational metadata; URIs stay only in pcsm_env_file.
  labels {
    label = "pcsm.source_kind"
    value = var.pcsm_source_kind
  }

  labels {
    label = "pcsm.source_name"
    value = var.pcsm_source_name
  }

  labels {
    label = "pcsm.target_kind"
    value = var.pcsm_target_kind
  }

  labels {
    label = "pcsm.target_name"
    value = var.pcsm_target_name
  }

  network_mode = "bridge"
  networks_advanced {
    name = docker_network.mongo_network.name
  }

  mounts {
    type      = "bind"
    source    = abspath(var.pcsm_env_file)
    target    = "/run/secrets/pcsm.env"
    read_only = true
  }

  healthcheck {
    test         = ["CMD-SHELL", "set -a; . /run/secrets/pcsm.env; set +a; pcsm status >/dev/null"]
    interval     = "10s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  # The UI creates least-privilege users after the MongoDB modules complete,
  # then restarts PCSM. Do not block the initial apply on PCSM connectivity.
  wait    = false
  restart = "unless-stopped"

  depends_on = [
    module.mongodb_clusters,
    module.mongodb_replsets,
  ]

  lifecycle {
    precondition {
      condition     = trimspace(var.pcsm_env_file) != "" && fileexists(var.pcsm_env_file)
      error_message = "pcsm_env_file must identify an existing host file when enable_pcsm is true."
    }

    precondition {
      condition     = var.pcsm_source_kind == var.pcsm_target_kind
      error_message = "PCSM requires cluster-to-cluster or replset-to-replset replication."
    }

    precondition {
      condition     = trimspace(var.pcsm_source_name) != "" && trimspace(var.pcsm_target_name) != "" && trimspace(var.pcsm_source_name) != trimspace(var.pcsm_target_name)
      error_message = "pcsm_source_name and pcsm_target_name must be different non-empty topology names."
    }

    precondition {
      condition     = var.pcsm_source_kind == "cluster" ? contains(keys(var.clusters), trimspace(var.pcsm_source_name)) : contains(keys(var.replsets), trimspace(var.pcsm_source_name))
      error_message = "pcsm_source_name must identify a configured topology of pcsm_source_kind."
    }

    precondition {
      condition     = var.pcsm_target_kind == "cluster" ? contains(keys(var.clusters), trimspace(var.pcsm_target_name)) : contains(keys(var.replsets), trimspace(var.pcsm_target_name))
      error_message = "pcsm_target_name must identify a configured topology of pcsm_target_kind."
    }
  }
}
