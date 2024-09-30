resource "google_compute_disk" "pmm_disk" {
  name  = "${var.env_tag}-${var.pmm_tag}-data"
  type  = var.pmm_disk_type
  size  = var.pmm_volume_size
  zone  = data.google_compute_zones.available.names[0]
}

resource "google_compute_instance" "pmm" {
  name = "${var.env_tag}-${var.pmm_tag}"
  machine_type = var.pmm_type
  zone  = data.google_compute_zones.available.names[0]
  tags = ["${var.env_tag}-${var.pmm_tag}"]
  boot_disk {
    initialize_params {
    image = lookup(var.image, var.region)
    }
  }   
  attached_disk {
    source = google_compute_disk.pmm_disk.name
  }     
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    access_config {}
  }
  metadata = {
    ssh-keys = join("\n", [for user, key_path in var.gce_ssh_users : "${user}:${file(key_path)}"])
  }
  scheduling {
    preemptible = false
    automatic_restart = true 
    provisioning_model = "STANDARD"
  }
  metadata_startup_script = <<EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.pmm_tag}.${var.env_tag}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts  

    # Add a dash to lsblk output to match the Terraform volume ID 
    DEVICE=$(lsblk -o NAME,SERIAL | sed 's/l/l-/' | grep "${google_compute_disk.pmm_disk.id}" | awk '{print "/dev/" $1}')

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/docker

    mount $DEVICE /var/lib/docker

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$UUID /var/lib/docker xfs defaults,noatime,nofail 0 2" >> /etc/fstab    
  EOT
}

resource "google_compute_firewall" "percona-pmm-firewall" {
  name = "${var.env_tag}-${var.pmm_tag}-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-${var.pmm_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.pmm_ports}"
  }
}
