#!/bin/bash
################################################################################
# Fortune 5 Cloud Cost Estimation Tool - Quick Start Script
# This script runs the cost estimation tool with appropriate settings
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}Fortune 5 Cloud Infrastructure Cost Estimation Tool${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python 3 found${NC}"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${YELLOW}Warning: Terraform not found. Some features may not work.${NC}"
else
    echo -e "${GREEN}✓ Terraform found${NC}"
fi

# Check Infracost
export PATH="/home/user/.local/bin:$PATH"
if [ -f "/home/user/.local/bin/infracost" ]; then
    echo -e "${GREEN}✓ Infracost found${NC}"

    # Check for API key
    if [ -z "$INFRACOST_API_KEY" ]; then
        echo -e "${YELLOW}Warning: INFRACOST_API_KEY not set${NC}"
        echo -e "${YELLOW}To get actual cost estimates, register at: https://dashboard.infracost.io${NC}"
        echo -e "${YELLOW}Then set: export INFRACOST_API_KEY=<your-key>${NC}"
        echo
        echo -e "${BLUE}Running in DEMO mode with sample data...${NC}"
        USE_DEMO=true
    else
        echo -e "${GREEN}✓ Infracost API key found${NC}"
        USE_DEMO=false
    fi
else
    echo -e "${YELLOW}Warning: Infracost not found${NC}"
    echo -e "${BLUE}Running in DEMO mode with sample data...${NC}"
    USE_DEMO=true
fi

echo

# Parse arguments
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
OUTPUT_DIR="${SCRIPT_DIR}/cost_estimates"

while [[ $# -gt 0 ]]; do
    case $1 in
        --terraform-dir)
            TERRAFORM_DIR="$2"
            shift 2
            ;;
        --demo)
            USE_DEMO=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --terraform-dir DIR   Specify Terraform directory (default: ./terraform)"
            echo "  --demo                Force demo mode with sample data"
            echo "  --help, -h            Show this help message"
            echo
            echo "Examples:"
            echo "  $0                                    # Run with default settings"
            echo "  $0 --demo                             # Run demo with sample data"
            echo "  $0 --terraform-dir /path/to/terraform # Run with custom Terraform dir"
            echo
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run the appropriate script
cd "$SCRIPT_DIR"

if [ "$USE_DEMO" = true ]; then
    echo -e "${BLUE}Running demo cost estimation...${NC}"
    echo
    python3 demo_cost_estimation.py
else
    echo -e "${BLUE}Running full cost estimation...${NC}"
    echo -e "${BLUE}Terraform Directory: ${TERRAFORM_DIR}${NC}"
    echo
    python3 cost_estimator.py --terraform-dir "$TERRAFORM_DIR"
fi

# Check if estimation was successful
if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}================================================================================================${NC}"
    echo -e "${GREEN}Cost estimation completed successfully!${NC}"
    echo -e "${GREEN}================================================================================================${NC}"
    echo
    echo -e "Reports saved to: ${GREEN}${OUTPUT_DIR}${NC}"
    echo
    echo "View latest report:"
    echo -e "  ${BLUE}cat ${OUTPUT_DIR}/latest_cost_report.txt${NC}"
    echo
    echo "View detailed analysis:"
    echo -e "  ${BLUE}cat ${OUTPUT_DIR}/cost_analysis_*.json | jq${NC}"
    echo

    # Show quick summary if latest report exists
    if [ -f "${OUTPUT_DIR}/latest_cost_report.txt" ]; then
        echo -e "${BLUE}================================================================================================${NC}"
        echo -e "${BLUE}QUICK SUMMARY${NC}"
        echo -e "${BLUE}================================================================================================${NC}"
        grep -A 10 "EXECUTIVE SUMMARY" "${OUTPUT_DIR}/latest_cost_report.txt" | head -n 15
    fi
else
    echo
    echo -e "${RED}================================================================================================${NC}"
    echo -e "${RED}Cost estimation failed!${NC}"
    echo -e "${RED}================================================================================================${NC}"
    echo
    echo "Please check the error messages above and ensure:"
    echo "  1. Terraform configuration is valid"
    echo "  2. Infracost is properly configured"
    echo "  3. INFRACOST_API_KEY environment variable is set (if not using demo mode)"
    echo
    exit 1
fi

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}ADDITIONAL TOOLS${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo
echo "Generate CSV export:"
echo -e "  ${BLUE}python3 -c 'from cost_analyzer import export_to_csv; import json; export_to_csv(json.load(open(\"${OUTPUT_DIR}/cost_analysis_*.json\")), \"costs.csv\")'${NC}"
echo
echo "Run advanced analysis:"
echo -e "  ${BLUE}python3 cost_analyzer.py${NC}"
echo
echo -e "${BLUE}================================================================================================${NC}"
