resource "aws_ebs_volume" "cfg_disk" {
  count              = var.configsvr_count
  #availability_zone  = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone   = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].availability_zone
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
  instance_type       = var.configsvr_type
  #availability_zone   = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone   = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].availability_zone
  key_name            = aws_key_pair.my_key_pair.key_name
  subnet_id           = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].id
    tags = {
    Name = "${var.env_tag}-${var.configsvr_tag}0${count.index}"
    ansible-group  = "cfg"
    environment    = var.env_tag
  }
  vpc_security_group_ids = [aws_security_group.mongodb_cfgsvr_sg.id]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.configsvr_tag}0${count.index}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
  EOT
}

resource "aws_volume_attachment" "cfg_volume_attachment" {
  count        = var.configsvr_count
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.cfg_disk[count.index].id
  instance_id  = aws_instance.cfg[count.index].id
}

resource "aws_security_group" "mongodb_cfgsvr_sg" {
  name   = "${var.env_tag}-${var.configsvr_tag}-sg"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.configsvr_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.configsvr_tag}-sg"
    environment    = var.env_tag
  }
}