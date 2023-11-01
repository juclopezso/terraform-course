
# Project - Create EC2 instance and been able to use it

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.23.1"
    }
  }
}

# 0. create a key pair in AWS: AWS / EC2 / Key Pairs

# variables
variable "subnet_prefix" {
  # all three keys are optional
  description = "cidr block for the subnet"
  type = string # Terraform supports any, numbers, booleans, tuples, ...
  # default = "10.0.1.0/24"
}
variable "subnet_value" {
  description = "subnet values"
}
variable "access_key" {
  description = "AWS access key"
  type = string
  sensitive = true
}
variable "secret_key" {
  description = "AWS secret key"
  type = string
  sensitive = true
}

provider "aws" {
  region = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

# 1. create a VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block       = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# 2. create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod_vpc.id
  tags = {
    Name = "production"
  }
}

# 3. create Custom Route Table
resource "aws_route_table" "prod_route_table" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0" # send all traffic whatever this route points
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "production"
  }
}

# 4. create a Subnet
resource "aws_subnet" "subnet_1" {
  vpc_id     = aws_vpc.prod_vpc.id
  # cidr_block = "10.0.1.0/24"
  # cidr_block = var.subnet_prefix
  cidr_block = var.subnet_value.cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = var.subnet_value.name
  }
}

# 5. associate subnet with Route Table (Route table association)
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.prod_route_table.id
}

# 6. create a Security Group to allow port 22,80,443
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # any can access the network
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # any can access the network
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # any can access the network
  }

  # any egres connection
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. create a network interface with an ip in the subnet (private IP) that was created in step 4
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface

resource "aws_network_interface" "web_server_nic" {
  subnet_id       = aws_subnet.subnet_1.id
  private_ips     = ["10.0.1.50"] # address within the range of the subnet
  security_groups = [aws_security_group.allow_web.id]
}

# 8. assign an elastic IP (public IP) to the network interface created in step 7
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip

resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw] # whole object, not just the id
}

# print output in the console when the code runs
output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# 9. create Ubuntu server and install/enable apache2
## https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance

resource "aws_instance" "ubuntu" {
  ami = "ami-0fc5d935ebf8bc3bc"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a" # same as subnet
  key_name = "main-key"

  network_interface {
    device_index = 0 # first network interface
    network_interface_id = aws_network_interface.web_server_nic.id
  }

  # start/enable apache
  user_data = "${file("user_data.sh")}"

  tags = {
    Name = "production_web_server"
  }
}

output "server_private_ip" {
  value = aws_instance.ubuntu.private_ip
}
output "server_id" {
  value = aws_instance.ubuntu.id
}

