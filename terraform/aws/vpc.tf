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
  count = length(data.aws_availability_zones.available.names)
  tags = {
    Name = "${var.env_tag}-${var.subnet_name}-${count.index}"
    environment    = var.env_tag
  }
}

resource "aws_internet_gateway" "vpc-igw" {
  vpc_id = aws_vpc.vpc-network.id
  tags = {
    Name = "${var.env_tag}-${var.network_name}-IGW"
    environment    = var.env_tag
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc-network.id
  route {
    cidr_block = "0.0.0.0/0"  # Route to the Internet
    gateway_id = aws_internet_gateway.vpc-igw.id
  }
  tags = {
    Name           = "${var.env_tag}-${var.network_name}-PublicRouteTable"
    environment    = var.env_tag    
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = aws_subnet.vpc-subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route53_zone" "private_zone" {
  name = var.env_tag
  vpc {
    vpc_id = aws_vpc.vpc-network.id 
  }
}

resource "aws_key_pair" "my_key_pair" {
  key_name   = "${var.env_tag}-mongo-${var.my_ssh_user}-key"
  public_key = file(var.ssh_public_key_path)
}