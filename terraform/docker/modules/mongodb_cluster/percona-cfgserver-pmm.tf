resource "docker_volume" "cfg_volume_pmm" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-pmm-client-data"
  count = var.enable_pmm ? var.configsvr_count : 0
}

resource "docker_container" "pmm_cfg" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-${var.pmm_client_container_suffix}"
  image = docker_image.pmm_client.image_id  
  count = var.enable_pmm ? var.configsvr_count : 0
  env = [ "PMM_AGENT_SETUP=0", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml" ]
  mounts {
    type = "volume"
    target = "/srv"
    source = docker_volume.cfg_volume_pmm[count.index].name
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
