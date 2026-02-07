#!/bin/bash

set -u

echo "=== Kubernetes Manifest Validation Script ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

echo "Starting validation..."
echo "===================="
echo ""

for manifest in "${K8S_MANIFESTS[@]}"; do
    # Get relative path for cleaner output
    REL_PATH=${manifest#/home/user/A2A/}

    echo -n "Validating: $REL_PATH ... "

    # Run kubeconform
    if $KUBECONFORM -summary -output json "$manifest" > /tmp/kubeconform-output.json 2>&1; then
        SUMMARY=$(cat /tmp/kubeconform-output.json | grep -o '"resources":[^}]*' || echo "")
        echo -e "${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        # Check if it's a template file (contains Helm template syntax)
        if grep -q "{{" "$manifest" 2>/dev/null; then
            echo -e "${YELLOW}SKIPPED (Helm template)${NC}"
            ((SKIPPED++))
        else
            echo -e "${RED}FAILED${NC}"
            cat /tmp/kubeconform-output.json 2>/dev/null || echo "Validation error"
            ((FAILED++))
        fi
    fi
done

echo ""
echo "===================="
echo "Validation Summary:"
echo "===================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
echo "Total: ${#K8S_MANIFESTS[@]}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Validation failed with $FAILED error(s)${NC}"
    exit 1
else
    echo -e "${GREEN}All manifests validated successfully!${NC}"
    exit 0
fi
