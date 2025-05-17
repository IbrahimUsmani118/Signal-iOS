#!/bin/bash

# Script to run duplicate content detection tests

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Running Duplicate Content Detection Tests...${NC}"

# Navigation to the project directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
cd "$PROJECT_DIR"

echo -e "${YELLOW}Building tests...${NC}"

# Build the test target
# Use a specific device that's available on this system
xcodebuild -workspace Signal.xcworkspace -scheme SignalServiceKit -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' build-for-testing

# Check if the build was successful
if [ $? -ne 0 ]; then
  echo -e "${RED}Build failed. Unable to run tests.${NC}"
  echo -e "${YELLOW}Note: You may need to modify this script to use a simulator that is available on your system.${NC}"
  exit 1
fi

echo -e "${GREEN}Build successful. Running tests...${NC}"

# Run the tests
# Use a specific device that's available on this system
xcodebuild -workspace Signal.xcworkspace -scheme SignalServiceKit -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' test -only-testing:SignalServiceKit/DuplicateContentDetectionTests

# Check if the tests ran successfully
if [ $? -ne 0 ]; then
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
fi

echo -e "${YELLOW}Tests completed.${NC}"

# Print information about how to test manually
echo -e "${YELLOW}To test manually:${NC}"
echo -e "1. Add the following code to a view controller in the app:"
echo -e "   ${GREEN}import SignalServiceKit${NC}"
echo -e "   ${GREEN}DuplicateContentDetectionTestApp.addTestButton(to: self)${NC}"
echo -e "2. Run the app and tap the 'Test Duplicate Detection' button"
echo -e "3. Use the test UI to verify functionality"

exit 0 