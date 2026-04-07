resource "aws_instance" "ycsb" {
  count             = var.enable_ycsb ? 1 : 0
  ami               = lookup(var.image, var.region)
  instance_type     = var.ycsb_type
  availability_zone = aws_subnet.vpc-subnet[0].availability_zone
  key_name          = aws_key_pair.my_key_pair.key_name
  subnet_id         = aws_subnet.vpc-subnet[0].id
  tags = {
    Name = local.ycsb_host
  }
  vpc_security_group_ids = [aws_security_group.mongodb_ycsb_sg[0].id]
  user_data              = <<-EOT
    #!/bin/bash
    hostnamectl set-hostname "${local.ycsb_host}"
    echo "127.0.0.1 ${local.ycsb_host}.${aws_route53_zone.private_zone.name} $(hostname) localhost" > /etc/hosts
  EOT
  monitoring             = true
}

resource "aws_security_group" "mongodb_ycsb_sg" {
  count       = var.enable_ycsb ? 1 : 0
  name        = "${local.ycsb_host}-sg"
  description = "Allow traffic to YCSB instance"
  vpc_id      = aws_vpc.vpc-network.id

  tags = {
    Name = "${local.ycsb_host}-sg"
  }
}

resource "aws_security_group_rule" "mongodb-ycsb-ssh_inbound" {
  count             = var.enable_ycsb ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mongodb_ycsb_sg[0].id
  description       = "SSH from anywhere"
}

resource "aws_security_group_rule" "mongodb-ycsb-egress" {
  count             = var.enable_ycsb ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.mongodb_ycsb_sg[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_route53_record" "ycsb_dns_record" {
  count   = var.enable_ycsb ? 1 : 0
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = local.ycsb_host
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ycsb[0].private_ip]
}
