#!/bin/bash
# Script to run infrastructure security tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Infrastructure Security Tests ===${NC}"
echo ""

# Check if running in CI
if [ "${CI}" = "true" ]; then
    echo -e "${YELLOW}Running in CI environment${NC}"
fi

# Check for required environment variables
if [ -z "${GCP_PROJECT_ID}" ]; then
    echo -e "${RED}Error: GCP_PROJECT_ID environment variable is not set${NC}"
    echo "Please set it with: export GCP_PROJECT_ID=your-project-id"
    exit 1
fi

echo -e "${GREEN}Using GCP Project: ${GCP_PROJECT_ID}${NC}"
echo -e "${GREEN}Using GCP Region: ${GCP_REGION:-us-central1}${NC}"
echo ""

# Check if kubectl is configured
if command -v kubectl &> /dev/null; then
    if kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✓ kubectl is configured${NC}"
    else
        echo -e "${YELLOW}⚠ kubectl is not connected to a cluster${NC}"
        echo -e "${YELLOW}  Network policy tests will be skipped${NC}"
    fi
else
    echo -e "${YELLOW}⚠ kubectl not found${NC}"
    echo -e "${YELLOW}  Network policy tests will be skipped${NC}"
fi

# Check GCP authentication
if gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    echo -e "${GREEN}✓ GCP authenticated as: ${ACTIVE_ACCOUNT}${NC}"
else
    echo -e "${RED}Error: Not authenticated to GCP${NC}"
    echo "Please run: gcloud auth application-default login"
    exit 1
fi

echo ""
echo -e "${GREEN}Installing dependencies...${NC}"
pip install -q -r requirements.txt

echo ""
echo -e "${GREEN}Running tests...${NC}"
echo ""

# Default test options
TEST_OPTIONS="-v"

# Add integration flag if requested
if [ "${RUN_INTEGRATION_TESTS}" = "true" ] || [ "$1" = "--integration" ]; then
    TEST_OPTIONS="${TEST_OPTIONS} --integration"
    echo -e "${YELLOW}Running integration tests (requires live infrastructure)${NC}"
fi

# Add parallel execution if not in CI
if [ "${CI}" != "true" ]; then
    TEST_OPTIONS="${TEST_OPTIONS} -n auto"
fi

# Add coverage if requested
if [ "$1" = "--coverage" ] || [ "$2" = "--coverage" ]; then
    TEST_OPTIONS="${TEST_OPTIONS} --cov=. --cov-report=term --cov-report=html"
fi

# Add HTML report if requested
if [ "$1" = "--html" ] || [ "$2" = "--html" ]; then
    TEST_OPTIONS="${TEST_OPTIONS} --html=report.html --self-contained-html"
fi

# Run the tests
if pytest ${TEST_OPTIONS} .; then
    echo ""
    echo -e "${GREEN}=== All tests passed! ===${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}=== Some tests failed ===${NC}"
    exit 1
fi
