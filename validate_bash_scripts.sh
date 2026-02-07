#!/bin/bash
# Bash Script Validation using ShellCheck
# This script runs shellcheck on install.sh and all scripts/*.sh files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "    Bash Script Validation with ShellCheck"
echo "================================================"
echo ""

# Determine shellcheck command
SHELLCHECK_CMD=""
if command -v shellcheck &> /dev/null; then
    SHELLCHECK_CMD="shellcheck"
elif [ -f "./shellcheck" ]; then
    SHELLCHECK_CMD="./shellcheck"
else
    echo -e "${RED}ERROR: shellcheck is not installed${NC}"
    echo "Please install shellcheck:"
    echo "  - Ubuntu/Debian: sudo apt-get install shellcheck"
    echo "  - macOS: brew install shellcheck"
    echo "  - Fedora: sudo dnf install ShellCheck"
    exit 1
fi

echo -e "${GREEN}shellcheck version:${NC}"
$SHELLCHECK_CMD --version | head -n 2
echo ""

# Array to hold all scripts to check
SCRIPTS=()

# Add install.sh if it exists
if [ -f "install.sh" ]; then
    SCRIPTS+=("install.sh")
fi

# Add all scripts/*.sh files
if [ -d "scripts" ]; then
    while IFS= read -r -d '' script; do
        SCRIPTS+=("$script")
    done < <(find scripts -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)
fi

# Check if we found any scripts
if [ ${#SCRIPTS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No bash scripts found to validate${NC}"
    exit 0
fi

echo "Found ${#SCRIPTS[@]} script(s) to validate"
echo ""

# Track results
TOTAL=0
PASSED=0
FAILED=0
FAILED_SCRIPTS=()

# Run shellcheck on each script
for script in "${SCRIPTS[@]}"; do
    TOTAL=$((TOTAL + 1))
    echo -e "${YELLOW}Checking:${NC} $script"

    if $SHELLCHECK_CMD "$script"; then
        echo -e "${GREEN}✓ PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC}"
        FAILED=$((FAILED + 1))
        FAILED_SCRIPTS+=("$script")
    fi
    echo ""
done

# Print summary
echo "================================================"
echo "                   SUMMARY"
echo "================================================"
echo "Total scripts checked: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

# List failed scripts if any
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed scripts:${NC}"
    for script in "${FAILED_SCRIPTS[@]}"; do
        echo "  - $script"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}All scripts passed validation!${NC}"
    exit 0
fi
