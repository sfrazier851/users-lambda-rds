# users-lambda-rds
Spin up a serverless REST API. Uses API Gateway, Lambda and RDS (MySQL).

-------------------------

### Set up Environment
###### NOTE: assuming macOS environment

1. Install Python3
    - http://python.org/ftp/python/3.7.9/python-3.7.9-macosx10.9.pkg

2. Install awscli via pip3 & add awscli to PATH
    - ```pip3 install awscli --upgrade --user```
    - ```export PATH=~/.local/bin:~/Library/Python/3.7/bin:$PATH```

3.  Confirm Install
    - ```aws --version```

4.  Create AWS Account

6.  Download AWS Access Key ID and AWS Secret Access Key
    - NOTE: for simplicity, give IAM User/Group AdministratorAccess (policy).

7.  Setup AWS Credentials
    - ```aws configure```

8.  Confirm Configure
    - ```aws sts get-caller-identity```

9.  Download Terraform, Unzip & Add to Path
    - https://releases.hashicorp.com/terraform/0.14.11/terraform_0.14.11_darwin_amd64.zip
    - ```unzip terraform_0.14.11_darwin_amd64.zip```
    - ```mv terraform /usr/local/bin/terraform14```

10. Confirm Install
    - ```terraform14 --version```

-------------------------

### Run AWS CLI Automation, Test and Teardown
###### NOTE: ```users-lambda-rds/aws_cli/public_rds``` requires that ```mysqlsh``` is installed on local machine.

1.  Navigate to ```users-lambda-rds/aws_cli/private_rds```
    - ```./deploy.sh```

2.  Wait about 8-12 minutes after script completes.

3.  Confirm Deployment
    - ```./curl_test.sh```

4.  Teardown
    - ```./destroy.sh```

-------------------------

### Run Terraform Automation, Test and Teardown
###### NOTE: create S3 bucket for remote state storage and dynamodb table for state locking:
   - ```aws s3 mb s3://user-lambda-rds-tfstate```
   - ```aws dynamodb create-table --table-name terraform-dev-state-table --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1```

1.  Navigate to ```users-lambda-rds/terraform```
    - ```terraform14 init```
    - ```terrafrom14 plan```
    - ```terraform14 apply```

2.  Wait about 8-12 minutes after automation completes.

3.  Confirm Deployment
    - ```./curl_test.sh```

4.  Teardown
    - ```terraform14 destroy```

5.  Delete S3 bucket (remote state storage) and Dynamodb Table (State Locking) 
    - ```aws s3 rb --force s3://user-lambda-rds-tfstate```
    - ```aws dynamodb delete-table --table-name terraform-dev-state-table```
