data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc-network" {
  cidr_block = var.subnet_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = local.vpc
  }
}

resource "aws_subnet" "vpc-subnet" {
  vpc_id            = aws_vpc.vpc-network.id
  cidr_block        = cidrsubnet(var.subnet_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]  
  map_public_ip_on_launch = true
  count = var.subnet_count
  tags = {
    Name = "${local.vpc}-subnet-${count.index}"
    AvailabilityZone = data.aws_availability_zones.available.names[count.index]    
  }
}

resource "aws_internet_gateway" "vpc-igw" {
  vpc_id = aws_vpc.vpc-network.id
  tags = {
    Name = "${local.vpc}-IGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc-network.id
  route {
    cidr_block = "0.0.0.0/0"  # Route to the Internet
    gateway_id = aws_internet_gateway.vpc-igw.id
  }
  tags = {
    Name           = "${local.vpc}-PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.vpc-subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# DNS
resource "aws_route53_zone" "private_zone" {
  name = local.vpc
  vpc {
    vpc_id = aws_vpc.vpc-network.id 
  }
}

# Key pair for SSH access
resource "aws_key_pair" "my_key_pair" {
  key_name   = "${var.prefix}-${var.my_ssh_user}-key"
  public_key = file(var.ssh_public_key_path)
}