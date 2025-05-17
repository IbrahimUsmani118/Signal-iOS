#!/bin/bash

# Setup script for Duplicate Content Detection system

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Duplicate Content Detection System...${NC}"

# Navigation to the project directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR"

# Check if required directories exist, create if not
mkdir -p "$SCRIPT_DIR/Sources/AWS"
mkdir -p "$SCRIPT_DIR/Sources/UI"
mkdir -p "$SCRIPT_DIR/Services"
mkdir -p "$SCRIPT_DIR/Tests"
mkdir -p "$SCRIPT_DIR/Util"

echo -e "${GREEN}Directories created.${NC}"

# Make the test script executable
chmod +x "$SCRIPT_DIR/Tests/run_tests.sh"

echo -e "${GREEN}Test script permissions set.${NC}"

# Check for AWS configuration
if [[ ! -f "$SCRIPT_DIR/Sources/AWS/AWSConfig.swift" ]]; then
    echo -e "${RED}Warning: AWSConfig.swift not found. Please make sure to create this file with your AWS credentials.${NC}"
    echo -e "${YELLOW}See the README.md file for more information.${NC}"
fi

# Check CocoaLumberjack dependency
PODFILE="$PROJECT_DIR/Podfile"
if [[ -f "$PODFILE" ]]; then
    if ! grep -q "CocoaLumberjack" "$PODFILE"; then
        echo -e "${YELLOW}CocoaLumberjack dependency not found in Podfile.${NC}"
        echo -e "${YELLOW}Consider adding: pod 'CocoaLumberjack'${NC}"
    else
        echo -e "${GREEN}CocoaLumberjack dependency found.${NC}"
    fi
else
    echo -e "${RED}Podfile not found.${NC}"
fi

# Remind about AWS credentials
echo -e "${YELLOW}Important: Make sure to update the AWS credentials in AWSConfig.swift with your actual credentials.${NC}"
echo -e "${YELLOW}See INTEGRATION.md for more details on secure credential management.${NC}"

# Run pod install if Podfile exists
if [[ -f "$PODFILE" ]]; then
    echo -e "${YELLOW}Running pod install...${NC}"
    pod install
    if [ $? -ne 0 ]; then
        echo -e "${RED}pod install failed. Please run it manually.${NC}"
    else
        echo -e "${GREEN}pod install completed successfully.${NC}"
    fi
fi

# Print setup completion message
echo -e "${GREEN}Setup completed!${NC}"
echo -e "${YELLOW}To test the system, run:${NC}"
echo -e "${GREEN}./SignalServiceKit/DuplicateContentDetection/Tests/run_tests.sh${NC}"
echo -e "${YELLOW}For integration instructions, refer to:${NC}"
echo -e "${GREEN}SignalServiceKit/DuplicateContentDetection/INTEGRATION.md${NC}"

exit 0 