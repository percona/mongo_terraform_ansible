variable "vault_type" {
  type    = string
  default = "t3.small"
}

variable "vault_volume_size" {
  type    = number
  default = 20
}

variable "vault_controller_dir" {
  type    = string
  default = ""
}

module "vault_mode_guard" {
  source         = "../modules/vault_mode_guard"
  controller_dir = var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/aws/${var.prefix}")
  topologies     = merge({ for n in keys(var.clusters) : "cluster-${n}" => var.vault_encryption }, { for n in keys(var.replsets) : "replset-${n}" => var.vault_encryption })
  enabled        = var.vault_encryption
}

module "vault_recovery" {
  count          = local.vault_enabled ? 1 : 0
  source         = "../modules/vault_recovery"
  controller_dir = var.vault_controller_dir != "" ? var.vault_controller_dir : "${path.module}/../../ansible/.vault/aws/${var.prefix}"
}

locals {
  vault_host    = "${var.prefix}-vault"
  vault_enabled = var.vault_encryption && length(var.clusters) + length(var.replsets) > 0
  vault_topologies = local.vault_enabled ? concat(
    [for name in keys(var.clusters) : "cluster-${name}"],
    [for name in keys(var.replsets) : "replset-${name}"]
  ) : []
  vault_inventory = local.vault_enabled ? "\n[vault]\n${local.vault_host} ansible_host=${aws_instance.vault[0].public_ip}\n\n[all:vars]\nvault_server=${aws_instance.vault[0].private_ip}\nvault_environment=${var.prefix}\nvault_encryption=true\nvault_topologies_json='${jsonencode(local.vault_topologies)}'\nvault_controller_dir_override=${jsonencode(var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/aws/${var.prefix}"))}\n" : ""
}

resource "aws_instance" "vault" {
  count                  = local.vault_enabled ? 1 : 0
  ami                    = lookup(var.image, var.region)
  instance_type          = var.vault_type
  subnet_id              = aws_subnet.vpc-subnet[0].id
  key_name               = aws_key_pair.my_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.vault[0].id]
  root_block_device {
    volume_size = var.vault_volume_size
    encrypted   = true
  }
  tags      = { Name = local.vault_host }
  user_data = <<-EOT
    #!/bin/bash
    id -u "${var.my_ssh_user}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${var.my_ssh_user}"
    echo "${var.my_ssh_user} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${var.my_ssh_user}"
    chmod 440 "/etc/sudoers.d/${var.my_ssh_user}"
    home_dir="$(getent passwd "${var.my_ssh_user}" | cut -d: -f6)"
    install -d -m 700 -o "${var.my_ssh_user}" -g "${var.my_ssh_user}" "$home_dir/.ssh"
    printf '%s' '${base64encode(file(var.ssh_public_key_path))}' | base64 -d > "$home_dir/.ssh/authorized_keys"
    chown "${var.my_ssh_user}:${var.my_ssh_user}" "$home_dir/.ssh/authorized_keys"
    chmod 600 "$home_dir/.ssh/authorized_keys"
    hostnamectl set-hostname "${local.vault_host}"
  EOT
  lifecycle {
    precondition {
      condition = alltrue(concat(
        [for t in values(var.clusters) : (t.mongodb_distribution != "" ? t.mongodb_distribution : var.mongodb_distribution) == "psmdb"],
        [for t in values(var.replsets) : (t.mongodb_distribution != "" ? t.mongodb_distribution : var.mongodb_distribution) == "psmdb"]
      ))
      error_message = "Vault encryption is supported only for PSMDB topologies."
    }
  }
}

resource "aws_security_group" "vault" {
  count  = local.vault_enabled ? 1 : 0
  name   = "${local.vault_host}-sg"
  vpc_id = aws_vpc.vpc-network.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.source_ranges, aws_vpc.vpc-network.cidr_block]
  }
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc-network.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "local_file" "VaultInventory" {
  count    = local.vault_enabled ? 1 : 0
  filename = "${var.prefix}_inventory_vault"
  content  = "${local.vault_inventory}\n[all:vars]\nansible_user=${var.my_ssh_user}\nansible_ssh_private_key_file=${var.ssh_private_key_path}\nansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null\n"
}
