#!/usr/bin/env bash
# =============================================================================
# Craftplan A2A Agent Build Script
# =============================================================================
#
# This script builds the Craftplan A2A agent release with error handling.
#
# Usage:
#   ./build-a2a.sh [--clean] [--debug]
#
# Options:
#   --clean   Clean build artifacts before building
#   --debug   Enable debug output
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
A2A_AGENT_DIR="${PROJECT_ROOT}/a2a-agent"
CLEAN_BUILD=false
DEBUG=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $*" >&2
    fi
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build the Craftplan A2A agent release.

OPTIONS:
    --clean   Clean build artifacts before building
    --debug   Enable debug output
    -h        Show this help message

EXAMPLES:
    $(basename "$0")              # Build release
    $(basename "$0") --clean      # Clean and build
    $(basename "$0") --debug      # Build with debug output

EOF
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v rebar3 &> /dev/null; then
        missing_deps+=("rebar3")
    fi

    if ! command -v erl &> /dev/null; then
        missing_deps+=("erlang")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install required dependencies and try again."
        exit 1
    fi

    debug "All dependencies found"
}

validate_project_structure() {
    log_info "Validating project structure..."

    if [[ ! -d "${A2A_AGENT_DIR}" ]]; then
        log_error "A2A agent directory not found: ${A2A_AGENT_DIR}"
        exit 1
    fi

    local required_files=(
        "${A2A_AGENT_DIR}/rebar.config"
        "${A2A_AGENT_DIR}/src"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -e "${file}" ]]; then
            log_error "Required file/directory not found: ${file}"
            exit 1
        fi
    done

    debug "Project structure validated"
}

clean_build() {
    if [[ "${CLEAN_BUILD}" == "true" ]]; then
        log_info "Cleaning build artifacts..."
        cd "${A2A_AGENT_DIR}"
        rebar3 clean || {
            log_error "Failed to clean build artifacts"
            exit 1
        }
        log_info "Clean completed"
    fi
}

build_release() {
    log_info "Building A2A agent release..."
    cd "${A2A_AGENT_DIR}"

    debug "Running: rebar3 compile"
    rebar3 compile || {
        log_error "Compilation failed"
        exit 1
    }

    debug "Running: rebar3 release -s craftplan_a2a"
    rebar3 release -s craftplan_a2a || {
        log_error "Release creation failed"
        exit 1
    }

    log_info "Release built successfully"
}

show_release_info() {
    local release_dir="${A2A_AGENT_DIR}/_build/default/rel/craftplan_a2a"

    if [[ ! -d "${release_dir}" ]]; then
        log_error "Release directory not found: ${release_dir}"
        exit 1
    fi

    log_info "Release information:"
    echo "  Location: ${release_dir}"
    echo "  Size: $(du -sh "${release_dir}" | cut -f1)"
    echo ""
    echo "To start the A2A agent:"
    echo "  cd ${release_dir}"
    echo "  ./bin/craftplan_a2a foreground"
    echo ""
    echo "To run as daemon:"
    echo "  cd ${release_dir}"
    echo "  ./bin/craftplan_a2a start"
    echo "  ./bin/craftplan_a2a stop"
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean)
                CLEAN_BUILD=true
                shift
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

    log_info "Starting A2A agent build..."
    debug "Project root: ${PROJECT_ROOT}"
    debug "A2A agent dir: ${A2A_AGENT_DIR}"

    check_dependencies
    validate_project_structure
    clean_build
    build_release
    show_release_info

    log_info "Build completed successfully!"
}

main "$@"
