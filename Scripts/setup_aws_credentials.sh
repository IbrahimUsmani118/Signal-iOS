#!/bin/bash

# Exit on error
set -e

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first:"
    echo "brew install awscli"
    exit 1
fi

# Try to fetch container credentials if available
if [ ! -z "$AWS_CONTAINER_CREDENTIALS_FULL_URI" ] && [ ! -z "$AWS_CONTAINER_AUTHORIZATION_TOKEN" ]; then
    echo "Fetching container credentials..."
    CREDS_JSON=$(curl -s "$AWS_CONTAINER_CREDENTIALS_FULL_URI" \
                 -H "Authorization: $AWS_CONTAINER_AUTHORIZATION_TOKEN")
    
    export AWS_ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r .AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r .SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r .Token)
else
    echo "Using local credentials..."
    # Prompt for credentials if not set
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    fi
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        read -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    fi
    if [ -z "$AWS_SESSION_TOKEN" ]; then
        read -p "AWS Session Token (optional): " AWS_SESSION_TOKEN
    fi
fi

export AWS_REGION="us-east-1"

# Configure AWS CLI
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
[ ! -z "$AWS_SESSION_TOKEN" ] && aws configure set aws_session_token "$AWS_SESSION_TOKEN"
aws configure set region "$AWS_REGION"
aws configure set output json

# Verify configuration
echo "Verifying AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials configured successfully!"
    echo "Current identity:"
    aws sts get-caller-identity
else
    echo "Failed to configure AWS credentials. Please check your input."
    exit 1
fi 