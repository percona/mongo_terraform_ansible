resource "aws_ebs_volume" "shard_disk" {
  count             = var.shard_count * var.shardsvr_replicas
  availability_zone = element(data.aws_availability_zones.available.names, floor(count.index / var.shardsvr_replicas) % length(data.aws_availability_zones.available.names))
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
  instance_type      = var.shardsvr_type
  availability_zone   = element(data.aws_availability_zones.available.names, floor(count.index / var.shardsvr_replicas) % length(data.aws_availability_zones.available.names))
  key_name            = "${var.my_ssh_user}_key"
  #subnet_id           = aws_subnet.vpc_subnet.id
  tags = {
    Name = "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
    ansible-group = floor(count.index / var.shardsvr_replicas )
    ansible-index = count.index % var.shardsvr_replicas
    environment = var.env_tag
  }
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_id   = aws_ebs_volume.shard_disk[count.index].id
  }
  user_data = <<-EOT
    #!/bin/bash
    echo "Created"
  EOT
  vpc_security_group_ids = [aws_security_group.mongodb_shardsvr_firewall.id]
}

resource "aws_security_group" "mongodb_shardsvr_firewall" {
  name   = "${var.env_tag}-${var.shard_tag}-firewall"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.shard_ports
    content {
      from_port   = 0
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.shard_tag}-firewall"
    environment    = var.env_tag
  }
}