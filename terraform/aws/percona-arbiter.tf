resource "aws_instance" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  tags = {
    Name           = "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
    ansible-group  = floor(count.index / var.arbiters_per_replset)
    ansible-index  = count.index % var.arbiters_per_replset
    environment    = var.env_tag
  }
  instance_type    = var.arbiter_type
#  availability_zone = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].availability_zone
  ami               = lookup(var.image, var.region)
  subnet_id         = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].id
  associate_public_ip_address = true
  key_name          = aws_key_pair.my_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.mongodb-arbiter-sg.id]
  user_data = <<EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
EOT
}

resource "aws_security_group" "mongodb-arbiter-sg" {
  name        = "${var.env_tag}-${var.arbiter_tag}-sg"
  description = "Allow traffic to MongoDB arbiter instances"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.arbiter_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.arbiter_tag}-sg"
    environment    = var.env_tag
  }
}