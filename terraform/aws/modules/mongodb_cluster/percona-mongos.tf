resource "aws_instance" "mongos" {
  count               = var.mongos_count
  ami                 = lookup(var.image, var.region)
  instance_type       = var.mongos_type
  subnet_id           = data.aws_subnet.details[count.index % var.subnet_count].id
  key_name            = data.aws_key_pair.my_key_pair.key_name
  tags = {
    Name = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
    ansible-group  = "mongos"
  }
  vpc_security_group_ids = [aws_security_group.mongodb_mongos_sg.id]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.cluster_name}-${var.mongos_tag}0${count.index}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname).${data.aws_route53_zone.private_zone.name} $(hostname) localhost" > /etc/hosts    
  EOT
}

resource "aws_security_group" "mongodb_mongos_sg" {
  name        = "${var.cluster_name}-${var.mongos_tag}-sg"
  description = "Allow traffic to MongoDB mongos instances"
  vpc_id      = data.aws_vpc.vpc-network.id

  tags = {
    Name        = "${var.cluster_name}-${var.mongos_tag}-sg"
  }
}

resource "aws_security_group_rule" "mongodb-mongos-ingress" {
  for_each          = toset([for port in var.mongos_ports : tostring(port)])
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  security_group_id = aws_security_group.mongodb_mongos_sg.id
  cidr_blocks       = [var.subnet_cidr]  
}

# Ingress rule (SSH from anywhere)
resource "aws_security_group_rule" "mongodb-mongos-ssh_inbound" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mongodb_mongos_sg.id
  description       = "SSH from anywhere"
}

# Ingress rule for ICMP (ping) traffic
resource "aws_security_group_rule" "mongodb-mongos-icmp-ingress" {
  type              = "ingress"
  from_port         = 8     # Type 8 for echo request (ping)
  to_port           = 0
  protocol          = "icmp"
  security_group_id = aws_security_group.mongodb_mongos_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Egress rule allowing all traffic
resource "aws_security_group_rule" "mongodb-mongos-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.mongodb_mongos_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow all outbound IPv4 traffic
  ipv6_cidr_blocks  = ["::/0"]       # Allow all outbound IPv6 traffic
}

resource "aws_route53_record" "mongos_dns_record" {
  count   = var.mongos_count
  zone_id = data.aws_route53_zone.private_zone.zone_id
  name    = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.mongos[count.index].private_ip]
}