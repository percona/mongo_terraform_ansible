# Public IP
resource "azurerm_public_ip" "cfg" {
  count               = var.configsvr_count
  name                ="${var.cluster_name}-${var.configsvr_tag}0${count.index}-nic-public-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
}

# Create managed data disks for config servers
resource "azurerm_managed_disk" "cfg_disk" {
  count                = var.configsvr_count
  name                 = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.data_disk_type
  create_option        = "Empty"
  disk_size_gb         = var.configsvr_volume_size
}

# Create NSG for configsvr
resource "azurerm_network_security_group" "mongodb_cfgsvr_nsg" {
  name                = "${var.cluster_name}-${var.configsvr_tag}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowMongoDBConfigPort"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.configsvr_port
    source_address_prefix      = var.subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-ICMP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

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
}

# Create configsvr VM instances
resource "azurerm_linux_virtual_machine" "cfg" {
  count               = var.configsvr_count
  name                = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.configsvr_type
  admin_username      = var.my_ssh_user

  network_interface_ids = [
    azurerm_network_interface.cfg[count.index].id
  ]
  tags = { 
    ansible-group = "cfg",
    environment = var.env_tag
  }  

  admin_ssh_key {
    username   = var.my_ssh_user
    public_key = file(var.ssh_users[var.my_ssh_user])
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = try(var.image.version, "latest")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(<<EOT
#!/bin/bash
hostnamectl set-hostname "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
echo "127.0.0.1 $(hostname) localhost" > /etc/hosts

# Wait for the disk to appear
DEVICE="/dev/sdc"
while [ ! -b "$DEVICE" ]; do
  echo "Waiting for $DEVICE to become available..."
  sleep 2
done

# Format and mount the disk
mkfs.xfs $DEVICE
mkdir -p /var/lib/mongo
mount $DEVICE /var/lib/mongo

# Add to fstab
UUID=$(blkid -s UUID -o value "$DEVICE")
echo "UUID=$UUID /var/lib/mongo xfs defaults,noatime,nofail 0 2" >> /etc/fstab
EOT
  )
}

# Create NICs for configsvr
resource "azurerm_network_interface" "cfg" {
  count               = var.configsvr_count
  name                = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cfg[count.index].id
  }
}

# Attach disk to VM
resource "azurerm_virtual_machine_data_disk_attachment" "cfg_attach" {
  count              = var.configsvr_count
  managed_disk_id    = azurerm_managed_disk.cfg_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.cfg[count.index].id
  lun                = 0
  caching            = "ReadWrite"
}