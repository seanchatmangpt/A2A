#!/bin/bash

# Terraform Security Validation Script
# Runs tfsec and checkov security scanners on all Terraform code

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories containing Terraform code
TERRAFORM_DIRS=(
    "/home/user/A2A/terraform"
    "/home/user/A2A/infrastructure/terraform"
)

# Output directory for reports
REPORT_DIR="/home/user/A2A/security_reports"
mkdir -p "$REPORT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Terraform Security Validation Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install tfsec
install_tfsec() {
    echo -e "${YELLOW}Installing tfsec...${NC}"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
        sudo mv tfsec /usr/local/bin/ 2>/dev/null || mv tfsec ~/bin/ 2>/dev/null || true
    else
        echo -e "${RED}Please install tfsec manually from: https://github.com/aquasecurity/tfsec${NC}"
        return 1
    fi
}

# Function to install checkov
install_checkov() {
    echo -e "${YELLOW}Installing checkov...${NC}"
    if command_exists pip3; then
        pip3 install --user checkov
    elif command_exists pip; then
        pip install --user checkov
    else
        echo -e "${RED}pip/pip3 not found. Please install Python and pip first.${NC}"
        return 1
    fi
}

# Check and install tfsec
echo -e "${BLUE}Checking for tfsec...${NC}"
if command_exists tfsec; then
    echo -e "${GREEN}✓ tfsec is installed${NC}"
    tfsec --version
else
    echo -e "${YELLOW}✗ tfsec not found${NC}"
    install_tfsec || echo -e "${YELLOW}Continuing without tfsec...${NC}"
fi
echo ""

# Check and install checkov
echo -e "${BLUE}Checking for checkov...${NC}"
if command_exists checkov; then
    echo -e "${GREEN}✓ checkov is installed${NC}"
    checkov --version
else
    echo -e "${YELLOW}✗ checkov not found${NC}"
    install_checkov || echo -e "${YELLOW}Continuing without checkov...${NC}"
fi
echo ""

# Run tfsec scans
if command_exists tfsec; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running tfsec Security Scans${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    for dir in "${TERRAFORM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "${YELLOW}Scanning: $dir${NC}"

            # Run tfsec with detailed output
            tfsec "$dir" \
                --format default \
                --out "$REPORT_DIR/tfsec_$(basename $dir)_report.txt" \
                --no-color || true

            # Also generate JSON output for programmatic analysis
            tfsec "$dir" \
                --format json \
                --out "$REPORT_DIR/tfsec_$(basename $dir)_report.json" \
                --no-color || true

            # Display summary
            tfsec "$dir" --format default || true
            echo ""
        fi
    done
else
    echo -e "${YELLOW}Skipping tfsec scan (not installed)${NC}"
    echo ""
fi

# Run checkov scans
if command_exists checkov; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running Checkov Security Scans${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    for dir in "${TERRAFORM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "${YELLOW}Scanning: $dir${NC}"

            # Run checkov with detailed output
            checkov -d "$dir" \
                --framework terraform \
                --output cli \
                --quiet \
                --compact \
                --skip-download || true

            # Generate JSON report
            checkov -d "$dir" \
                --framework terraform \
                --output json \
                --output-file-path "$REPORT_DIR" \
                --quiet \
                --skip-download || true

            echo ""
        fi
    done
else
    echo -e "${YELLOW}Skipping checkov scan (not installed)${NC}"
    echo ""
fi

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Scan Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Reports saved to: $REPORT_DIR${NC}"
echo ""
echo "Available reports:"
ls -lh "$REPORT_DIR" 2>/dev/null || echo "No reports generated"
echo ""

# Count issues if reports exist
if command_exists tfsec && [ -f "$REPORT_DIR/tfsec_terraform_report.txt" ]; then
    echo -e "${BLUE}tfsec Summary:${NC}"
    grep -E "CRITICAL|HIGH|MEDIUM|LOW" "$REPORT_DIR/tfsec_terraform_report.txt" | head -20 || echo "No issues found or report format different"
    echo ""
fi

echo -e "${GREEN}Security scan completed successfully!${NC}"
