# Public IP for YCSB
resource "azurerm_public_ip" "ycsb" {
  count               = var.enable_ycsb ? 1 : 0
  name                = "${local.ycsb_host}-public-ip"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Dynamic"
  depends_on          = [time_sleep.wait_after_rg]
}

resource "azurerm_network_interface" "ycsb_nic" {
  count               = var.enable_ycsb ? 1 : 0
  name                = "${local.ycsb_host}-nic"
  location            = var.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ycsb[0].id
  }

  depends_on = [time_sleep.wait_after_rg]
}

resource "azurerm_network_security_group" "ycsb_nsg" {
  count               = var.enable_ycsb ? 1 : 0
  name                = "${local.ycsb_host}-nsg"
  location            = var.location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.source_ranges
    destination_address_prefix = "*"
  }

  depends_on = [time_sleep.wait_after_rg]
}

resource "azurerm_network_interface_security_group_association" "ycsb_nsg_assoc" {
  count                     = var.enable_ycsb ? 1 : 0
  network_interface_id      = azurerm_network_interface.ycsb_nic[0].id
  network_security_group_id = azurerm_network_security_group.ycsb_nsg[0].id
}

resource "azurerm_linux_virtual_machine" "ycsb" {
  count               = var.enable_ycsb ? 1 : 0
  name                = local.ycsb_host
  location            = var.location
  resource_group_name = local.resource_group_name
  size                = var.ycsb_type
  admin_username      = var.my_ssh_user
  network_interface_ids = [
    azurerm_network_interface.ycsb_nic[0].id,
  ]

  admin_ssh_key {
    username   = var.my_ssh_user
    public_key = file(var.ssh_users[var.my_ssh_user])
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = try(var.image.version, "latest")
  }

  custom_data = base64encode(<<EOT
#!/bin/bash
hostnamectl set-hostname "${local.ycsb_host}"
echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
EOT
  )

  tags = {
    role = "ycsb"
  }

  depends_on = [
    azurerm_network_interface_security_group_association.ycsb_nsg_assoc[0]
  ]
}
