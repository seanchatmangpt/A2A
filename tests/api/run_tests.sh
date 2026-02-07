#!/bin/bash
# API Test Runner Script

set -e

echo "================================"
echo "A2A Bridge API Test Suite"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$TEST_DIR")")"
COVERAGE_MIN=70

echo "Test Directory: $TEST_DIR"
echo "Project Root: $PROJECT_ROOT"
echo ""

# Function to print colored output
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# Install dependencies if needed
echo "Checking dependencies..."
if ! python3 -c "import pytest" 2>/dev/null; then
    echo "Installing test dependencies..."
    pip install -q -r "$PROJECT_ROOT/tests/requirements.txt"
fi

# Run pytest tests
echo ""
echo "================================"
echo "Running Pytest Tests"
echo "================================"
echo ""

cd "$PROJECT_ROOT"

# Run tests with coverage
pytest tests/api/ \
    -v \
    --tb=short \
    --cov=elrmcp_bridge/src/api \
    --cov-report=term-missing \
    --cov-report=html:tests/api/htmlcov \
    --cov-report=xml:tests/api/coverage.xml \
    --html=tests/api/report.html \
    --self-contained-html \
    --json-report \
    --json-report-file=tests/api/report.json \
    --maxfail=5

PYTEST_EXIT=$?
print_status $PYTEST_EXIT "Pytest tests completed"

# Check if Newman is available
echo ""
echo "================================"
echo "Running Newman Tests"
echo "================================"
echo ""

if command -v newman &> /dev/null; then
    newman run tests/api/postman_collection.json \
        --reporters cli,html,json \
        --reporter-html-export tests/api/newman-report.html \
        --reporter-json-export tests/api/newman-report.json \
        --color on \
        --bail \
        --timeout-request 30000 || true

    NEWMAN_EXIT=$?
    print_status $NEWMAN_EXIT "Newman tests completed"
else
    echo -e "${YELLOW}⚠ Newman not installed. Skipping Postman collection tests.${NC}"
    echo "Install Newman: npm install -g newman"
    NEWMAN_EXIT=0
fi

# Generate summary report
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo ""

if [ -f tests/api/report.json ]; then
    echo "Test Results:"
    python3 -c "
import json
import sys

try:
    with open('tests/api/report.json', 'r') as f:
        data = json.load(f)

    summary = data.get('summary', {})
    total = summary.get('total', 0)
    passed = summary.get('passed', 0)
    failed = summary.get('failed', 0)

    print(f'  Total:  {total}')
    print(f'  Passed: {passed}')
    print(f'  Failed: {failed}')

    if total > 0:
        percentage = (passed / total) * 100
        print(f'  Success Rate: {percentage:.1f}%')
except Exception as e:
    print(f'  Could not parse test results: {e}')
" || true
fi

echo ""
echo "Reports generated:"
echo "  - HTML Report: tests/api/report.html"
echo "  - Coverage HTML: tests/api/htmlcov/index.html"
echo "  - Coverage XML: tests/api/coverage.xml"
echo "  - JSON Report: tests/api/report.json"

if command -v newman &> /dev/null; then
    echo "  - Newman HTML: tests/api/newman-report.html"
    echo "  - Newman JSON: tests/api/newman-report.json"
fi

echo ""

# Exit with appropriate code
if [ $PYTEST_EXIT -ne 0 ]; then
    echo -e "${RED}Tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
