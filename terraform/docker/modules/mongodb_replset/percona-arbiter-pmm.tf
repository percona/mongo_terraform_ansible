resource "docker_container" "pmm_arb" {
  name  = "${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset}-${var.pmm_client_container_suffix}"
  image = docker_image.pmm_client.image_id  
  count = var.enable_pmm ? var.arbiters_per_replset : 0
  env = [ "PMM_AGENT_SETUP=1", "PMM_AGENT_SETUP_FORCE=1", "PMM_AGENT_SETUP_NODE_NAME=${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset}", "PMM_AGENT_SETUP_NODE_TYPE=container", "PMM_AGENT_SERVER_ADDRESS=${var.pmm_host}:${var.pmm_port}", "PMM_AGENT_SERVER_USERNAME=${var.pmm_server_user}", "PMM_AGENT_SERVER_PASSWORD=${var.pmm_server_pwd}", "PMM_AGENT_SERVER_INSECURE_TLS=1", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml", "PMM_AGENT_PRERUN_SCRIPT=pmm-admin status --wait=10s; pmm-admin add mongodb --environment=${var.env_tag} --cluster=${var.rs_name} --host=${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset} --port=${var.arbiter_port + var.data_nodes_per_replset + count.index} --service-name=${var.rs_name}-${var.arbiter_tag}${count.index % var.arbiters_per_replset}-mongodb --skip-connection-check --tls-skip-verify" ]
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
