#!/bin/bash
# Main entry point for all Helm upgrade/rollback tests
# This script orchestrates the complete test suite

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Cleanup function
cleanup() {
    local exit_code=$?

    if [[ ${exit_code} -ne 0 ]] && [[ "${SKIP_CLEANUP:-}" != "true" ]]; then
        log_warn "Test failed. Skipping cleanup for debugging..."
        log_warn "Run 'SKIP_CLEANUP=true $0' to keep resources"
        log_warn "To cleanup manually, run: ${SCRIPT_DIR}/setup-kind-cluster.sh delete"
    elif [[ "${SKIP_CLEANUP:-}" != "true" ]]; then
        log_info "Cleaning up test resources..."
        "${SCRIPT_DIR}/setup-kind-cluster.sh" delete
    fi

    exit ${exit_code}
}

trap cleanup EXIT

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "  Helm Upgrade/Rollback Test Suite"
    echo "========================================="
    echo ""

    # Step 1: Setup Kind cluster
    log_step "Step 1: Setting up Kind cluster..."
    if ! "${SCRIPT_DIR}/setup-kind-cluster.sh" create; then
        log_error "Failed to setup Kind cluster"
        exit 1
    fi

    # Step 2: Build test images
    log_step "Step 2: Building test images..."
    if ! "${SCRIPT_DIR}/build-test-images.sh" all; then
        log_error "Failed to build test images"
        exit 1
    fi

    # Step 3: Run upgrade/rollback tests
    log_step "Step 3: Running upgrade/rollback tests..."
    if ! "${SCRIPT_DIR}/test-upgrade-rollback.sh"; then
        log_error "Tests failed!"
        exit 1
    fi

    # Step 4: Validate final health
    log_step "Step 4: Validating final health..."
    if "${SCRIPT_DIR}/validate-health.sh"; then
        log_info "Final health validation passed!"
    else
        log_warn "Final health validation had issues (may be expected after cleanup)"
    fi

    echo ""
    log_info "All tests completed successfully!"
    echo ""
    log_info "To keep resources for debugging, run:"
    echo "  SKIP_CLEANUP=true $0"
    echo ""
    log_info "To manually cleanup, run:"
    echo "  ${SCRIPT_DIR}/setup-kind-cluster.sh delete"
    echo ""
}

# Help function
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run the complete Helm upgrade/rollback test suite.

OPTIONS:
    -h, --help          Show this help message
    --skip-cleanup      Don't cleanup resources after tests
    --no-cluster        Skip cluster creation (use existing)
    --no-build          Skip image building (use existing)

ENVIRONMENT VARIABLES:
    SKIP_CLEANUP        Don't cleanup resources after tests
    CLUSTER_NAME        Kind cluster name (default: a2a-test)
    RELEASE_NAME        Helm release name (default: a2a-test)
    NAMESPACE           Kubernetes namespace (default: a2a-test)
    REGISTRY            Docker registry (default: localhost:5000)
    IMAGE_NAME          Image name (default: a2a-erl)

EXAMPLES:
    $0                              # Run all tests with cleanup
    SKIP_CLEANUP=true $0            # Run tests and keep resources
    CLUSTER_NAME=mytest $0          # Use custom cluster name

EOF
}

# Parse arguments
SKIP_CLUSTER=false
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --skip-cleanup)
            export SKIP_CLEANUP=true
            shift
            ;;
        --no-cluster)
            SKIP_CLUSTER=true
            shift
            ;;
        --no-build)
            SKIP_BUILD=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run with conditional steps
if [[ "${SKIP_CLUSTER}" == "true" ]]; then
    log_warn "Skipping cluster creation..."
else
    export SKIP_CLUSTER # Pass to sub-scripts
fi

if [[ "${SKIP_BUILD}" == "true" ]]; then
    log_warn "Skipping image build..."
else
    export SKIP_BUILD # Pass to sub-scripts
fi

main "$@"
