resource "docker_volume" "rs_volume_pmm" {
  count = var.enable_pmm ? var.data_nodes_per_replset : 0
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-pmm-client-data"
}

resource "docker_container" "pmm_rs" {
  name  = "${var.rs_name}-${var.replset_tag}${count.index % var.data_nodes_per_replset}-${var.pmm_client_container_suffix}"
  image = docker_image.pmm_client.image_id  
  count = var.enable_pmm ? var.data_nodes_per_replset : 0
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.rs_volume_pmm[count.index].name
  }
  network_mode = "bridge"
  networks_advanced {
    name = "${var.network_name}"
  }
  healthcheck {
    test        = ["CMD-SHELL", "pmm-admin status"]
    interval    = "10s"
    timeout     = "10s"
    retries     = 5
    start_period = "30s"
  }   
  wait = false  
  restart = "on-failure"
}
