resource "aws_instance" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  tags = {
    Name           = "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
    ansible-group  = floor(count.index / var.arbiters_per_replset)
    ansible-index  = count.index % var.arbiters_per_replset
    environment    = var.env_tag
  }
  instance_type = var.arbiter_type
  availability_zone = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  ami = lookup(var.image, var.region)
  #subnet_id = aws_subnet.vpc-subnet.id
  associate_public_ip_address = true
  key_name = "${var.my_ssh_user}_key"
  vpc_security_group_ids = [aws_security_group.mongodb-arbiter-sg.id]
  user_data = <<EOT
    #!/bin/bash
    echo "Created"
EOT
}

resource "aws_security_group" "mongodb-arbiter-sg" {
  name        = "${var.env_tag}-${var.arbiter_tag}-security-group"
  description = "Allow traffic to MongoDB arbiter instances"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.arbiter_ports
    content {
      from_port   = 0
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.env_tag}-${var.arbiter_tag}-firewall"
    environment    = var.env_tag
  }
}

resource "aws_network_interface_sg_attachment" "arbiter_sg_attachment" {
  count              = var.shard_count * var.arbiters_per_replset
  security_group_id  = aws_security_group.mongodb-arbiter-sg.id
  network_interface_id = aws_instance.arbiter[count.index].primary_network_interface_id
}