#!/bin/bash

# Helm Chart Validation Script
# This script runs helm lint and helm template on the chart

set -e

CHART_DIR="/home/user/A2A/helm"
RELEASE_NAME="a2a-test"

echo "=========================================="
echo "Helm Chart Validation"
echo "=========================================="
echo ""

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm command not found. Please install Helm."
    exit 1
fi

echo "Helm version:"
helm version --short
echo ""

# Run helm lint
echo "=========================================="
echo "Running: helm lint ${CHART_DIR}"
echo "=========================================="
if helm lint "${CHART_DIR}"; then
    echo "✓ Helm lint passed successfully"
else
    echo "✗ Helm lint failed"
    exit 1
fi
echo ""

# Run helm template
echo "=========================================="
echo "Running: helm template ${RELEASE_NAME} ${CHART_DIR}"
echo "=========================================="
if helm template "${RELEASE_NAME}" "${CHART_DIR}" > /tmp/helm-template-output.yaml; then
    echo "✓ Helm template generated successfully"
    echo ""
    echo "Template output saved to: /tmp/helm-template-output.yaml"
    echo ""
    echo "Generated resources:"
    grep -E "^# Source:|^kind:" /tmp/helm-template-output.yaml | head -20
    echo ""
    echo "Full template output:"
    cat /tmp/helm-template-output.yaml
else
    echo "✗ Helm template failed"
    exit 1
fi
echo ""

echo "=========================================="
echo "Validation Complete - All checks passed!"
echo "=========================================="
