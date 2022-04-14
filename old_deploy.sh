#!/bin/bash

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
VPC_NAME="rds-lambda-apig"
VPC_CIDR="10.0.0.0/16"
SUBNET_PUBLIC_CIDR1="10.0.1.0/24"
SUBNET_PUBLIC_CIDR2="10.0.2.0/24"
SUBNET_PUBLIC_AZ1="us-east-1a"
SUBNET_PUBLIC_AZ2="us-east-1b"
MY_IP_ADDRESS=$(curl https://icanhazip.com)


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

# Create public Subnet 1
echo "Creating public Subnet 1..."
SUBNET_PUBLIC_ID1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PUBLIC_CIDR1 \
  --availability-zone $SUBNET_PUBLIC_AZ1 \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PUBLIC_ID1' CREATED in '$SUBNET_PUBLIC_AZ1'" \
  "Availability Zone."

# Create public Subnet 2
echo "Creating public Subnet 2..."
SUBNET_PUBLIC_ID2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PUBLIC_CIDR2 \
  --availability-zone $SUBNET_PUBLIC_AZ2 \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PUBLIC_ID2' CREATED in '$SUBNET_PUBLIC_AZ2'" \
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

# Create Route Table
echo "Creating Route Table..."
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
  --subnet-id $SUBNET_PUBLIC_ID1 \
  --route-table-id $ROUTE_TABLE_ID \
  --region $AWS_REGION)
echo "  Public Subnet ID '$SUBNET_PUBLIC_ID1' ASSOCIATED with Route Table ID" \
  "'$ROUTE_TABLE_ID'."

# Associate Public Subnet with Route Table
RESULT=$(aws ec2 associate-route-table  \
  --subnet-id $SUBNET_PUBLIC_ID2 \
  --route-table-id $ROUTE_TABLE_ID \
  --region $AWS_REGION)
echo "  Public Subnet ID '$SUBNET_PUBLIC_ID2' ASSOCIATED with Route Table ID" \
  "'$ROUTE_TABLE_ID'."

# Get Default Security Group
echo "Getting Default Security Group..."
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --filter Name=vpc-id,Values=$VPC_ID Name=group-name,Values=default \
  --query 'SecurityGroups[*].[GroupId]' --output text)
echo "  Security Group ID: '$SECURITY_GROUP_ID'."

# Adding Security Group Rule for connecting remotely to RDS MySQL instance..."
echo "Adding Security Group (ingress) Rule for connecting remotely to RDS MySQL instance..."
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp --port 3306 \
  --cidr $MY_IP_ADDRESS/32
echo "  Created (ingress) Rule for RDS access from IP: '$MY_IP_ADDRESS'."

# Create IAM role for lambda
echo "Creating IAM role for lambda function to access RDS instance..."
aws iam create-role \
  --role-name lambda-vpc-access \
  --assume-role-policy-document file://lambda-trust-policy.json \
  --no-cli-pager
echo "  Created lambda-vpc-access role."

# Attach IAM policy to lambda-vpc-access role
echo "Attaching managed policy to lambda-vpc-access role..."
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole \
  --role-name lambda-vpc-access
echo "  Attached VPCAccessExecutionRole policy to lambda-vpc-access role."

# Verify IAM policy is attached to role
echo "Verifying lambda-vpc-access role has AWSLmbdaVPCAccessExecutionRole attached..."
aws iam list-attached-role-policies --role-name lambda-vpc-access

# Create DB Subnet Group for RDS MySQL instance
echo "Creating DB Subnet Group for RDS instance..."
aws rds create-db-subnet-group \
  --db-subnet-group-name lambdaRdsSubnetGroup \
  --db-subnet-group-description "DB subnet group for lambda rds apig" \
  --subnet-ids "$SUBNET_PUBLIC_ID1" "$SUBNET_PUBLIC_ID2" \
  --no-cli-pager
echo "  subnet group created."

# Create RDS instance
echo "Creating RDS MySQL instance..."
aws rds create-db-instance \
  --engine MySQL \
  --db-instance-identifier lambdaRDS \
  --db-instance-class db.t2.micro \
  --publicly-accessible \
  --allocated-storage 5 \
  --backup-retention-period 3 \
  --publicly-accessible \
  --vpc-security-group-ids "$SECURITY_GROUP_ID" \
  --db-subnet-group-name lambdaRdsSubnetGroup \
  --master-username admin \
  --master-user-password supersecret \
  --no-cli-pager
echo "  RDS MySQL instance created."

# Wait for RDS MySQL instance ready (need host uri string)
echo "Waiting for RDS MySQL instance ready..."
aws rds wait db-instance-available \
  --db-instance-identifier lambdaRDS

# Run SQL script on RDS instance
echo "Running SQL script against RDS instance..."
mysqlsh --mysql admin@lambdards.cmowfshfbd4y.us-east-1.rds.amazonaws.com --file db.sql

# Get RDS endpoint address (instance host uri)
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier lambdaRDS \
  --query DBInstances[*].Endpoint.Address --output text)

# Get IAM role arn (for Lambda function)
ROLE_ARN=$(aws iam get-role --role-name lambda-vpc-role  --query 'Role.Arn' --output text) 

# Write rds uri endpoint to rds_host.py
echo "uri_string = \"$RDS_ENDPOINT\"" > ./deploy/rds_host.py

# Prepare Lambda function zip file
echo "Preparing Lambda function zip file..."
python3 -m pip install pymysql -t ./deploy
rm deploy.zip
cd deploy && zip -r ../deploy.zip ./* && cd ..

# Create Lambda function
echo "Creating Lambda function..."
aws lambda create-function \
  --function-name lambdaRdsQuery \
  --runtime python3.8 \
  --zip-file fileb://deploy.zip \
  --handler app.handler \
  --role $ROLE_ARN \
  --vpc-config SubnetIds=$SUBNET_PUBLIC_ID1,$SUBNET_PUBLIC_ID2,SecurityGroupIds=$SECURITY_GROUP_ID \
  --no-cli-pager

# Get Lambda function Arn
LAMBDA_ARN=$(aws lambda get-function \
  --function-name lambdaRdsQuery \
  --query Configuration.FunctionArn \
  --output text)

# Create RestApi (Api Gateway)
echo "Creating Api Gateway Rest Api..."
API_ID=$(aws apigateway create-rest-api \
  --name 'lambdaRds' \
  --description 'users lambda rds' \
  --region $AWS_REGION \
  --endpoint-configuration '{ "types": ["REGIONAL"] }' \
  --query id --output text)

# Get root resource id
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID --query 'items[0].id' \
  --output text)

# Create Users resource
echo "Creating users resource..."
USERS_RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_RESOURCE_ID \
  --path-part users \
  --query id --output text)

# Create GET method on users resource
echo "Creating GET method on users resource..."
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE \
  --region $AWS_REGION

#echo "arn:aws:apigateway:$AWS_REGION:lambda:path//2015-03-31/functions/$LAMBDA_ARN/invocations"

# Set/create the integration type on the GET method for users resource
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$AWS_REGION:lambda:path//2015-03-31/functions/$LAMBDA_ARN/invocations"

# Create POST method on users resource
echo "Creating POST method on users resource..."
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE \
  --region $AWS_REGION

# Set/create the integration type on the POST method for users resource
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $USERS_RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$AWS_REGION:lambda:path//2015-03-31/functions/$LAMBDA_ARN/invocations"

# Create deployment with stage
echo "Creating deployment and stage v1..."
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --region $AWS_REGION \
  --stage-name v1

# Give api gateway (stage/method/resource) permission to call lambda function
echo "Setting permissions for Api Gateway GET method (v1/GET/users) to call lambda..."
aws lambda add-permission \
  --function-name lambdaRdsQuery \
  --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/v1/GET/users" \
  --principal apigateway.amazonaws.com \
  --statement-id "API_Gateway_can_GET_users_lambdaRdsQuery" \
  --action lambda:InvokeFunction

# Give api gateway (stage/method/resource) permission to call lambda function
echo "Setting permissions for Api Gateway POST method (v1/POST/users) to call lambda..."
aws lambda add-permission \
  --function-name lambdaRdsQuery \
  --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/v1/POST/users" \
  --principal apigateway.amazonaws.com \
  --statement-id "API_Gateway_can_POST_users_lambdaRdsQuery" \
  --action lambda:InvokeFunction

