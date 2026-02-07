#!/bin/bash
# RBAC Test Runner
# Runs comprehensive RBAC, IAM, and permission validation tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RBAC and IAM Policy Test Suite${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Change to project root
cd /home/user/A2A

# Check if pytest is installed
if ! command -v pytest &> /dev/null; then
    echo -e "${YELLOW}pytest not found. Installing...${NC}"
    pip install pytest pytest-cov pytest-html -q
fi

# Create reports directory
mkdir -p /home/user/A2A/tests/reports

# Run tests with coverage
echo -e "${GREEN}Running RBAC Permission Tests...${NC}"
pytest tests/unit/rbac/test_rbac_permissions.py \
    -v \
    --tb=short \
    --cov=. \
    --cov-report=term-missing \
    --cov-report=html:/home/user/A2A/tests/reports/rbac_coverage \
    --html=/home/user/A2A/tests/reports/rbac_permissions_report.html \
    --self-contained-html \
    || echo -e "${RED}Some RBAC permission tests failed${NC}"

echo ""
echo -e "${GREEN}Running IAM Policy Validation Tests...${NC}"
pytest tests/unit/rbac/test_iam_policy_validation.py \
    -v \
    --tb=short \
    --cov=. \
    --cov-report=term-missing \
    --cov-report=html:/home/user/A2A/tests/reports/iam_coverage \
    --html=/home/user/A2A/tests/reports/iam_policy_report.html \
    --self-contained-html \
    || echo -e "${RED}Some IAM policy tests failed${NC}"

echo ""
echo -e "${GREEN}Running All RBAC Tests Together...${NC}"
pytest tests/unit/rbac/ \
    -v \
    --tb=line \
    --html=/home/user/A2A/tests/reports/rbac_full_report.html \
    --self-contained-html

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Test reports generated in: ${YELLOW}/home/user/A2A/tests/reports/${NC}"
echo -e "- rbac_permissions_report.html"
echo -e "- iam_policy_report.html"
echo -e "- rbac_full_report.html"
echo ""
echo -e "${GREEN}Coverage reports:${NC}"
echo -e "- /home/user/A2A/tests/reports/rbac_coverage/"
echo -e "- /home/user/A2A/tests/reports/iam_coverage/"
echo ""
