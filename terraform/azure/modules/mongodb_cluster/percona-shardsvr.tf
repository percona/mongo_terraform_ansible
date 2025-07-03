# Public IP
resource "azurerm_public_ip" "shard" {
  count               = var.shard_count * var.shardsvr_replicas
  name                = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-nic-public-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
}

# NSG for shard nodes
resource "azurerm_network_security_group" "mongodb_shard_nsg" {
  name                = "${var.cluster_name}-${var.shardsvr_tag}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowMongoDBShardPort"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.shard_port
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
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.source_ranges
    destination_address_prefix = "*"
  }      
}

# Data disks for each shard node
resource "azurerm_managed_disk" "shard_disk" {
  count                = var.shard_count * var.shardsvr_replicas
  name                 = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.data_disk_type
  create_option        = "Empty"
  disk_size_gb         = var.shardsvr_volume_size
}

# NIC for shard node
resource "azurerm_network_interface" "shard" {
  count               = var.shard_count * var.shardsvr_replicas
  name                = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.shard[count.index].id
  }
}

# VM for each shard server
resource "azurerm_linux_virtual_machine" "shard" {
  count               = var.shard_count * var.shardsvr_replicas
  name                = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.shardsvr_type
  admin_username      = var.my_ssh_user
  tags = { 
    ansible-group = floor(count.index / var.shardsvr_replicas ),
    ansible-index = count.index % var.shardsvr_replicas,
    environment = var.env_tag
  }  

  network_interface_ids = [
    azurerm_network_interface.shard[count.index].id
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

  priority        = var.use_spot_instances ? "Spot" : "Regular"
  eviction_policy = var.use_spot_instances ? "Deallocate" : null

  custom_data = base64encode(<<EOT
#!/bin/bash
hostnamectl set-hostname "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
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

# Attach data disk to each shard server
resource "azurerm_virtual_machine_data_disk_attachment" "shard_disk_attachment" {
  count              = var.shard_count * var.shardsvr_replicas
  managed_disk_id    = azurerm_managed_disk.shard_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.shard[count.index].id
  lun                = 0
  caching            = "ReadWrite"
}