resource "aws_ebs_volume" "shard_disk" {
  count             = var.shard_count * var.shardsvr_replicas
#  availability_zone = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone           = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].availability_zone
  size              = var.shardsvr_volume_size
  type              = var.data_disk_type
  tags = {
    Name = "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
    environment    = var.env_tag
  }
}

resource "aws_instance" "shard" {
  count               = var.shard_count * var.shardsvr_replicas
  ami                 = lookup(var.image, var.region)
  instance_type       = var.shardsvr_type
  #availability_zone   = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone           = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].availability_zone
  key_name            = aws_key_pair.my_key_pair.key_name
  subnet_id           = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].id
  tags = {
    Name = "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
    ansible-group = floor(count.index / var.shardsvr_replicas )
    ansible-index = count.index % var.shardsvr_replicas
    environment = var.env_tag
  }  
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
  EOT
  vpc_security_group_ids = [aws_security_group.mongodb_shardsvr_sg.id]
}

resource "aws_volume_attachment" "shard_volume_attachment" {
  count        = var.shard_count * var.shardsvr_replicas
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.shard_disk[count.index].id
  instance_id  = aws_instance.shard[count.index].id
}

resource "aws_security_group" "mongodb_shardsvr_sg" {
  name   = "${var.env_tag}-${var.shard_tag}-sg"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.shard_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.shard_tag}-sg"
    environment    = var.env_tag

  }
}