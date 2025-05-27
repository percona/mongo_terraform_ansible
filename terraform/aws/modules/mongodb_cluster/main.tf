terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.68.0"
    }
  }
}

# Get the VPC object using its name
data "aws_vpc" "vpc-network" {
  filter {
    name   = "tag:Name"
    values = [var.vpc]  
  }
}

# Get all subnets in the VPC
data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc-network.id]
  }
}

# Get details for subnet
data "aws_subnet" "details" {
  count = var.subnet_count
  id    = data.aws_subnets.subnets.ids[count.index]
}

# Get the existing key pair object
data "aws_key_pair" "my_key_pair" {
  key_name = "${var.my_ssh_user}-key"
}

# Get the existing DNS zone
data "aws_route53_zone" "private_zone" {
  name = var.vpc  
  private_zone = true
}