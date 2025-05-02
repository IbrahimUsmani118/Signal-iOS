#!/usr/bin/env bash

=============================================================================

aws_verify.sh

A CLI utility to verify AWS connectivity for S3, DynamoDB, and API Gateway.



Usage:

./aws_verify.sh [OPTIONS]



Options:

-t, --tests   Comma-separated list of tests to run: credentials,s3,dynamo,api,all

-b, --bucket  S3 bucket name for S3 tests and import

-k, --key     S3 object key for upload/download test

-T, --table   DynamoDB table name for table-status test

-e, --endpoint  API Gateway endpoint URL for connectivity test

-h, --help    Show this help message and exit



Exit codes:

0  All tests passed (or no tests selected)

1  Usage or argument error

2  Credential validation failure

3  S3 test failure

4  DynamoDB test failure

5  API Gateway test failure

=============================================================================

ANSI color codes

RED="\033[0;31m"    # Error
GREEN="\033[0;32m"  # Success
YELLOW="\033[0;33m" # Warning
BLUE="\033[0;34m"   # Info
RESET="\033[0m"

Summary report array

declare -A REPORT

Functions

function usage() {
grep '^#' "$0" | sed -e 's/# ?//'
exit 1
}

function log() { echo -e "${BLUE}[INFO]${RESET} $1"; }
function success() { echo -e "${GREEN}[PASS]${RESET} $1"; REPORT["$1"]="PASS"; }
function warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; REPORT["$1"]="WARN"; }
function error() { echo -e "${RED}[FAIL]${RESET} $1"; REPORT["$1"]="FAIL"; }

function test_credentials() {
local label="AWS Credentials"
log "Validating AWS credentials..."
if aws sts get-caller-identity &>/dev/null; then
success "$label"
else
error "$label"; exit 2
fi
}

function test_s3() {
local label="S3 Upload/Download"
if [[ -z "$BUCKET" || -z "$KEY" ]]; then
error "$label: --bucket and --key required"; exit 3
fi
log "Testing S3 upload to s3://$BUCKET/$KEY..."
echo "hello-aws" > /tmp/aws_verify_test.txt
if aws s3 cp /tmp/aws_verify_test.txt s3://$BUCKET/$KEY &>/dev/null; then
success "$label upload"
else
error "$label upload"; exit 3
fi
log "Testing S3 download from s3://$BUCKET/$KEY..."
if aws s3 cp s3://$BUCKET/$KEY /tmp/aws_verify_test_down.txt &>/dev/null && grep -q "hello-aws" /tmp/aws_verify_test_down.txt; then
success "$label download"
else
error "$label download"; exit 3
fi
}

function test_dynamo() {
local label="DynamoDB Table Status"
if [[ -z "$TABLE" ]]; then
error "$label: --table required"; exit 4
fi
log "Describing DynamoDB table $TABLE..."
if aws dynamodb describe-table --table-name "$TABLE" &>/dev/null; then
success "$label"
else
error "$label"; exit 4
fi
}

function test_api() {
local label="API Gateway"
if [[ -z "$ENDPOINT" ]]; then
error "$label: --endpoint required"; exit 5
fi
log "Calling API endpoint $ENDPOINT..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT")
if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
success "$label ($HTTP_STATUS)"
else
error "$label ($HTTP_STATUS)"; exit 5
fi
}

function generate_report() {
echo -e "\n${BLUE}=== Test Summary ===${RESET}"
for test in "AWS Credentials" "S3 Upload/Download upload" "S3 Upload/Download download" "DynamoDB Table Status" "API Gateway"; do
status=${REPORT["$test"]:-SKIP}
printf "%-35s : %s\n" "$test" "$status"
done
}

Argument parsing

tests=""
BUCKET=""
KEY="aws_verify_test.txt"
TABLE=""
ENDPOINT=""

while [[ $# -gt 0 ]]; do
case "$1" in
-t|--tests)
tests="$2"; shift 2;;
-b|--bucket)
BUCKET="$2"; shift 2;;
-k|--key)
KEY="$2"; shift 2;;
-T|--table)
TABLE="$2"; shift 2;;
-e|--endpoint)
ENDPOINT="$2"; shift 2;;
-h|--help)
usage;;
*)
echo "Unknown option: $1"; usage;;
esac
done

if [[ -z "$tests" ]]; then
echo "No tests specified."; usage
fi

IFS=',' read -r -a test_array <<< "$tests"

Run selected tests

gen_exit=0
for t in "${test_array[@]}"; do
case "$t" in
credentials)
test_credentials || gen_exit=$?;;
s3)
test_s3 || gen_exit=$?;;
dynamo)
test_dynamo || gen_exit=$?;;
api)
test_api || gen_exit=$?;;
all)
test_credentials || gen_exit=$?
test_s3 || gen_exit=$?
test_dynamo || gen_exit=$?
test_api || gen_exit=$?;
;;*)
echo "Unknown test: $t"; usage;;
esac
done

generate_report
exit $gen_exit

