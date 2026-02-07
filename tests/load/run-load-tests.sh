#!/bin/bash
# Load Testing Runner Script for A2A Protocol
# Runs comprehensive load tests at Fortune 5 scale

set -e

echo "======================================================================"
echo "A2A Protocol Load Testing Suite - Fortune 5 Scale"
echo "======================================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
RESULTS_DIR="/home/user/A2A/tests/load/results"
mkdir -p "$RESULTS_DIR"

# Check if k6 is installed
echo -e "${BLUE}Checking k6 installation...${NC}"
if ! command -v k6 &> /dev/null; then
    echo -e "${YELLOW}k6 not found. Installing k6...${NC}"

    # Install k6
    sudo gpg -k
    sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update
    sudo apt-get install -y k6

    echo -e "${GREEN}k6 installed successfully!${NC}"
else
    echo -e "${GREEN}k6 is already installed${NC}"
    k6 version
fi

# Function to run a test
run_test() {
    local test_name=$1
    local test_file=$2
    local description=$3

    echo ""
    echo "======================================================================"
    echo -e "${BLUE}Running: ${test_name}${NC}"
    echo "Description: ${description}"
    echo "======================================================================"

    # Run the test
    if k6 run "$test_file"; then
        echo -e "${GREEN}✓ ${test_name} completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ ${test_name} failed${NC}"
        return 1
    fi
}

# Test execution order
echo ""
echo -e "${YELLOW}Starting load test suite...${NC}"
echo ""

# Parse command line arguments
TEST_SUITE=${1:-all}

case $TEST_SUITE in
    smoke)
        run_test "Smoke Test" "/home/user/A2A/tests/load/k6-smoke-test.js" "Basic functionality validation with minimal load"
        ;;
    load)
        run_test "Load Test" "/home/user/A2A/tests/load/k6-load-test.js" "Normal peak load simulation"
        ;;
    stress)
        run_test "Stress Test" "/home/user/A2A/tests/load/k6-stress-test.js" "Beyond capacity stress testing"
        ;;
    fortune5)
        run_test "Fortune 5 Scale Test" "/home/user/A2A/tests/load/k6-fortune5-test.js" "Enterprise-scale simulation with 100K RPS"
        ;;
    all)
        # Run all tests in order
        run_test "1. Smoke Test" "/home/user/A2A/tests/load/k6-smoke-test.js" "Basic functionality validation"

        sleep 5

        run_test "2. Load Test" "/home/user/A2A/tests/load/k6-load-test.js" "Normal peak load simulation"

        sleep 10

        run_test "3. Stress Test" "/home/user/A2A/tests/load/k6-stress-test.js" "Beyond capacity stress testing"

        sleep 10

        run_test "4. Fortune 5 Scale Test" "/home/user/A2A/tests/load/k6-fortune5-test.js" "Enterprise-scale simulation"
        ;;
    *)
        echo -e "${RED}Unknown test suite: $TEST_SUITE${NC}"
        echo "Usage: $0 {smoke|load|stress|fortune5|all}"
        exit 1
        ;;
esac

echo ""
echo "======================================================================"
echo -e "${GREEN}Load Testing Complete!${NC}"
echo "======================================================================"
echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "View detailed reports:"
echo "  - JSON summaries: $RESULTS_DIR/*.json"
echo "  - HTML reports: $RESULTS_DIR/*.html"
echo ""
echo "======================================================================"
