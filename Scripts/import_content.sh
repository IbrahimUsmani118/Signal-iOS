#!/bin/bash

# Exit on error
set -e

# Configuration
BUCKET_NAME="signal-content-bucket"
TABLE_NAME="ImageSignatures"
TEMP_DIR=$(mktemp -d)

# Clean up temp directory on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to calculate SHA-256 hash
calculate_hash() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        sha256sum "$file" | cut -d' ' -f1
    fi
}

# List all objects in S3 bucket
echo "Listing objects in S3 bucket..."
aws s3 ls "s3://$BUCKET_NAME" --recursive | while read -r line; do
    # Extract the key from the ls output
    key=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^[ \t]*//')
    
    if [ -z "$key" ]; then
        continue
    fi
    
    echo "Processing: $key"
    
    # Download the object
    temp_file="$TEMP_DIR/$(basename "$key")"
    aws s3 cp "s3://$BUCKET_NAME/$key" "$temp_file"
    
    # Calculate hash
    hash=$(calculate_hash "$temp_file")
    echo "Hash: $hash"
    
    # Store in DynamoDB
    aws dynamodb put-item \
        --table-name "$TABLE_NAME" \
        --item "{
            \"signature\": {\"S\": \"$hash\"},
            \"timestamp\": {\"N\": \"$(date +%s)\"},
            \"s3_key\": {\"S\": \"$key\"}
        }"
    
    echo "Successfully processed: $key"
    rm -f "$temp_file"
done

echo "Import completed successfully" 