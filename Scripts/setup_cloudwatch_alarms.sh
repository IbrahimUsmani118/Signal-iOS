#!/bin/bash

# Exit on error
set -e

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Create CloudWatch alarms for DynamoDB
echo "Creating CloudWatch alarms..."

# Alarm for high read capacity
aws cloudwatch put-metric-alarm \
    --alarm-name "ImageSignatures-HighReadCapacity" \
    --alarm-description "Alarm when DynamoDB read capacity exceeds 80%" \
    --metric-name "ConsumedReadCapacityUnits" \
    --namespace "AWS/DynamoDB" \
    --statistic "Sum" \
    --period 300 \
    --threshold 4 \
    --comparison-operator "GreaterThanThreshold" \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:us-east-1:$(aws sts get-caller-identity --query Account --output text):ImageSignaturesAlerts" \
    --dimensions "Name=TableName,Value=ImageSignatures"

# Alarm for high write capacity
aws cloudwatch put-metric-alarm \
    --alarm-name "ImageSignatures-HighWriteCapacity" \
    --alarm-description "Alarm when DynamoDB write capacity exceeds 80%" \
    --metric-name "ConsumedWriteCapacityUnits" \
    --namespace "AWS/DynamoDB" \
    --statistic "Sum" \
    --period 300 \
    --threshold 4 \
    --comparison-operator "GreaterThanThreshold" \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:us-east-1:$(aws sts get-caller-identity --query Account --output text):ImageSignaturesAlerts" \
    --dimensions "Name=TableName,Value=ImageSignatures"

# Create SNS topic for alerts
aws sns create-topic --name "ImageSignaturesAlerts"

echo "CloudWatch alarms setup complete!" 