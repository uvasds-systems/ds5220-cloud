# BYOC Lambda

## Container Image

References:
- [`app.py`](app.py)
- [`Dockerfile`](Dockerfile)
- [`requirements.txt`](requirements.txt)
  
```
# Simple build
docker build --platform linux/amd64 --provenance=false -t my-lambda-fn .

# Authenticate
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  440848399208.dkr.ecr.us-east-1.amazonaws.com

# Tag (can be done with build)
docker tag my-lambda-fn:latest \
  440848399208.dkr.ecr.us-east-1.amazonaws.com/my-lambda-fn:latest

# Create repo:
aws ecr create-repository --repository-name my-lambda-fn

# Push
docker push 440848399208.dkr.ecr.us-east-1.amazonaws.com/my-lambda-fn:latest
```

> **Note:** The `--platform linux/amd64` flag ensures the image targets Lambda's default
> x86_64 runtime (important if building on Apple Silicon). The `--provenance=false` flag
> prevents Docker BuildKit from producing OCI image manifests that Lambda does not support.
> 
> It is possible to build `arm64` container images and run them in AWS Lambda. See the 
> `--architecture` flag in the [Create Function](#create-the-lambda-function) section.


## Trust

Create a `trust-policy.json` file that allows Lambda to assume the role:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

```
# Create the IAM execution role for Lambda
aws iam create-role \
  --role-name lambda-execution-role \
  --assume-role-policy-document file://trust-policy.json

# Attach basic execution permissions (CloudWatch logging)
aws iam attach-role-policy \
  --role-name lambda-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

## IAM Permissions

Create a `lambda-s3-policy.json` file that grants S3 GetObject access to a specific bucket
and permission to list all buckets:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::s3-linecount/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListAllMyBuckets"
      ],
      "Resource": "arn:aws:s3:::*"
    }
  ]
}
```

```
# Create the custom policy
aws iam create-policy \
  --policy-name lambda-s3-linecount-policy \
  --policy-document file://lambda-s3-policy.json

# Attach the custom policy to the execution role
aws iam attach-role-policy \
  --role-name lambda-execution-role \
  --policy-arn arn:aws:iam::440848399208:policy/lambda-s3-linecount-policy

# Update the policy if you modify the local JSON file
aws iam create-policy-version \
  --policy-arn arn:aws:iam::440848399208:policy/lambda-s3-linecount-policy \
  --policy-document file://lambda-s3-policy.json \
  --set-as-default
```

## Create the Lambda Function

```
aws lambda create-function \
  --function-name my-lambda-fn \
  # --architectures arm64 \
  --package-type Image \
  --timeout 30 \
  --code ImageUri=440848399208.dkr.ecr.us-east-1.amazonaws.com/my-lambda-fn:latest \
  --role arn:aws:iam::440848399208:role/lambda-execution-role
```

> **Note:** The `--timeout 30` flag sets the function timeout to 30 seconds. The default
> is 3 seconds, which is too short for ECR-based Lambda functions — container cold starts
> (pulling the image, initializing the runtime, importing libraries) can easily exceed 3
> seconds and cause spurious timeouts.

To update the timeout on an existing Lambda function:
```
aws lambda update-function-configuration \
  --function-name my-lambda-fn \
  --timeout 30
```

> **Note:** `boto3` calls like `s3.list_buckets()` return Python `datetime` objects (e.g.
> in `CreationDate`), which are not JSON-serializable. Convert them with `.isoformat()`
> before returning from your handler, or Lambda will fail to serialize the response.

## Run and Test

```
aws lambda invoke --function-name my-lambda-fn output.json
cat output.json
```

After pushing a new container image to ECR, force Lambda to pull the latest image:
```
aws lambda update-function-code \
  --function-name my-lambda-fn \
  --image-uri 440848399208.dkr.ecr.us-east-1.amazonaws.com/my-lambda-fn:latest
```

## Deploy and Tear Down Using CloudFormation

Assume you have a container image built and pushed to ECR, and that you know the IAM policy statements you would like for your BYOC Lambda function. You can create the policy, role, and Lambda function itself using CloudFormation.

See [`template.yaml`](template.yaml) for sample code.

To deploy this template from the CLI:
```
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name byoc-s3-list \
  --capabilities CAPABILITY_NAMED_IAM                                                             
```

The `CAPABILITY_NAMED_IAM` flag is required because the template creates a named IAM role. 

Teardown the template:
```
aws cloudformation delete-stack --stack-name byoc-s3-list
```
