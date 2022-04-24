# Terraform Settings Block
terraform {
  # Terraform Version
  required_version = "~> 0.14.6"
  required_providers {
    # AWS Provider
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.31.0"
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

  egress {
    description = "internet access"
    from_port        = 0
    to_port          = 0
    protocol         = -1
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
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

  user_data = <<EOF
#!/bin/bash

apt update
apt upgrade --yes
apt install --yes mysql-client

/home/ubuntu/configure_db.sh
rm /home/ubuntu/configure_db.sh

EOF

  provisioner "file" {
    source      = "db.sql"
    destination = "/home/ubuntu/db.sql"
  }

  provisioner "file" {
    source      = "configure_db.sh"
    destination = "/home/ubuntu/configure_db.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/configure_db.sh",
    ]
  }

  connection {
   host        = coalesce(self.public_ip, self.private_ip)
   agent       = true
   type        = "ssh"
   user        = "ubuntu"
   private_key = file("${aws_key_pair.kp_bastion.key_name}.pem")
  }

  tags = {
    Name = "rds_bastion"
  }

  depends_on = [local_file.configure_db_sh]
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

resource "aws_db_subnet_group" "lambda_rds" {
  name        = "lambda-rds"
  description = "DB subnet group for lambda-rds-apig (Terraform Managed)"

  subnet_ids  = [aws_subnet.private_rds1.id, aws_subnet.private_rds2.id]

  # tags = {
  #   Name = "Private RDS Subnet Group"
  # }
}

resource "aws_db_instance" "private_rds" {
  db_name              = "lambda_rds"
  engine               = "mysql"
  instance_class       = "db.t2.micro"
  allocated_storage    = 5
  skip_final_snapshot  = true
  username             = "admin"
  password             = "supersecret"

  db_subnet_group_name = aws_db_subnet_group.lambda_rds.name
}

resource "local_file" "configure_db_sh" {
  content = <<EOF
#!/bin/bash
mysql -h ${aws_db_instance.private_rds.address} --user=${aws_db_instance.private_rds.username} --password=${aws_db_instance.private_rds.password} < /home/ubuntu/db.sql
EOF
  filename = "configure_db.sh"
}

resource "local_file" "rds_host_py" {
  content  = <<EOF
# uri_string = '<db-instance-name>.<account-region-hash>.<region-id>.rds.amazonaws.com'
uri_string = '${aws_db_instance.private_rds.address}'
EOF
  filename = "deploy/rds_host.py"
}

resource "local_file" "rds_config_py" {
  content  = <<EOF
# config file containing credentials for RDS MySQL instance
db_username = '${aws_db_instance.private_rds.username}'
db_password = '${aws_db_instance.private_rds.password}'
db_name = 'test'
EOF
  filename = "deploy/rds_config.py"

  provisioner "local-exec" {
    command = <<EOF
python3 -m pip install pymysql -t ./deploy
EOF
  }

  depends_on = [local_file.rds_host_py]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "deploy"
  output_path = "deploy.zip"

  depends_on = [local_file.rds_config_py]
}

resource "aws_iam_role" "lambda_vpc_access" {
  name = "lambda-vpc-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  #tags = {
  #  tag-key = "tag-value"
  #}
}

resource "aws_iam_policy_attachment" "lambda_vpc_access" {
  name       = "lambda_vpc_access"
  roles      = [aws_iam_role.lambda_vpc_access.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "rds_lambda" {
  # If the file is not in the current working directory you will need to include a
  #  path.module in the filename.
  filename      = "deploy.zip"
  function_name = "rds_query"
  role          = aws_iam_role.lambda_vpc_access.arn
  handler       = "app.handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  #source_code_hash = filebase64sha256("deploy.zip")
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime = "python3.8"

  vpc_config {
    # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
    subnet_ids         = [aws_subnet.private_rds1.id, aws_subnet.private_rds2.id]
    security_group_ids = [aws_default_security_group.default.id]
  }

  #environment {
  #  variables = {
  #    foo = "bar"
  #  }
  #}
}

resource "null_resource" "assign_default_sg" {
  triggers = {
    sg       = aws_default_security_group.default.id
    vpc     = aws_vpc.rds_lambda_apig.id
  }

  provisioner "local-exec" {
    when    = destroy
    command = "/bin/bash ./update-lambda-sg.sh ${self.triggers.vpc} ${self.triggers.sg}"
  }
}

resource "null_resource" "delete_deploy_zip" {

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
rm deploy.zip && touch empty && zip deploy.zip empty && zip -d deploy.zip empty && rm empty
EOF
  }
}
