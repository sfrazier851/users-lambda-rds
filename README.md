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
    - NOTE: for simplicity, give IAM User/Group with AdministratorAccess (policy).

7.  Setup AWS Credentials
    - ```aws configure```

8.  Confirm Configure
    - ```aws sts get-caller-identity```

-------------------------

### Run AWS CLI Automation, Test and Teardown

1.  Navigate to ```users-lambda-rds/aws_cli/private_rds``` OR ```users-lambda-rds/aws_cli/public_rds```
    - ```./deploy.sh```

2.  Wait about 5-10 minutes after script completes.

3.  Confirm Deployment
    - ```./curl_test.sh```

4.  Teardown
    - ```./destroy.sh```
