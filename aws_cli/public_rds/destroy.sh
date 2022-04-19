#!/bin/bash

AWS_REGION=us-east-1
VPC_NAME=rds-lambda-apig

API_ID=$(aws apigateway get-rest-apis \
  --query 'items[?name==`lambdaRds`].[id]' --output text)

# Get VPC ID by Tag
VPC_ID=$(aws ec2 describe-vpcs \
  --filter Name=tag:Name,Values=$VPC_NAME \
  --query Vpcs[].VpcId --output text)

# Delete Api Gateway resources
echo "Deleting Api Gateway resources..."
aws apigateway delete-rest-api \
  --rest-api-id $API_ID

# Detach policy from IAM role lambda-vpc-access
echo "Detaching policy from lambda-vpc-access role..."
aws iam detach-role-policy \
  --role-name lambda-vpc-access \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
echo "  policy detached."

# Delete IAM role lambda-vpc-access
echo "Deleting IAM role lambda-vpc-access..."
aws iam delete-role \
  --role-name lambda-vpc-access 
echo "  lambda-vpc-access role deleted."

# Disconnect Lambda function from VPC
echo "Disconnecting lambda function from VPC..."
aws lambda update-function-configuration \
  --function-name lambdaRdsQuery \
  --vpc-config SubnetIds=[],SecurityGroupIds=[] \
  --no-cli-pager

# Delete Lambda function 
echo "Deleting lambda function..."
aws lambda delete-function \
  --function-name lambdaRdsQuery

# Delete RDS instance
echo "Deleting RDS DB instance..."
aws rds delete-db-instance \
  --db-instance-identifier lambdaRDS \
  --skip-final-snapshot \
  --delete-automated-backups \
  --no-cli-pager

# Wait for RDS instance to be deleted
echo "Waiting for RDS DB instance to be deleted..."
aws rds wait db-instance-deleted \
  --db-instance-identifier lambdaRDS

# Delete Db Subnet Group
echo "Deleting Db Subnet Group lambdaRdsSubnetGroup..."
aws rds delete-db-subnet-group \
  --db-subnet-group-name lambdaRdsSubnetGroup
echo "  db subnet group deleted."

# Check VPC state, available or not
vpc_state=$(aws ec2 describe-vpcs \
    --vpc-ids "${VPC_ID}" \
    --query 'Vpcs[].State' \
    --region "${AWS_REGION}" \
    --output text)

if [ ${vpc_state} != 'available' ]; then
    echo "The VPC ${VPC_ID} is not available."
    exit 1
fi

echo -n "=== Deleting the resources in VPC ${VPC_ID} in ${AWS_REGION}..."

# Delete NIC
echo "Deleting Network Interface ..."
for nic in $(aws ec2 describe-network-interfaces \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    detach Network Interface of $nic"
    attachment=$(aws ec2 describe-network-interfaces \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
                  'Name=network-interface-id,Values='${nic} \
        --query 'NetworkInterfaces[].Attachment.AttachmentId' \
        --region "${AWS_REGION}" \
        --output text)

    if [ ! -z ${attachment} ]; then
        echo "network attachment is ${attachment}"
        aws ec2 detach-network-interface \
            --attachment-id "${attachment}" \
            --region "${AWS_REGION}" >/dev/null

        # we need a waiter here
        sleep 1
    fi

    echo "    delete Network Interface of $nic"
    aws ec2 delete-network-interface \
        --network-interface-id "${nic}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete Security Group
echo "Deleting Security Groups ..."
for sg in $(aws ec2 describe-security-groups \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'SecurityGroups[].GroupId' \
    --region "${AWS_REGION}" \
    --output text)
do
    # Check for default security group
    sg_name=$(aws ec2 describe-security-groups \
        --group-ids "${sg}" \
        --query 'SecurityGroups[].GroupName' \
        --region "${AWS_REGION}" \
        --output text)
    # Ignore default security group
    if [ "$sg_name" = 'default' ] || [ "$sg_name" = 'Default' ]; then
        continue
    fi

    echo "    delete Security group $sg"
    aws ec2 delete-security-group \
        --group-id "${sg}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete IGW
echo "Deleting Internet Gateway ..."
for igw in $(aws ec2 describe-internet-gateways \
    --filters 'Name=attachment.vpc-id,Values='${VPC_ID} \
    --query 'InternetGateways[].InternetGatewayId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    detach IGW $igw"
    aws ec2 detach-internet-gateway \
        --internet-gateway-id "${igw}" \
        --vpc-id "${VPC_ID}" \
        --region "${AWS_REGION}" > /dev/null

    # we need a waiter here
    sleep 1

    echo "    delete IGW $igw"
    aws ec2 delete-internet-gateway \
        --internet-gateway-id "${igw}" \
        --region "${AWS_REGION}" > /dev/null
done

# Deleting Subnet(s)
echo "Deleting of Subnet(s) ..."
for subnet in $(aws ec2 describe-subnets \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'Subnets[].SubnetId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    delete subnet $subnet"
    aws ec2 delete-subnet \
        --subnet-id "${subnet}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete Route Table
echo "Deleting Route Table ..."
for routetable in $(aws ec2 describe-route-tables \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'RouteTables[].RouteTableId' \
    --output text --region "${AWS_REGION}")
do
    # Check for main route table
    main_table=$(aws ec2 describe-route-tables \
        --route-table-ids "${routetable}" \
        --query 'RouteTables[].Associations[].Main' \
        --region "${AWS_REGION}" \
        --output text)

    # Ignore main route table
    if [ "$main_table" = 'True' ] || [ "$main_table" = 'true' ]; then
        continue
    fi

    echo "    delete Route Table $routetable"
    aws ec2 delete-route-table \
        --route-table-id "${routetable}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete VPC
echo -n "Deleting VPC ${VPC_ID}"
aws ec2 delete-vpc \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" \
    --output text

echo ""
echo "Done."
