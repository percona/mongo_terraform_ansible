locals {
  ldap_hosts = { for name, server in var.ldap_servers : name => "${var.prefix}-${name}" }
}

resource "chaos_instance" "ldap" {
  for_each          = var.ldap_servers
  name              = local.ldap_hosts[each.key]
  os                = var.os_image
  cpu_cores         = each.value.cpu_cores
  memory            = each.value.memory_gb
  disk              = 20
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} LDAP server"
  delete_after_days = var.delete_after_days
  firewall_rules = toset(concat(var.firewall_rules, [
    { source = "10.30.0.0/16", port = "389", protocol = "tcp", comment = "Allow LDAP access" },
    { source = "10.30.0.0/16", port = "80", protocol = "tcp", comment = "Allow phpLDAPadmin access" },
  ]))
}
