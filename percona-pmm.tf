resource "google_compute_disk" "pmm_disk" {
  name  = "${var.env_tag}-percona-pmm-data"
  type  = var.data_disk_type
  size  = var.pmm_volume_size
  zone  = data.google_compute_zones.available.names[0]
}

resource "google_compute_instance" "pmm" {
  name = "${var.env_tag}-percona-pmm"
  machine_type = var.pmm_type
  zone  = data.google_compute_zones.available.names[0]
  tags = ["percona-pmm"]
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
    }
  }   
  attached_disk {
    source = google_compute_disk.pmm_disk.name
  }     
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
  }

  metadata_startup_script = <<EOT
    #! /bin/bash

    mkdir -p /var/lib/containers/storage
    mkfs.xfs -L pmm /dev/sdb 
    echo "$(blkid /dev/sdb | awk ' { print $3 }' | tr -d '"') /var/lib/containers/storage xfs defaults,noatime,discard 1 1" | tee -a /etc/fstab
    mount /var/lib/containers/storage
   
    tee -a /etc/sysctl.conf <<-EOF
    vm.swappiness=1
    vm.dirty_ratio=15
    vm.dirty_background_ratio=5
    kernel.panic=10
    net.core.somaxconn=65535
    net.ipv4.tcp_max_syn_backlog=4096
    net.ipv4.conf.all.secure_redirects=0
    net.ipv4.conf.default.secure_redirects=0
    net.ipv4.ip_local_port_range=10001    65535
    net.ipv4.neigh.default.gc_thresh1=0
    net.ipv4.tcp_slow_start_after_idle=0
    net.ipv6.conf.all.accept_ra=0
    net.ipv6.conf.all.accept_redirects=0
    net.ipv6.conf.all.disable_ipv6=1
    net.ipv6.conf.default.accept_ra=0
    net.ipv6.conf.default.accept_redirects=0
    net.ipv6.conf.default.disable_ipv6=1
EOF
    sysctl -p

    setenforce 0

    yum -y install docker
    docker pull percona/pmm-server:2

    docker create \
    -v /srv/ \
    --name pmm-data \
    percona/pmm-server:2 /bin/true    

    docker run --detach --restart always \
    --publish 443:443 \
    --volumes-from pmm-data --name pmm-server \
    percona/pmm-server:2
EOT
}
resource "google_compute_firewall" "percona-pmm-firewall" {
  name = "percona-pmm-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  target_tags = ["percona-pmm"]
  allow {
    protocol = "tcp"
    ports = ["22", "443"]
 }
}
