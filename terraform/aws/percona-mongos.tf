resource "aws_instance" "mongos" {
  count               = var.mongos_count
  ami                 = lookup(var.image, var.region)
  instance_type       = var.mongos_type
  #availability_zone   = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone   = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].availability_zone
  key_name            = aws_key_pair.my_key_pair.key_name
  subnet_id           = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet)].id
  tags = {
    Name = "${var.env_tag}-${var.mongos_tag}0${count.index}"
    ansible-group  = "mongos"
    environment    = var.env_tag
  }
  vpc_security_group_ids = [aws_security_group.mongodb_mongos_sg.id]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.mongos_tag}0${count.index}.${var.env_tag}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
  EOT
}

resource "aws_security_group" "mongodb_mongos_sg" {
  name   = "${var.env_tag}-${var.mongos_tag}-sg"
  vpc_id = aws_vpc.vpc-network.id
  dynamic "ingress" {
    for_each = var.mongos_ports
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
    Name = "${var.env_tag}-${var.mongos_tag}-sg"
    environment    = var.env_tag
  }
}

resource "aws_route53_record" "mongos_dns_record" {
  count   = var.mongos_count
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "${var.env_tag}-${var.mongos_tag}0${count.index}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.mongos[count.index].private_ip]
}