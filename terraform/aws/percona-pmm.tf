resource "aws_ebs_volume" "pmm_disk" {
  count             = var.enable_pmm ? 1 : 0
  availability_zone = aws_subnet.vpc-subnet[0].availability_zone
  size              = var.pmm_volume_size
  type              = var.pmm_disk_type
  tags = {
    Name = "${local.pmm_host}-data"
  }
}

locals {
  pmm_volume_id_without_dashes = var.enable_pmm ? replace(aws_ebs_volume.pmm_disk[0].id, "-", "") : ""
}

resource "aws_instance" "pmm" {
  count                       = var.enable_pmm ? 1 : 0
  ami                         = lookup(var.image, var.region)
  instance_type               = var.pmm_type
  availability_zone           = aws_subnet.vpc-subnet[0].availability_zone
  key_name                    = aws_key_pair.my_key_pair.key_name
  subnet_id                   = aws_subnet.vpc-subnet[0].id
  tags = {
    Name = "${local.pmm_host}"
  }  
  vpc_security_group_ids = [ aws_security_group.mongodb_pmm_sg[0].id ]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${local.pmm_host}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 ${local.pmm_host}.${aws_route53_zone.private_zone.name} $(hostname) localhost" > /etc/hosts  

    DEVICE="/dev/nvme1n1"
    while [ ! -b "$DEVICE" ]; do
      echo "Waiting for $DEVICE to be attached..."
      sleep 2
    done
    
    # Add a dash to lsblk output to match the Terraform volume ID 
    DEVICE=$(lsblk -o NAME,SERIAL | sed 's/l/l-/' | grep "${aws_ebs_volume.pmm_disk[0].id}" | awk '{print "/dev/" $1}')

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/docker

    mount $DEVICE /var/lib/docker

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$UUID /var/lib/docker xfs defaults,noatime,nofail 0 2" >> /etc/fstab    
  EOT
  monitoring = true
}

resource "aws_volume_attachment" "pmm_volume_attachment" {
  count        = var.enable_pmm ? 1 : 0
  device_name  = "/dev/sdf" # Placeholder, not used for NVMe but required by Terraform
  volume_id    = aws_ebs_volume.pmm_disk[0].id
  instance_id  = aws_instance.pmm[0].id
}

# Network
resource "aws_security_group" "mongodb_pmm_sg" {
  count       = var.enable_pmm ? 1 : 0
  name        = "${local.pmm_host}-sg"
  description = "Allow traffic to MongoDB pmm instances"
  vpc_id      = aws_vpc.vpc-network.id

  tags = {
    Name        = "${local.pmm_host}-sg"
  }
}

resource "aws_security_group_rule" "mongodb-pmm-ingress" {
  count             = var.enable_pmm ? 1 : 0
  type              = "ingress"
  from_port         = var.pmm_port
  to_port           = var.pmm_port
  protocol          = "tcp"
  security_group_id = aws_security_group.mongodb_pmm_sg[0].id
  cidr_blocks       = [var.subnet_cidr]
}

# Ingress rule (SSH from anywhere)
resource "aws_security_group_rule" "mongodb-pmm-ssh_inbound" {
  count             = var.enable_pmm ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mongodb_pmm_sg[0].id
  description       = "SSH from anywhere"
}

# Ingress rule for ICMP (ping) traffic
resource "aws_security_group_rule" "mongodb-pmm-icmp-ingress" {
  count             = var.enable_pmm ? 1 : 0
  type              = "ingress"
  from_port         = 8     # Type 8 for echo request (ping)
  to_port           = 0
  protocol          = "icmp"
  security_group_id = aws_security_group.mongodb_pmm_sg[0].id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Egress rule allowing all traffic
resource "aws_security_group_rule" "mongodb-pmm-egress" {
  count             = var.enable_pmm ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.mongodb_pmm_sg[0].id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow all outbound IPv4 traffic
  ipv6_cidr_blocks  = ["::/0"]       # Allow all outbound IPv6 traffic
}

# DNS
resource "aws_route53_record" "pmm_dns_record" {
  count   = var.enable_pmm ? 1 : 0
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "${local.pmm_host}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.pmm[0].private_ip]
}
