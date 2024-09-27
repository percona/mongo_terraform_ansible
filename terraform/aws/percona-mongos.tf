resource "aws_instance" "mongos" {
  count               = var.mongos_count
  ami                 = lookup(var.image, var.region)
  instance_type      = var.mongos_type
  availability_zone   = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  key_name            = "${var.my_ssh_user}_key"
  #subnet_id           = aws_subnet.vpc_subnet.id
  tags = {
    Name = "${var.env_tag}-${var.mongos_tag}0${count.index}"
    ansible-group  = "mongos"
    environment    = var.env_tag
  }
  vpc_security_group_ids = [aws_security_group.mongodb_mongos_sg.id]
  user_data = <<-EOT
    #!/bin/bash
    echo "Created"
  EOT
}

resource "aws_security_group" "mongodb_mongos_sg" {
  name   = "${var.env_tag}-${var.mongos_tag}-sg"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.mongos_ports
    content {
      from_port   = 0
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
    }
  }
  tags = {
    Name = "${var.env_tag}-${var.mongos_tag}-sg"
    environment    = var.env_tag
  }
}