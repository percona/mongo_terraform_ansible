resource "aws_instance" "pcsm" {
  count         = var.enable_pcsm ? 1 : 0
  ami           = lookup(var.image, var.region)
  instance_type = var.pcsm_type
  key_name      = aws_key_pair.my_key_pair.key_name
  subnet_id     = aws_subnet.vpc-subnet[0].id

  vpc_security_group_ids = [aws_security_group.pcsm[0].id]
  monitoring             = true

  tags = {
    Name = local.pcsm_host
    role = "pcsm"
  }

  user_data = <<-EOT
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
    hostnamectl set-hostname "${local.pcsm_host}"
  EOT
}

resource "aws_security_group" "pcsm" {
  count       = var.enable_pcsm ? 1 : 0
  name        = "${local.pcsm_host}-sg"
  description = "PCSM SSH access; API port 2242 is intentionally not exposed"
  vpc_id      = aws_vpc.vpc-network.id

  tags = { Name = "${local.pcsm_host}-sg" }
}

resource "aws_security_group_rule" "pcsm_ssh" {
  count             = var.enable_pcsm ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.source_ranges]
  security_group_id = aws_security_group.pcsm[0].id
  description       = "SSH access"
}

resource "aws_security_group_rule" "pcsm_egress" {
  count             = var.enable_pcsm ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.pcsm[0].id
}

resource "aws_route53_record" "pcsm" {
  count   = var.enable_pcsm ? 1 : 0
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = local.pcsm_host
  type    = "A"
  ttl     = 300
  records = [aws_instance.pcsm[0].private_ip]
}
