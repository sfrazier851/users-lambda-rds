# Terraform Settings Block
terraform {
  # Terraform Version
  required_version = "~> 0.14.6"
  required_providers {
    # AWS Provider 
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.0.0"
    }
    # Random Provider
    random = {
      source  = "hashicorp/random"
      version = "3.0.0"
    }
    # TLS Provider
    tls = {
      source  = "hashicorp/tls"
      version = "3.3.0"
    }
  }
  # S3 Backend for Remote State Storage
  backend "s3" {
    bucket = "user-lambda-rds-tfstate"
    key    = "dev/terraform.tfstate"
    region = "us-east-1" 
    
    # For State Locking
    dynamodb_table = "terraform-dev-state-table"    
  }
}

# Provider Block
provider "aws" {
  region  = "us-east-1"
  profile = "default"
}

resource "aws_vpc" "rds_lambda_apig" {
  cidr_block           = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "rds-lambda-apig"
  }
}

resource "aws_subnet" "private_rds1" {
  vpc_id            = aws_vpc.rds_lambda_apig.id
  cidr_block        = "10.0.1.0/24" 
  availability_zone = "us-east-1a"

  tags = {
    Name = "private_rds1"
  }
}

resource "aws_subnet" "private_rds2" {
  vpc_id            = aws_vpc.rds_lambda_apig.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private_rds2"
  }
}

resource "aws_subnet" "public_bastion" {
  vpc_id            = aws_vpc.rds_lambda_apig.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true

  tags = {
    Name = "public_bastion"
  }
}

resource "aws_internet_gateway" "public_bastion" {
  vpc_id = aws_vpc.rds_lambda_apig.id
}

#resource "aws_internet_gateway_attachment" "public_bastion" {
#  internet_gateway_id = aws_internet_gateway.public_bastion.id
#  vpc_id              = aws_vpc.rds_lambda_apig.id
#}

resource "aws_route_table" "public_bastion" {
  vpc_id     = aws_vpc.rds_lambda_apig.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public_bastion.id
  }
}

resource "aws_route_table_association" "public_bastion" {
  subnet_id      = aws_subnet.public_bastion.id
  route_table_id = aws_route_table.public_bastion.id
}

resource "aws_security_group" "ssh_public_bastion" {
  name        = "ssh_public_bastion"
  description = "allow inbound ssh to bastion ec2 host"
  vpc_id      = aws_vpc.rds_lambda_apig.id

  ingress {
    description = "ssh access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "pk_bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp_bastion" {
  key_name   = "bastion-rds"
  public_key = tls_private_key.pk_bastion.public_key_openssh
  
  provisioner "local-exec" {
    command = "echo '${tls_private_key.pk_bastion.private_key_pem}' > '${aws_key_pair.kp_bastion.key_name}.pem' && chmod 400 '${aws_key_pair.kp_bastion.key_name}.pem'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f '${self.key_name}.pem'"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = "true"

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"] 
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "rds_bastion" {
  subnet_id     = aws_subnet.public_bastion.id
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.nano"
  key_name      = aws_key_pair.kp_bastion.key_name
  
  vpc_security_group_ids = [aws_security_group.ssh_public_bastion.id]  

  tags = {
    Name = "rds_bastion"
  } 
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.rds_lambda_apig.id
  
  ingress {
    description = ""
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.rds_bastion.private_ip}/32"] 
  }
}
