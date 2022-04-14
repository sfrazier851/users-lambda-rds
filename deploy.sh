#!/bin/bash

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
VPC_NAME="rds-lambda-apig"
VPC_CIDR="10.0.0.0/16"
# private subnets and AZs for RDS and lambda
SUBNET_PRIVATE_CIDR1="10.0.1.0/24"
SUBNET_PRIVATE_CIDR2="10.0.2.0/24"
SUBNET_PRIVATE_AZ1="us-east-1a"
SUBNET_PRIVATE_AZ2="us-east-1b"
# public subnet and az for bastion host
SUBNET_PUBLIC_CIDR="10.0.3.0/24"
SUBNET_PUBLIC_AZ="us-east-1a"
#MY_IP_ADDRESS=$(curl -s https://ipv4.icanhazip.com)/32
MY_IP_ADDRESS=0.0.0.0/0

# Create VPC
echo "Creating VPC in specified region..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --query 'Vpc.{VpcId:VpcId}' \
  --output text \
  --region $AWS_REGION)
echo "  VPC ID '$VPC_ID' CREATED in '$AWS_REGION' region."

# Add Name tag to VPC
aws ec2 create-tags \
  --resources $VPC_ID \
  --tags "Key=Name,Value=$VPC_NAME" \
  --region $AWS_REGION
echo "  VPC ID: '$VPC_ID' with tag: '$VPC_NAME'."

# Enable dns hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames \

# Enable dns support
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support

# Create private subnet 1
echo "Creating private subnet 1..."
SUBNET_PRIVATE_ID1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PRIVATE_CIDR1 \
  --availability-zone $SUBNET_PRIVATE_AZ1 \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PRIVATE_ID1' CREATED in '$SUBNET_PRIVATE_AZ1'" \
  "Availability Zone."

# Create private Subnet 2
echo "Creating private subnet 2..."
SUBNET_PRIVATE_ID2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PRIVATE_CIDR2 \
  --availability-zone $SUBNET_PRIVATE_AZ2 \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PRIVATE_ID2' CREATED in '$SUBNET_PRIVATE_AZ2'" \
  "Availability Zone."

# Create public (bastion) subnet
echo "Creating public (bastion) subnet..."
SUBNET_PUBLIC_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PUBLIC_CIDR \
  --availability-zone $SUBNET_PUBLIC_AZ \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PUBLIC_ID' CREATED in '$SUBNET_PUBLIC_AZ'" \
  "Availability Zone."

# Create Internet gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' \
  --output text \
  --region $AWS_REGION)
echo "  Internet Gateway ID '$IGW_ID' CREATED."

# Attach Internet gateway to your VPC
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID \
  --region $AWS_REGION
echo "  Internet Gateway ID '$IGW_ID' ATTACHED to VPC ID '$VPC_ID'."

# Create public subnet Route Table
echo "Creating (public bastion subnet) Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --query 'RouteTable.{RouteTableId:RouteTableId}' \
  --output text \
  --region $AWS_REGION)
echo "  Route Table ID '$ROUTE_TABLE_ID' CREATED."

# Create route to Internet Gateway
RESULT=$(aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $AWS_REGION)
echo "  Route to '0.0.0.0/0' via Internet Gateway ID '$IGW_ID' ADDED to" \
  "Route Table ID '$ROUTE_TABLE_ID'."

# Associate Public Subnet with Route Table
RESULT=$(aws ec2 associate-route-table  \
  --subnet-id $SUBNET_PUBLIC_ID \
  --route-table-id $ROUTE_TABLE_ID \
  --region $AWS_REGION)
echo "  Public Subnet ID '$SUBNET_PUBLIC_ID' ASSOCIATED with Route Table ID" \
  "'$ROUTE_TABLE_ID'."

# Automatically give instances launched in subnet a public ip
aws ec2 modify-subnet-attribute \
  --subnet-id $SUBNET_PUBLIC_ID \
  --map-public-ip-on-launch
  
# Create Security Group for the bastion host
BASTION_SG_ID=$(aws ec2 create-security-group \
  --group-name bastion-sg \
  --description "security group for bastion host" \
  --vpc-id $VPC_ID \
  --region $AWS_REGION \
  --query 'GroupId' --output text)

# Add security group rule for inbound ssh access from my_ip_address
aws ec2 authorize-security-group-ingress \
  --group-id $BASTION_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP_ADDRESS \
  --region $AWS_REGION

# create ec2 key-pair for bastion
aws ec2 create-key-pair \
  --key-name bastion-rds \
  --query "KeyMaterial" \
  --output text \
  --region $AWS_REGION > ./bastion-rds.pem

# set permissions for private key
chmod 400 bastion-rds.pem

# Run ec2 (bastion) instance
echo "Creating bastion ec2 instance..."
aws ec2 run-instances \
  --image-id ami-0fd63e471b04e22d0 \
  --count 1 \
  --instance-type t2.nano \
  --key-name bastion-rds \
  --security-group-ids $BASTION_SG_ID \
  --subnet-id $SUBNET_PUBLIC_ID \
  --region $AWS_REGION \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion-rds}]' \
  --user-data file://userdata.sh \
  --no-cli-pager

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bastion-rds" "Name=instance-state-name,Values=pending" \
  --query "Reservations[].Instances[].InstanceId" --output text)
  
echo $INSTANCE_ID

# Wait for bastion instance to be running
echo "Waiting for bastion instance to be running..."
aws ec2 wait instance-running \
  --instance-ids $INSTANCE_ID
echo "  instance running."

PRIVATE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bastion-rds" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PrivateIpAddress" --output text)

echo $PRIVATE_IP

PUBLIC_DNS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bastion-rds" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PublicDnsName" --output text)

echo $PUBLIC_DNS
echo $MY_IP_ADDRESS

