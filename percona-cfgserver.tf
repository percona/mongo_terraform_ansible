resource "google_compute_disk" "cfg_disk" {
  name  = "${var.env_tag}-mongo-cfg0${count.index}-data"
  type  = var.data_disk_type
  size  = var.configsvr_volume_size
  zone  = data.google_compute_zones.available.names[count.index % 3]
  count = var.configsvr_count
}

resource "google_compute_instance" "cfg" {
  name = "${var.env_tag}-mongo-cfg0${count.index}"
  machine_type = var.configsvr_type
  zone  = data.google_compute_zones.available.names[count.index % 3]
  count = var.configsvr_count
  tags = ["mongodb-cfg"]
  labels = { 
    ansible-group = "cfg",
    environment = var.env_tag
  }  
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
    }
  }
  attached_disk {
    source = element(google_compute_disk.cfg_disk.*.self_link, count.index)
  }   
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    access_config {}
  }
  metadata = {
    ssh-keys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }
  metadata_startup_script = <<EOT
    #! /bin/bash

    mkdir /data
    mkfs.xfs -L mongodb /dev/sdb 
    echo "$(blkid /dev/sdb | awk ' { print $3 }' | tr -d '"') /data xfs defaults,noatime,discard 1 1" | tee -a /etc/fstab
    mount /data

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
    semanage fcontext -a -t mongod_var_lib_t "/data(/.*)?"
    restorecon -R -v /data/

EOT
}

resource "google_compute_firewall" "mongodb-cfgsvr-firewall" {
  name = "mongodb-cfgsvr-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["mongodb-cfg"]
  allow {
    protocol = "tcp"
    ports = ["22", "27019"]
 }
}

