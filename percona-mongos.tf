resource "google_compute_instance" "mongos" {
  name = "${var.env_tag}-mongo-router0${count.index}"
  machine_type = var.mongos_type
  zone  = data.google_compute_zones.available.names[count.index % 3]
  count = var.mongos_count
  tags = ["mongodb-mongos"]
  labels = { 
    ansible-group = "mongos",
    environment = var.env_tag
  }
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
    }
  }   
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
  }
 metadata_startup_script = <<EOT
    #! /bin/bash

    tee -a  /etc/sysctl.conf <<-EOF
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

    tee /etc/systemd/system/disable-transparent-huge-pages.service <<-EOF
    [Unit]
    Description=Disable Transparent Huge Pages (THP)
    DefaultDependencies=no
    After=sysinit.target local-fs.target
    Before=mongod.service

    [Service]
    Type=oneshot
    ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null'

    [Install]
    WantedBy=basic.target
EOF

    systemctl daemon-reload
    systemctl start disable-transparent-huge-pages
    systemctl enable disable-transparent-huge-pages

    mkdir /etc/tuned/virtual-guest-no-thp

    tee /etc/tuned/virtual-guest-no-thp/tuned.conf <<-EOF
    [main]
    include=virtual-guest

    [vm]
    transparent_hugepages=never
EOF

    tuned-adm profile virtual-guest-no-thp

    tee -a /etc/security/limits.d/20-nproc.conf <<-EOF
    *        hard   nofile    64000
    *        soft    nofile    64000
EOF

    tee -a /etc/pam.d/login <<-EOF
    session    required    pam_limits.so
EOF

EOT
}

resource "google_compute_firewall" "mongodb-mongos-firewall" {
  name = "mongodb-mongos-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  target_tags = ["mongodb-mongos"]
  allow {
    protocol = "tcp"
    ports = ["22", "27017"]
 }
}
