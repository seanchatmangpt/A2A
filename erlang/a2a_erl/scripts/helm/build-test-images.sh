#!/bin/bash
# Build multiple versions of the A2A Erlang Docker image for testing upgrades

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY="${REGISTRY:-localhost:5000}"
IMAGE_NAME="${IMAGE_NAME:-a2a-erl}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Build a specific version
build_version() {
    local version=$1
    local full_tag="${REGISTRY}/${IMAGE_NAME}:${version}"

    log_info "Building ${IMAGE_NAME}:${version}..."

    cd "${PROJECT_ROOT}"

    # Build the image with version tag
    docker build \
        -f Dockerfile \
        -t "${IMAGE_NAME}:${version}" \
        -t "${full_tag}" \
        --build-arg "VERSION=${version}" \
        .

    # Optionally push to local registry
    if [[ "${REGISTRY}" == "localhost:5000" ]]; then
        log_info "Pushing to local registry..."
        docker push "${full_tag}" 2>/dev/null || true
    fi

    log_info "Built ${full_tag}"
}

# Build all test versions
build_all() {
    log_info "Building all test versions..."

    # Version 0.1.0 - Initial version
    build_version "0.1.0"

    # Version 0.2.0 - With enhancements
    build_version "0.2.0"

    # Version 0.3.0 - Latest version
    build_version "0.3.0"

    # Also tag latest
    docker tag "${IMAGE_NAME}:0.3.0" "${IMAGE_NAME}:latest"
    docker tag "${REGISTRY}/${IMAGE_NAME}:0.3.0" "${REGISTRY}/${IMAGE_NAME}:latest"

    log_info "All versions built successfully!"
    docker images | grep "${IMAGE_NAME}"
}

# Setup local registry
setup_registry() {
    log_info "Setting up local Docker registry..."

    # Check if registry is running
    if ! docker ps | grep -q "registry:2"; then
        docker run -d -p 5000:5000 --name local-registry registry:2
        log_info "Local registry started on port 5000"
    else
        log_info "Local registry already running"
    fi
}

# Main script logic
case "${1:-all}" in
    all)
        setup_registry
        build_all
        ;;
    0.1.0|0.2.0|0.3.0)
        setup_registry
        build_version "$1"
        ;;
    registry)
        setup_registry
        ;;
    clean)
        log_info "Cleaning up test images..."
        docker rmi "${IMAGE_NAME}:0.1.0" "${IMAGE_NAME}:0.2.0" "${IMAGE_NAME}:0.3.0" "${IMAGE_NAME}:latest" 2>/dev/null || true
        docker rmi "${REGISTRY}/${IMAGE_NAME}:0.1.0" "${REGISTRY}/${IMAGE_NAME}:0.2.0" "${REGISTRY}/${IMAGE_NAME}:0.3.0" "${REGISTRY}/${IMAGE_NAME}:latest" 2>/dev/null || true
        log_info "Cleanup complete"
        ;;
    *)
        echo "Usage: $0 {all|0.1.0|0.2.0|0.3.0|registry|clean}"
        echo ""
        echo "Environment variables:"
        echo "  REGISTRY  - Docker registry (default: localhost:5000)"
        echo "  IMAGE_NAME - Image name (default: a2a-erl)"
        exit 1
        ;;
esac
