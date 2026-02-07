#!/bin/bash

set -u

echo "=== Kubernetes Manifest Validation Script (Detailed) ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_CRDS=false
if [[ "${1:-}" == "--skip-crds" ]]; then
    SKIP_CRDS=true
    echo -e "${BLUE}Running in CRD-skip mode${NC}"
    echo ""
fi

# Check if kubeconform is installed
KUBECONFORM_PATH="$HOME/.local/bin/kubeconform"
if ! command -v kubeconform &> /dev/null && [ ! -f "$KUBECONFORM_PATH" ]; then
    echo -e "${YELLOW}kubeconform not found. Installing locally...${NC}"

    # Create local bin directory if it doesn't exist
    mkdir -p "$HOME/.local/bin"

    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac

    # Download and install kubeconform
    VERSION="v0.6.4"
    URL="https://github.com/yannh/kubeconform/releases/download/${VERSION}/kubeconform-linux-${ARCH}.tar.gz"

    echo "Downloading kubeconform ${VERSION} for ${ARCH}..."
    curl -sL "$URL" | tar xz -C "$HOME/.local/bin/"
    chmod +x "$KUBECONFORM_PATH"

    echo -e "${GREEN}kubeconform installed successfully to $KUBECONFORM_PATH${NC}"
    echo ""
fi

# Use local kubeconform if available
if [ -f "$KUBECONFORM_PATH" ]; then
    KUBECONFORM="$KUBECONFORM_PATH"
else
    KUBECONFORM="kubeconform"
fi

# Directories and files to exclude
EXCLUDE_PATTERNS=(
    ".github/workflows"
    "Chart.yaml"
    "values.yaml"
    ".pre-commit-config.yaml"
    "buf.yaml"
    "buf.gen.yaml"
    ".protolint.yaml"
    "conventional-commit-lint.yaml"
    "docker-compose"
    "prometheus.yml"
    "datasources"
    "mkdocs.yml"
    ".gitvote.yml"
    "dependabot.yml"
    "config.yaml"
    "/tests/"
    "test-"
)

# Function to check if file should be excluded
should_exclude() {
    local file="$1"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$file" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Find all YAML files
echo "Finding Kubernetes manifests..."
ALL_YAML_FILES=$(find /home/user/A2A -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)

# Filter to get only K8s manifests
K8S_MANIFESTS=()
while IFS= read -r file; do
    if ! should_exclude "$file"; then
        # Check if file contains Kubernetes API resources
        if grep -q "apiVersion:" "$file" 2>/dev/null && grep -q "kind:" "$file" 2>/dev/null; then
            K8S_MANIFESTS+=("$file")
        fi
    fi
done <<< "$ALL_YAML_FILES"

echo -e "${GREEN}Found ${#K8S_MANIFESTS[@]} Kubernetes manifest files${NC}"
echo ""

if [ ${#K8S_MANIFESTS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No Kubernetes manifests found to validate${NC}"
    exit 0
fi

# Validate each manifest
FAILED=0
PASSED=0
SKIPPED=0
CRD_ERRORS=0

FAILED_FILES=()
CRD_ERROR_FILES=()

echo "Starting validation..."
echo "===================="
echo ""

for manifest in "${K8S_MANIFESTS[@]}"; do
    # Get relative path for cleaner output
    REL_PATH=${manifest#/home/user/A2A/}

    echo -n "Validating: $REL_PATH ... "

    # Run kubeconform
    if $KUBECONFORM -summary -output json "$manifest" > /tmp/kubeconform-output.json 2>&1; then
        echo -e "${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        # Check if it's a template file (contains Helm template syntax)
        if grep -q "{{" "$manifest" 2>/dev/null; then
            echo -e "${YELLOW}SKIPPED (Helm template)${NC}"
            ((SKIPPED++))
        else
            # Check if it's a CRD schema error
            if grep -q "could not find schema" /tmp/kubeconform-output.json 2>/dev/null; then
                if [ "$SKIP_CRDS" = true ]; then
                    echo -e "${YELLOW}SKIPPED (CRD)${NC}"
                    ((SKIPPED++))
                else
                    echo -e "${BLUE}CRD (no schema available)${NC}"
                    CRD_ERROR_FILES+=("$REL_PATH")
                    ((CRD_ERRORS++))
                fi
            else
                echo -e "${RED}FAILED${NC}"
                cat /tmp/kubeconform-output.json 2>/dev/null || echo "Validation error"
                echo ""
                FAILED_FILES+=("$REL_PATH")
                ((FAILED++))
            fi
        fi
    fi
done

echo ""
echo "===================="
echo "Validation Summary:"
echo "===================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${BLUE}CRD Errors: $CRD_ERRORS${NC}"
echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
echo "Total: ${#K8S_MANIFESTS[@]}"
echo ""

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
    echo -e "${RED}Failed Files:${NC}"
    for file in "${FAILED_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
fi

if [ ${#CRD_ERROR_FILES[@]} -gt 0 ]; then
    echo -e "${BLUE}CRD Files (Custom Resources without schemas):${NC}"
    for file in "${CRD_ERROR_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo -e "${BLUE}Note: CRD validation failures are expected for custom resources.${NC}"
    echo -e "${BLUE}To skip CRDs in validation, run: $0 --skip-crds${NC}"
    echo ""
fi

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Validation failed with $FAILED actual error(s)${NC}"
    exit 1
else
    echo -e "${GREEN}All standard Kubernetes manifests validated successfully!${NC}"
    if [ $CRD_ERRORS -gt 0 ]; then
        echo -e "${BLUE}($CRD_ERRORS CRD files detected - these are custom resources)${NC}"
    fi
    exit 0
fi
