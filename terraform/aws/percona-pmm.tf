resource "aws_ebs_volume" "pmm_disk" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = var.pmm_volume_size
  type              = var.pmm_disk_type
  tags = {
    Name = "${var.env_tag}-${var.pmm_tag}-data"
    environment    = var.env_tag
  }
}

resource "aws_instance" "pmm" {
  ami                         = lookup(var.image, var.region)
  instance_type               = var.pmm_type
  availability_zone           = data.aws_availability_zones.available.names[0]
  key_name                    = "${var.my_ssh_user}_key"
  #subnet_id                   = aws_subnet.vpc-subnet.id
  tags = {
    Name = "${var.env_tag}-${var.pmm_tag}"
    environment    = var.env_tag
  }
  ebs_block_device {
    device_name = "/dev/sdh"
    volume_id   = aws_ebs_volume.pmm_disk.id
  }
  vpc_security_group_ids = [aws_security_group.pmm_security_group.id]
  user_data = <<-EOT
    #! /bin/bash
    echo "Created"
  EOT
  monitoring = true
}

resource "aws_security_group" "pmm_security_group" {
  name   = "${var.env_tag}-${var.pmm_tag}-security-group"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.pmm_ports
    content {
      from_port   = 0
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.pmm_tag}-firewall"
    environment    = var.env_tag
  }
}