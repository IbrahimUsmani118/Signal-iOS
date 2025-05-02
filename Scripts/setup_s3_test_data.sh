#!/bin/bash

# Exit on error
set -e

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Create S3 bucket
BUCKET_NAME="signal-content-bucket"
REGION="us-east-1"

echo "Creating S3 bucket..."
if [ "$REGION" == "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION
else
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION \
        --create-bucket-configuration LocationConstraint=$REGION
fi

# Enable versioning
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

# Enable encryption
echo "Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'

# Create test directory
echo "Creating test directory..."
mkdir -p test_data

# Generate test files
echo "Generating test files..."
for i in {1..5}; do
    dd if=/dev/urandom of=test_data/test_file_$i.bin bs=1M count=1
done

# Upload test files
echo "Uploading test files..."
aws s3 sync test_data/ s3://$BUCKET_NAME/test_data/

# Clean up
echo "Cleaning up..."
rm -rf test_data

echo "S3 setup complete!"
echo "Bucket name: $BUCKET_NAME"
echo "Region: $REGION" 