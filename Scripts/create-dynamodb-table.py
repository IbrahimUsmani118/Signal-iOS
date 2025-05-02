#!/usr/bin/env python3

import boto3
from botocore.exceptions import ClientError

def create_file_metadata_table(table_name):
    dynamodb = boto3.client('dynamodb')
    
    try:
        table = dynamodb.create_table(
            TableName=table_name,
            KeySchema=[
                {
                    'AttributeName': 'file_hash',
                    'KeyType': 'HASH'  # Partition key
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'file_hash',
                    'AttributeType': 'S'  # String
                }
            ],
            ProvisionedThroughput={
                'ReadCapacityUnits': 5,
                'WriteCapacityUnits': 5
            },
            Tags=[
                {
                    'Key': 'Project',
                    'Value': 'Signal-iOS'
                }
            ]
        )
        print(f"Creating table {table_name}...")
        # Wait for the table to be created
        dynamodb.get_waiter('table_exists').wait(TableName=table_name)
        print(f"Table {table_name} created successfully!")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            print(f"Table {table_name} already exists")
            return True
        else:
            print(f"Error creating table: {str(e)}")
            return False

if __name__ == "__main__":
    TABLE_NAME = "signal-file-metadata"
    create_file_metadata_table(TABLE_NAME) 