resource "aws_instance" "ca" {
  count             = var.enable_tls && var.ca_placement == "dedicated" ? 1 : 0
  ami               = lookup(var.image, var.region)
  instance_type     = var.ca_type
  availability_zone = aws_subnet.vpc-subnet[0].availability_zone
  key_name          = aws_key_pair.my_key_pair.key_name
  subnet_id         = aws_subnet.vpc-subnet[0].id

  tags = {
    Name = local.ca_host
  }

  vpc_security_group_ids = [aws_security_group.ca[0].id]
  user_data              = <<-EOT
    #!/bin/bash
    id -u "${var.my_ssh_user}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${var.my_ssh_user}"
    usermod -aG wheel "${var.my_ssh_user}" 2>/dev/null || usermod -aG sudo "${var.my_ssh_user}" 2>/dev/null || true
    echo "${var.my_ssh_user} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${var.my_ssh_user}"
    chmod 440 "/etc/sudoers.d/${var.my_ssh_user}"
    home_dir="$(getent passwd "${var.my_ssh_user}" | cut -d: -f6)"
    install -d -m 700 -o "${var.my_ssh_user}" -g "${var.my_ssh_user}" "$home_dir/.ssh"
    printf '%s' '${base64encode(file(var.ssh_public_key_path))}' | base64 -d > "$home_dir/.ssh/authorized_keys"
    chown "${var.my_ssh_user}:${var.my_ssh_user}" "$home_dir/.ssh/authorized_keys"
    chmod 600 "$home_dir/.ssh/authorized_keys"
    hostnamectl set-hostname "${local.ca_host}"
    echo "127.0.0.1 ${local.ca_host}.${aws_route53_zone.private_zone.name} $(hostname) localhost" > /etc/hosts
  EOT
}

resource "aws_security_group" "ca" {
  count       = var.enable_tls && var.ca_placement == "dedicated" ? 1 : 0
  name        = "${local.ca_host}-sg"
  description = "Allow SSH access to the dedicated CA instance"
  vpc_id      = aws_vpc.vpc-network.id

  tags = {
    Name = "${local.ca_host}-sg"
  }
}

resource "aws_security_group_rule" "ca_ssh_inbound" {
  count             = var.enable_tls && var.ca_placement == "dedicated" ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.source_ranges]
  security_group_id = aws_security_group.ca[0].id
  description       = "SSH access"
}

resource "aws_security_group_rule" "ca_egress" {
  count             = var.enable_tls && var.ca_placement == "dedicated" ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.ca[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_route53_record" "ca" {
  count   = var.enable_tls && var.ca_placement == "dedicated" ? 1 : 0
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = local.ca_host
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ca[0].private_ip]
}
