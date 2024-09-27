data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc-network" {
  cidr_block = var.subnet
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.env_tag}-${var.network_name}-vpc"
    environment    = var.env_tag
  }
}

resource "aws_subnet" "vpc-subnet" {
  vpc_id            = aws_vpc.vpc-network.id
  cidr_block        = cidrsubnet(var.subnet, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  count = var.subnet_count
  tags = {
    Name = "${var.env_tag}-${var.subnet_name}-${count.index + 1}"
    environment    = var.env_tag
  }
}

resource "aws_key_pair" "my_key_pair" {
  key_name   = "${var.env_tag}-${var.my_ssh_user}-key"
  public_key = file(var.ssh_public_key_path)
}