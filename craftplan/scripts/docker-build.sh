#!/usr/bin/env bash
# =============================================================================
# Craftplan Docker Build Helper Script
# =============================================================================
#
# This script builds Docker images for the Craftplan integration.
#
# Usage:
#   ./docker-build.sh [mcp|a2a|all] [--push] [--tag TAG] [--no-cache]
#
# Arguments:
#   mcp|a2a|all    Which component(s) to build (default: all)
#
# Options:
#   --push         Push images to registry after building
#   --tag TAG      Use custom tag instead of 'latest'
#   --no-cache     Build without using cache
#   --platform P   Build for specific platform (e.g., linux/amd64)
#   --debug        Enable debug output
#
# Examples:
#   ./docker-build.sh all                # Build both images
#   ./docker-build.sh mcp --tag v1.0.0   # Build and tag MCP server
#   ./docker-build.sh all --push         # Build and push both
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd"

DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_ORG="${DOCKER_ORG:-craftplan}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_COMPONENT="all"
PUSH_IMAGES=false
NO_CACHE=false
PLATFORM=""
DEBUG=false

# Image names
MCP_IMAGE_NAME="${DOCKER_ORG}/craftplan-mcp-server"
A2A_IMAGE_NAME="${DOCKER_ORG}/craftplan-a2a-agent"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $*" >&2
    fi
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [COMPONENT] [OPTIONS]

Build Docker images for Craftplan integration.

COMPONENTS:
    mcp         Build MCP server image only
    a2a         Build A2A agent image only
    all         Build both images (default)

OPTIONS:
    --push         Push images to registry after building
    --tag TAG      Use custom tag instead of 'latest'
    --no-cache     Build without using cache
    --platform P   Build for specific platform (e.g., linux/amd64)
    --debug        Enable debug output
    -h             Show this help message

ENVIRONMENT VARIABLES:
    DOCKER_REGISTRY   Docker registry (default: docker.io)
    DOCKER_ORG        Docker organization (default: craftplan)
    IMAGE_TAG         Image tag (default: latest)

EXAMPLES:
    $(basename "$0") all                          # Build both images
    $(basename "$0") mcp --tag v1.0.0            # Build and tag MCP as v1.0.0
    $(basename "$0") all --push                   # Build and push both
    $(basename "$0") a2a --platform linux/arm64   # Build for ARM64

EOF
}

print_banner() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                                                              ║
║       Craftplan Docker Build Automation                     ║
║                                                              ║
╚════════════════════════════════════════════════════════════╝

EOF
}

check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi

    debug "Docker version: $(docker --version)"
}

build_docker_image() {
    local component="$1"
    local context_dir="$2"
    local dockerfile="$3"
    local image_name="$4"

    log_step "Building ${component} image..."

    local build_args=(
        -t "${image_name}:${IMAGE_TAG}"
        -f "${dockerfile}"
    )

    if [[ "${NO_CACHE}" == "true" ]]; then
        build_args+=(--no-cache)
    fi

    if [[ -n "${PLATFORM}" ]]; then
        build_args+=(--platform "${PLATFORM}")
    fi

    debug "Build command: docker build ${build_args[*]} ${context_dir}"

    if docker build "${build_args[@]}" "${context_dir}"; then
        log_info "${component} image built successfully: ${image_name}:${IMAGE_TAG}"

        # Also tag as 'latest' if IMAGE_TAG is not 'latest'
        if [[ "${IMAGE_TAG}" != "latest" ]]; then
            docker tag "${image_name}:${IMAGE_TAG}" "${image_name}:latest"
            log_info "Also tagged as ${image_name}:latest"
        fi

        return 0
    else
        log_error "Failed to build ${component} image"
        return 1
    fi
}

push_docker_image() {
    local image_name="$1"

    log_step "Pushing ${image_name}:${IMAGE_TAG}..."

    if docker push "${image_name}:${IMAGE_TAG}"; then
        log_info "Successfully pushed ${image_name}:${IMAGE_TAG}"

        # Also push 'latest' tag if IMAGE_TAG is not 'latest'
        if [[ "${IMAGE_TAG}" != "latest" ]]; then
            docker push "${image_name}:latest"
            log_info "Successfully pushed ${image_name}:latest"
        fi

        return 0
    else
        log_error "Failed to push ${image_name}:${IMAGE_TAG}"
        return 1
    fi
}

show_image_info() {
    local image_name="$1"

    log_info "Image information for ${image_name}:${IMAGE_TAG}:"
    docker images "${image_name}:${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
}

build_mcp() {
    local context_dir="${PROJECT_ROOT}/mcp-server"
    local dockerfile="${context_dir}/Dockerfile"

    if [[ ! -f "${dockerfile}" ]]; then
        log_error "Dockerfile not found: ${dockerfile}"
        return 1
    fi

    if build_docker_image "MCP Server" "${context_dir}" "${dockerfile}" "${MCP_IMAGE_NAME}"; then
        show_image_info "${MCP_IMAGE_NAME}"

        if [[ "${PUSH_IMAGES}" == "true" ]]; then
            push_docker_image "${MCP_IMAGE_NAME}"
        fi

        return 0
    else
        return 1
    fi
}

build_a2a() {
    local context_dir="${PROJECT_ROOT}/a2a-agent"
    local dockerfile="${context_dir}/Dockerfile"

    if [[ ! -f "${dockerfile}" ]]; then
        log_error "Dockerfile not found: ${dockerfile}"
        return 1
    fi

    if build_docker_image "A2A Agent" "${context_dir}" "${dockerfile}" "${A2A_IMAGE_NAME}"; then
        show_image_info "${A2A_IMAGE_NAME}"

        if [[ "${PUSH_IMAGES}" == "true" ]]; then
            push_docker_image "${A2A_IMAGE_NAME}"
        fi

        return 0
    else
        return 1
    fi
}

show_build_summary() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                    Build Summary                           ║
╚════════════════════════════════════════════════════════════╝

EOF

    if [[ "${BUILD_COMPONENT}" == "all" || "${BUILD_COMPONENT}" == "mcp" ]]; then
        if docker image inspect "${MCP_IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
            echo "✓ MCP Server: ${MCP_IMAGE_NAME}:${IMAGE_TAG}"
        else
            echo "✗ MCP Server: Build failed"
        fi
    fi

    if [[ "${BUILD_COMPONENT}" == "all" || "${BUILD_COMPONENT}" == "a2a" ]]; then
        if docker image inspect "${A2A_IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
            echo "✓ A2A Agent: ${A2A_IMAGE_NAME}:${IMAGE_TAG}"
        else
            echo "✗ A2A Agent: Build failed"
        fi
    fi

    cat << "EOF"

Quick Start:

  docker run -p 8090:8090 ${MCP_IMAGE_NAME}:${IMAGE_TAG}
  docker run -p 8080:8080 ${A2A_IMAGE_NAME}:${IMAGE_TAG}

EOF
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------

parse_arguments() {
    if [[ $# -eq 0 ]]; then
        BUILD_COMPONENT="all"
        return
    fi

    # First argument is the component
    case "$1" in
        mcp|a2a|all)
            BUILD_COMPONENT="$1"
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            # If starts with option, assume 'all'
            BUILD_COMPONENT="all"
            ;;
        *)
            log_error "Unknown component: $1"
            show_usage
            exit 1
            ;;
    esac

    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --push)
                PUSH_IMAGES=true
                shift
                ;;
            --tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                set -x
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------

main() {
    parse_arguments "$@"

    print_banner

    log_info "Docker build configuration:"
    echo "  Component: ${BUILD_COMPONENT}"
    echo "  Tag: ${IMAGE_TAG}"
    echo "  Registry: ${DOCKER_REGISTRY}"
    echo "  Organization: ${DOCKER_ORG}"
    echo "  Push: ${PUSH_IMAGES}"
    echo "  No Cache: ${NO_CACHE}"
    [[ -n "${PLATFORM}" ]] && echo "  Platform: ${PLATFORM}"
    echo ""

    check_dependencies

    local exit_code=0

    case "${BUILD_COMPONENT}" in
        mcp)
            if ! build_mcp; then
                exit_code=1
            fi
            ;;
        a2a)
            if ! build_a2a; then
                exit_code=1
            fi
            ;;
        all)
            if ! build_mcp; then
                exit_code=1
            fi
            if ! build_a2a; then
                exit_code=1
            fi
            ;;
    esac

    show_build_summary

    if [[ ${exit_code} -eq 0 ]]; then
        log_info "Docker build completed successfully!"
    else
        log_error "Docker build completed with errors"
    fi

    exit ${exit_code}
}

main "$@"
