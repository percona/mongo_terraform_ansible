resource "aws_ebs_volume" "cfg_disk" {
  count              = var.configsvr_count
  availability_zone  = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  size               = var.configsvr_volume_size
  type               = var.data_disk_type
  tags = {
    Name = "${var.env_tag}-${var.configsvr_tag}0${count.index}-data"
    environment    = var.env_tag
  }
}

resource "aws_instance" "cfg" {
  count               = var.configsvr_count
  ami                 = lookup(var.image, var.region)
  instance_type      = var.configsvr_type
  availability_zone   = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  key_name            = "${var.my_ssh_user}_key"
  #subnet_id           = aws_subnet.vpc_subnet.id
    tags = {
    Name = "${var.env_tag}-${var.configsvr_tag}0${count.index}"
    ansible-group  = "cfg"
    environment    = var.env_tag
  }
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_id   = aws_ebs_volume.cfg_disk[count.index].id
  }
  vpc_security_group_ids = [aws_security_group.mongodb_cfgsvr_sg.id]
  user_data = <<-EOT
    #!/bin/bash
    echo "Created"
  EOT
}

resource "aws_security_group" "mongodb_cfgsvr_sg" {
  name   = "${var.env_tag}-${var.configsvr_tag}-sg"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.configsvr_ports
    content {
      from_port   = 0
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.configsvr_tag}-sg"
    environment    = var.env_tag
  }
}