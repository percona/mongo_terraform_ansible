resource "aws_ebs_volume" "pmm_disk" {
  availability_zone = aws_subnet.vpc-subnet[0].availability_zone
  size              = var.pmm_volume_size
  type              = var.pmm_disk_type
  tags = {
    Name = "${local.pmm_host}-data"
  }
}

locals {
  pmm_volume_id_without_dashes = replace(aws_ebs_volume.pmm_disk.id, "-", "")
}

resource "aws_instance" "pmm" {
  ami                         = lookup(var.image, var.region)
  instance_type               = var.pmm_type
  availability_zone           = aws_subnet.vpc-subnet[0].availability_zone
  key_name                    = aws_key_pair.my_key_pair.key_name
  subnet_id                   = aws_subnet.vpc-subnet[0].id
  tags = {
    Name = "${local.pmm_host}"
  }  
  vpc_security_group_ids = [ aws_security_group.mongodb_pmm_sg.id ]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${local.pmm_host}.${aws_route53_zone.private_zone.name}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" > /etc/hosts  

    DEVICE="/dev/nvme1n1"
    while [ ! -b "$DEVICE" ]; do
      echo "Waiting for $DEVICE to be attached..."
      sleep 2
    done
    
    # Add a dash to lsblk output to match the Terraform volume ID 
    DEVICE=$(lsblk -o NAME,SERIAL | sed 's/l/l-/' | grep "${aws_ebs_volume.pmm_disk.id}" | awk '{print "/dev/" $1}')

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/docker

    mount $DEVICE /var/lib/docker

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$UUID /var/lib/docker xfs defaults,noatime,nofail 0 2" >> /etc/fstab    
  EOT
  monitoring = true
}

resource "aws_volume_attachment" "pmm_volume_attachment" {
  device_name  = "/dev/sdf" # Placeholder, not used for NVMe but required by Terraform
  volume_id    = aws_ebs_volume.pmm_disk.id
  instance_id  = aws_instance.pmm.id
}

# Network
resource "aws_security_group" "mongodb_pmm_sg" {
  name        = "${local.pmm_host}-sg"
  description = "Allow traffic to MongoDB pmm instances"
  vpc_id      = aws_vpc.vpc-network.id

  tags = {
    Name        = "${local.pmm_host}-sg"
  }
}

resource "aws_security_group_rule" "mongodb-pmm-ingress" {
  type              = "ingress"
  from_port         = var.pmm_port
  to_port           = var.pmm_port
  protocol          = "tcp"
  security_group_id = aws_security_group.mongodb_pmm_sg.id
  cidr_blocks       = [var.subnet_cidr]
}

# Ingress rule (SSH from anywhere)
resource "aws_security_group_rule" "mongodb-pmm-ssh_inbound" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mongodb_pmm_sg.id
  description       = "SSH from anywhere"
}

# Ingress rule for ICMP (ping) traffic
resource "aws_security_group_rule" "mongodb-pmm-icmp-ingress" {
  type              = "ingress"
  from_port         = 8     # Type 8 for echo request (ping)
  to_port           = 0
  protocol          = "icmp"
  security_group_id = aws_security_group.mongodb_pmm_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Egress rule allowing all traffic
resource "aws_security_group_rule" "mongodb-pmm-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.mongodb_pmm_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow all outbound IPv4 traffic
  ipv6_cidr_blocks  = ["::/0"]       # Allow all outbound IPv6 traffic
}

# DNS
resource "aws_route53_record" "pmm_dns_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "${local.pmm_host}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.pmm.private_ip]
}