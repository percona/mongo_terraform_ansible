### The Ansible inventory file
resource "local_file" "AnsibleInventory" {
  content = templatefile("inventory.tmpl",
    {
     ansible_group_shards = google_compute_instance.shard.*.labels.ansible-group,
     ansible_group_index = google_compute_instance.shard.*.labels.ansible-index,
     hostname_shards = google_compute_instance.shard.*.name,
     ansible_group_cfg = google_compute_instance.cfg.*.labels.ansible-group,
     hostname_cfg = google_compute_instance.cfg.*.name,
     ansible_group_mongos = google_compute_instance.mongos.*.labels.ansible-group,
     hostname_mongos = google_compute_instance.mongos.*.name,
     number_of_shards = range(var.shard_count)
    }
  )
  filename = "inventory"
}