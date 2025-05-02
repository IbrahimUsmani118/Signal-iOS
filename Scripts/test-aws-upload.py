#!/usr/bin/env python3

import boto3
import hashlib
import os
import uuid
import json
from datetime import datetime
from botocore.config import Config

# AWS Configuration
S3_BUCKET = "2314823894myawsbucket"
S3_PREFIX = "images/"
DYNAMODB_TABLE = "SignalMetadata"
AWS_REGION = "us-east-1"

def create_test_image():
    """Create a test image file."""
    with open("test_image.heic", "wb") as f:
        f.write(b"Test image content")
    return "test_image.heic"

def calculate_file_hash(file_path):
    """Calculate SHA-256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def upload_to_s3(file_path, file_hash):
    """Upload file to S3 and return the S3 key."""
    session = boto3.Session()
    s3 = session.client('s3', config=Config(signature_version='s3v4'))
    file_name = os.path.basename(file_path)
    s3_key = f"{S3_PREFIX}{file_hash}__{file_name}"
    
    try:
        # Upload file to S3
        with open(file_path, 'rb') as f:
            s3.put_object(
                Bucket=S3_BUCKET,
                Key=s3_key,
                Body=f.read(),
                ContentType='image/heic'
            )
        print(f"Successfully uploaded to S3: {s3_key}")
        return s3_key
    except Exception as e:
        print(f"Error uploading to S3: {str(e)}")
        raise

def store_in_dynamodb(s3_key, file_hash, file_name):
    """Store metadata in DynamoDB."""
    session = boto3.Session()
    dynamodb = session.client('dynamodb')
    
    try:
        # Store metadata in DynamoDB
        response = dynamodb.put_item(
            TableName=DYNAMODB_TABLE,
            Item={
                'file_hash': {'S': file_hash},
                's3_key': {'S': s3_key},
                'file_name': {'S': file_name},
                'upload_timestamp': {'S': datetime.utcnow().isoformat()},
                'status': {'S': 'uploaded'}
            }
        )
        print("Successfully stored metadata in DynamoDB")
        return response
    except Exception as e:
        print(f"Error storing in DynamoDB: {str(e)}")
        raise

def main():
    try:
        # Create test image
        file_path = create_test_image()
        print(f"Created test image: {file_path}")
        
        # Calculate file hash
        file_hash = calculate_file_hash(file_path)
        print(f"File hash (signature): {file_hash}")
        
        # Upload to S3
        s3_key = upload_to_s3(file_path, file_hash)
        
        # Store metadata in DynamoDB
        store_in_dynamodb(s3_key, file_hash, os.path.basename(file_path))
        
        print("Process completed successfully!")
        
    except Exception as e:
        print(f"Process failed: {str(e)}")

if __name__ == "__main__":
    main() 