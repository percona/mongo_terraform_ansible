resource "aws_ebs_volume" "shard_disk" {
  count             = var.shard_count * var.shardsvr_replicas
#  availability_zone = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet) % var.shardsvr_replicas].availability_zone
  size              = var.shardsvr_volume_size
  type              = var.data_disk_type
  tags = {
    Name = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}-data"
    environment    = var.env_tag
  }
}

resource "aws_instance" "shard" {
  count               = var.shard_count * var.shardsvr_replicas
  ami                 = lookup(var.image, var.region)
  instance_type       = var.shardsvr_type
  #availability_zone   = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))
  availability_zone   = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet) % var.shardsvr_replicas].availability_zone
  key_name            = aws_key_pair.my_key_pair.key_name
  subnet_id           = aws_subnet.vpc-subnet[count.index % length(aws_subnet.vpc-subnet) % var.shardsvr_replicas].id
  tags = {
    Name = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
    ansible-group = floor(count.index / var.shardsvr_replicas )
    ansible-index = count.index % var.shardsvr_replicas
    environment = var.env_tag
  }  
  user_data = <<-EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}.${var.env_tag}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    

    # Add a dash to lsblk output to match the Terraform volume ID 
    DEVICE=$(lsblk -o NAME,SERIAL | sed 's/l/l-/' | grep "${aws_ebs_volume.shard_disk[count.index].id}" | awk '{print "/dev/" $1}')

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/mongo

    mount $DEVICE /var/lib/mongo

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$DEVICE /var/lib/mongo xfs defaults,noatime,nofail 0 2" >> /etc/fstab    
  EOT
  vpc_security_group_ids = [aws_security_group.mongodb_shardsvr_sg.id]
}

resource "aws_volume_attachment" "shard_volume_attachment" {
  count        = var.shard_count * var.shardsvr_replicas
  device_name  = "/dev/sdf" # Placeholder, not used for NVMe but required by Terraform
  volume_id    = aws_ebs_volume.shard_disk[count.index].id
  instance_id  = aws_instance.shard[count.index].id
}

resource "aws_security_group" "mongodb_shardsvr_sg" {
  name        = "${var.env_tag}-${var.shardsvr_tag}-sg"
  description = "Allow traffic to MongoDB shardsvr instances"
  vpc_id      = aws_vpc.vpc-network.id

  tags = {
    Name        = "${var.env_tag}-${var.shardsvr_tag}-sg"
    environment = var.env_tag
  }
}

resource "aws_security_group_rule" "mongodb-shardsvr-ingress" {
  for_each          = toset([for port in var.shardsvr_ports : tostring(port)])
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  security_group_id = aws_security_group.mongodb_shardsvr_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Ingress rule for ICMP (ping) traffic
resource "aws_security_group_rule" "mongodb-shardsvr-icmp-ingress" {
  type              = "ingress"
  from_port         = 8     # Type 8 for echo request (ping)
  to_port           = 0
  protocol          = "icmp"
  security_group_id = aws_security_group.mongodb_shardsvr_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from any IP address; adjust based on your needs
}

# Egress rule allowing all traffic
resource "aws_security_group_rule" "mongodb-shardsvr-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.mongodb_shardsvr_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Allow all outbound IPv4 traffic
  ipv6_cidr_blocks  = ["::/0"]       # Allow all outbound IPv6 traffic
}

resource "aws_route53_record" "shard_dns_record" {
  count   = var.shard_count * var.shardsvr_replicas
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.shard[count.index].private_ip]
}