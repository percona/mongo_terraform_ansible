locals {
  ldap_hosts = { for name, server in var.ldap_servers : name => "${var.prefix}-${name}" }
}

resource "aws_security_group" "ldap" {
  for_each    = var.ldap_servers
  name        = "${local.ldap_hosts[each.key]}-sg"
  description = "Allow LDAP, phpLDAPadmin, and SSH access"
  vpc_id      = aws_vpc.vpc-network.id
}

resource "aws_security_group_rule" "ldap_internal" {
  for_each          = var.ldap_servers
  type              = "ingress"
  from_port         = 389
  to_port           = 389
  protocol          = "tcp"
  security_group_id = aws_security_group.ldap[each.key].id
  cidr_blocks       = [var.subnet_cidr]
}

resource "aws_security_group_rule" "ldap_http" {
  for_each          = var.ldap_servers
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.ldap[each.key].id
  cidr_blocks       = [var.subnet_cidr]
}

resource "aws_security_group_rule" "ldap_ssh" {
  for_each          = var.ldap_servers
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.ldap[each.key].id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ldap_egress" {
  for_each          = var.ldap_servers
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.ldap[each.key].id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_instance" "ldap" {
  for_each               = var.ldap_servers
  ami                    = lookup(var.image, var.region)
  instance_type          = each.value.instance_type
  availability_zone      = aws_subnet.vpc-subnet[0].availability_zone
  key_name               = aws_key_pair.my_key_pair.key_name
  subnet_id              = aws_subnet.vpc-subnet[0].id
  vpc_security_group_ids = [aws_security_group.ldap[each.key].id]
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
    hostnamectl set-hostname "${local.ldap_hosts[each.key]}"
  EOT
  tags                   = { Name = local.ldap_hosts[each.key] }
}

resource "aws_route53_record" "ldap" {
  for_each = var.ldap_servers
  zone_id  = aws_route53_zone.private_zone.zone_id
  name     = local.ldap_hosts[each.key]
  type     = "A"
  ttl      = "300"
  records  = [aws_instance.ldap[each.key].private_ip]
}
