resource "aws_instance" "arbiter" {
  count = var.shard_count * var.arbiters_per_replset
  tags = {
    Name           = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % {var.arbiters_per_replset}"
    ansible-group  = floor(count.index / var.arbiters_per_replset)
    ansible-index  = count.index % var.arbiters_per_replset
    environment    = var.env_tag
  }
  instance_type    = var.arbiter_type
  availability_zone = reverse(aws_subnet.vpc-subnet)[count.index % length(aws_subnet.vpc-subnet) % var.arbiters_per_replset].availability_zone
  ami               = lookup(var.image, var.region)
  subnet_id         = reverse(aws_subnet.vpc-subnet)[count.index % length(aws_subnet.vpc-subnet) % var.arbiters_per_replset].id
  associate_public_ip_address = true
  key_name          = aws_key_pair.my_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.mongodb-arbiter-sg.id]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index} % {var.arbiters_per_replset}.${var.env_tag}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
  EOT
}

resource "aws_security_group" "mongodb-arbiter-sg" {
  name        = "${var.env_tag}-${var.arbiter_tag}-sg"
  description = "Allow traffic to MongoDB arbiter instances"
  vpc_id      = aws_vpc.vpc-network.id

  tags = {
    Name        = "${var.env_tag}-${var.arbiter_tag}-sg"
    environment = var.env_tag
  }
}

resource "aws_security_group_rule" "mongodb-arbiter-ingress" {
  for_each          = toset([for port in var.arbiter_ports : tostring(port)])
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  security_group_id = aws_security_group.mongodb-arbiter-sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Ingress rule for ICMP (ping) traffic
resource "aws_security_group_rule" "mongodb-arbiter-icmp-ingress" {
  type              = "ingress"
  from_port         = 8     # Type 8 for echo request (ping)
  to_port           = 0
  protocol          = "icmp"
  security_group_id = aws_security_group.mongodb-arbiter-sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Egress rule allowing all traffic
resource "aws_security_group_rule" "mongodb-arbiter-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.mongodb-arbiter-sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow all outbound IPv4 traffic
  ipv6_cidr_blocks  = ["::/0"]       # Allow all outbound IPv6 traffic
}

resource "aws_route53_record" "arbiter_dns_record" {
  count   = var.shard_count * var.arbiters_per_replset
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.arbiter[count.index].private_ip]
}