#!/bin/bash

API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`lambda_rds`].id' --output text)
AWS_REGION=us-east-1


curl -v -X POST \
  "https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/v1/users" \
  -H 'content-type: application/json' \
  -d '{ "email": "jim876@gmail.com", "password": "987Pass!" }'
