#!/bin/bash

# Exit on error
set -e

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials are not configured. Please run 'aws configure' first."
    exit 1
fi

# Create KMS key for DynamoDB encryption
echo "Creating KMS key for encryption..."
KMS_KEY_ID=$(aws kms create-key --description "Key for ImageSignatures table encryption" --query 'KeyMetadata.KeyId' --output text)
aws kms create-alias --alias-name alias/ImageSignaturesKey --target-key-id $KMS_KEY_ID

# Create DynamoDB table with encryption
echo "Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name ImageSignatures \
    --attribute-definitions \
        AttributeName=signature,AttributeType=S \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=signature,KeyType=HASH \
    --provisioned-throughput \
        ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --table-class STANDARD \
    --sse-specification Enabled=true,SSEType=KMS,KMSMasterKeyId=$KMS_KEY_ID

echo "Waiting for table to be created..."
aws dynamodb wait table-exists --table-name ImageSignatures

# Enable point-in-time recovery
echo "Enabling point-in-time recovery..."
aws dynamodb update-continuous-backups \
    --table-name ImageSignatures \
    --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true

# Create IAM policy for the application
echo "Creating IAM policy..."
cat > image-signatures-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:*:*:table/ImageSignatures"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:Encrypt",
                "kms:GenerateDataKey"
            ],
            "Resource": "arn:aws:kms:*:*:key/$KMS_KEY_ID"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name ImageSignaturesPolicy \
    --policy-document file://image-signatures-policy.json

# Set up auto-scaling
echo "Setting up auto-scaling..."
aws application-autoscaling register-scalable-target \
    --service-namespace dynamodb \
    --resource-id "table/ImageSignatures" \
    --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
    --min-capacity 5 \
    --max-capacity 50

aws application-autoscaling register-scalable-target \
    --service-namespace dynamodb \
    --resource-id "table/ImageSignatures" \
    --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
    --min-capacity 5 \
    --max-capacity 50

# Create scaling policies
aws application-autoscaling put-scaling-policy \
    --service-namespace dynamodb \
    --resource-id "table/ImageSignatures" \
    --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
    --policy-name "ImageSignaturesReadScaling" \
    --policy-type "TargetTrackingScaling" \
    --target-tracking-scaling-policy-configuration '{
        "TargetValue": 70.0,
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "DynamoDBReadCapacityUtilization"
        },
        "ScaleInCooldown": 60,
        "ScaleOutCooldown": 60
    }'

aws application-autoscaling put-scaling-policy \
    --service-namespace dynamodb \
    --resource-id "table/ImageSignatures" \
    --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
    --policy-name "ImageSignaturesWriteScaling" \
    --policy-type "TargetTrackingScaling" \
    --target-tracking-scaling-policy-configuration '{
        "TargetValue": 70.0,
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "DynamoDBWriteCapacityUtilization"
        },
        "ScaleInCooldown": 60,
        "ScaleOutCooldown": 60
    }'

echo "AWS infrastructure setup complete!"
echo "Please note the following:"
echo "1. Create an IAM user and attach the ImageSignaturesPolicy"
echo "2. Generate access keys for the IAM user"
echo "3. Set up the environment variables as described in README.md"
echo "4. KMS Key ID: $KMS_KEY_ID" 