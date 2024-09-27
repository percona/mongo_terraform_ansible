resource "aws_ebs_volume" "pmm_disk" {
  availability_zone = aws_subnet.vpc-subnet[0].availability_zone
  size              = var.pmm_volume_size
  type              = var.pmm_disk_type
  tags = {
    Name = "${var.env_tag}-${var.pmm_tag}-data"
    environment    = var.env_tag
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
    Name = "${var.env_tag}-${var.pmm_tag}"
    environment    = var.env_tag
  }  
  vpc_security_group_ids = [aws_security_group.pmm_security_group.id]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.pmm_tag}.${var.env_tag}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts  

    # Remove the dash from the Terraform volume ID to match with lsblk output
    DEVICE=$(lsblk -o NAME,SERIAL | grep "${aws_ebs_volume.pmm_disk.id}" | awk '{print "/dev/" $1}')

    # Create an XFS filesystem on the EBS volume
    mkfs.xfs $DEVICE

    # Create the directory for MongoDB data
    mkdir -p /var/lib/docker

    # Mount the volume
    mount $DEVICE /var/lib/docker

    # Add the volume to /etc/fstab for automatic mounting at boot
    echo "$DEVICE /var/lib/docker xfs defaults,nofail 0 2" >> /etc/fstab    
  EOT
  monitoring = true
}

resource "aws_volume_attachment" "pmm_volume_attachment" {
  device_name  = "/dev/sdf" # Placeholder, not used for NVMe but required by Terraform
  volume_id    = aws_ebs_volume.pmm_disk.id
  instance_id  = aws_instance.pmm.id
}

resource "aws_security_group" "pmm_security_group" {
  name   = "${var.env_tag}-${var.pmm_tag}-sg"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.pmm_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  
    }
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }  
  tags = {
    Name = "${var.env_tag}-${var.pmm_tag}-sg"
    environment    = var.env_tag
  }
}

resource "aws_route53_record" "pmm_dns_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "${var.env_tag}-${var.pmm_tag}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.pmm.private_ip]
}