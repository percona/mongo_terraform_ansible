# Public IP
resource "azurerm_public_ip" "replset" {
  count               = var.data_nodes_per_replset
  name                = "${var.rs_name}-${var.replset_tag}${count.index}-nic-public-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
}

# Network-security group for the replica-set
resource "azurerm_network_security_group" "replset_nsg" {
  name                = "${var.rs_name}-${var.replset_tag}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowReplsetPort"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.replsetsvr_port
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

# Managed data-disk for every data-bearing member
resource "azurerm_managed_disk" "replset_disk" {
  count                = var.data_nodes_per_replset
  name                 = "${var.rs_name}-${var.replset_tag}${count.index}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.data_disk_type
  create_option        = "Empty"
  disk_size_gb         = var.replsetsvr_volume_size
}

# Network-interface for every member
resource "azurerm_network_interface" "replset" {
  count               = var.data_nodes_per_replset
  name                = "${var.rs_name}-${var.replset_tag}${count.index}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.replset[count.index].id
  }
}

# VM for every replica-set member
resource "azurerm_linux_virtual_machine" "replset" {
  count               = var.data_nodes_per_replset
  name                = "${var.rs_name}-${var.replset_tag}${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.replsetsvr_type
  admin_username      = var.my_ssh_user
  
  tags = { 
    ansible-group = var.replset_tag,
    environment = var.env_tag
  }  

  network_interface_ids = [
    azurerm_network_interface.replset[count.index].id
  ]

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

  priority        = var.use_spot_instances ? "Spot" : "Regular"
  eviction_policy = var.use_spot_instances ? "Deallocate" : null

  custom_data = base64encode(<<EOT
#!/bin/bash

# Set the hostname
hostnamectl set-hostname "${var.rs_name}-${var.replset_tag}${count.index}"
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

# Attach each managed disk to its VM
resource "azurerm_virtual_machine_data_disk_attachment" "replset_attach" {
  count              = var.data_nodes_per_replset
  managed_disk_id    = azurerm_managed_disk.replset_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.replset[count.index].id
  lun                = 0
  caching            = "ReadWrite"
}