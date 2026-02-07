#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Terraform Validation Script"
echo "========================================="
echo ""

# Track overall status
EXIT_CODE=0

# 1. Terraform Format Check
echo -e "${YELLOW}[1/3] Running terraform fmt -check...${NC}"
if terraform fmt -check -recursive .; then
    echo -e "${GREEN}✓ Terraform format check passed${NC}"
else
    echo -e "${RED}✗ Terraform format check failed${NC}"
    echo "Run 'terraform fmt -recursive' to fix formatting issues"
    EXIT_CODE=1
fi
echo ""

# 2. Terraform Init (required for validate)
echo -e "${YELLOW}Initializing Terraform...${NC}"
if terraform init -backend=false 2>&1 | grep -q "Terraform has been successfully initialized\|has been successfully initialized"; then
    echo -e "${GREEN}✓ Terraform initialized${NC}"
else
    echo -e "${YELLOW}⚠ Terraform init skipped (modules may not be available)${NC}"
    echo "Note: Run 'terraform init' manually for full validation"
fi
echo ""

# 3. Terraform Validate
echo -e "${YELLOW}[2/3] Running terraform validate...${NC}"
if terraform validate; then
    echo -e "${GREEN}✓ Terraform validation passed${NC}"
else
    echo -e "${RED}✗ Terraform validation failed${NC}"
    EXIT_CODE=1
fi
echo ""

# 4. TFLint
echo -e "${YELLOW}[3/3] Running tflint...${NC}"
if command -v tflint &> /dev/null; then
    # Initialize tflint
    tflint --init > /dev/null 2>&1 || true

    if tflint --recursive; then
        echo -e "${GREEN}✓ TFLint check passed${NC}"
    else
        echo -e "${RED}✗ TFLint check failed${NC}"
        EXIT_CODE=1
    fi
else
    echo -e "${YELLOW}⚠ TFLint not installed, skipping...${NC}"
    echo "Install with: curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash"
fi
echo ""

# Summary
echo "========================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}All validation checks passed!${NC}"
else
    echo -e "${RED}Some validation checks failed!${NC}"
fi
echo "========================================="

exit $EXIT_CODE
