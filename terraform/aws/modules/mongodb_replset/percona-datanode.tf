resource "aws_ebs_volume" "replset_disk" {
  count              = var.data_nodes_per_replset
  availability_zone  = data.aws_subnet.details[count.index % var.subnet_count].availability_zone
  size               = var.replsetsvr_volume_size
  type               = var.data_disk_type
  tags = {
    Name = "${var.rs_name}-${var.replset_tag}svr${count.index % var.data_nodes_per_replset}-data"
  }
}

resource "aws_instance" "replset" {
  count               = var.data_nodes_per_replset
  ami                 = lookup(var.image, var.region)
  instance_type       = var.replsetsvr_type
  subnet_id           = data.aws_subnet.details[count.index % var.subnet_count].id
  key_name            = data.aws_key_pair.my_key_pair.key_name
    tags = {
    Name = "${var.rs_name}-${var.replset_tag}svr${count.index % var.data_nodes_per_replset}"
    ansible-group  = var.replset_tag
  }
  vpc_security_group_ids = [aws_security_group.replsetsvr_sg.id]
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.rs_name}-${var.replset_tag}svr${count.index % var.data_nodes_per_replset}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    

    # Add a dash to lsblk output to match the Terraform volume ID 
    DEVICE=$(lsblk -o NAME,SERIAL | sed 's/l/l-/' | grep "${aws_ebs_volume.replset_disk[count.index].id}" | awk '{print "/dev/" $1}')

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/mongo

    mount $DEVICE /var/lib/mongo

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$UUID /var/lib/mongo xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  EOT
}

resource "aws_volume_attachment" "replset_volume_attachment" {
  count        = var.data_nodes_per_replset
  device_name  = "/dev/sdf" # Placeholder, not used for NVMe but required by Terraform
  volume_id    = aws_ebs_volume.replset_disk[count.index].id
  instance_id  = aws_instance.replset[count.index].id
}

resource "aws_security_group" "replsetsvr_sg" {
  name        = "${var.rs_name}-${var.replset_tag}-sg"
  description = "Allow traffic to MongoDB replset instances"
  vpc_id      = data.aws_vpc.vpc-network.id
  tags = {
    Name      = "${var.rs_name}-${var.replset_tag}-sg"
  }
}

resource "aws_security_group_rule" "mongodb-replset-ingress" {
  for_each          = toset([for port in var.replsetsvr_ports : tostring(port)])
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  security_group_id = aws_security_group.replsetsvr_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Ingress rule for ICMP (ping) traffic
resource "aws_security_group_rule" "mongodb-replset-icmp-ingress" {
  type              = "ingress"
  from_port         = 8     # Type 8 for echo request (ping)
  to_port           = 0
  protocol          = "icmp"
  security_group_id = aws_security_group.replsetsvr_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Egress rule allowing all traffic
resource "aws_security_group_rule" "mongodb-replset-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.replsetsvr_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow all outbound IPv4 traffic
  ipv6_cidr_blocks  = ["::/0"]       # Allow all outbound IPv6 traffic
}

resource "aws_route53_record" "replsetsvr_dns_record" {
  count   = var.data_nodes_per_replset
  zone_id = data.aws_route53_zone.private_zone.zone_id
  name    = "${var.rs_name}-${var.replset_tag}svr${count.index % var.data_nodes_per_replset}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.replset[count.index].private_ip]
}