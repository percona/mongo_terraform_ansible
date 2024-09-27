resource "aws_ebs_volume" "pmm_disk" {
  availability_zone = aws_subnet.vpc-subnet[0].availability_zone
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
    hostnamectl set-hostname "${var.env_tag}-${var.pmm_tag}"
    
    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
  EOT
  monitoring = true
}

resource "aws_volume_attachment" "pmm_volume_attachment" {
  device_name  = "/dev/sdf"
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
  tags = {
    Name = "${var.env_tag}-${var.pmm_tag}-sg"
    environment    = var.env_tag
  }
}
