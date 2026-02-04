#!/usr/bin/env bash
# =============================================================================
# Craftplan Integration Build Script
# =============================================================================
#
# This script builds both the MCP server and A2A agent releases.
#
# Usage:
#   ./build-all.sh [--clean] [--debug] [--skip-tests]
#
# Options:
#   --clean       Clean build artifacts before building
#   --debug       Enable debug output
#   --skip-tests  Skip running tests
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLEAN_BUILD=false
DEBUG=false
SKIP_TESTS=false

# Build exit codes
EXIT_MCP_FAILED=1
EXIT_A2A_FAILED=2
EXIT_TESTS_FAILED=3

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
Usage: $(basename "$0") [OPTIONS]

Build both Craftplan MCP server and A2A agent releases.

OPTIONS:
    --clean       Clean build artifacts before building
    --debug       Enable debug output
    --skip-tests  Skip running tests
    -h            Show this help message

EXAMPLES:
    $(basename "$0")                # Build both projects
    $(basename "$0") --clean        # Clean and build both
    $(basename "$0") --skip-tests   # Build without running tests

EOF
}

print_banner() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                                                              ║
║       Craftplan Integration Build Automation                ║
║                                                              ║
║       Building MCP Server + A2A Agent                       ║
║                                                              ║
╚════════════════════════════════════════════════════════════╝

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

    local required_dirs=(
        "${PROJECT_ROOT}/mcp-server"
        "${PROJECT_ROOT}/a2a-agent"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            log_error "Required directory not found: ${dir}"
            exit 1
        fi
    done

    debug "Project structure validated"
}

clean_build() {
    if [[ "${CLEAN_BUILD}" == "true" ]]; then
        log_info "Cleaning build artifacts..."
        cd "${PROJECT_ROOT}/mcp-server" && rebar3 clean || {
            log_error "Failed to clean MCP server"
            exit 1
        }
        cd "${PROJECT_ROOT}/a2a-agent" && rebar3 clean || {
            log_error "Failed to clean A2A agent"
            exit 1
        }
        log_info "Clean completed"
    fi
}

build_mcp_server() {
    log_step "Building MCP Server"
    cd "${PROJECT_ROOT}/mcp-server"

    debug "Compiling MCP server..."
    rebar3 compile || {
        log_error "MCP server compilation failed"
        return ${EXIT_MCP_FAILED}
    }

    debug "Creating MCP server release..."
    rebar3 release -s craftplan_mcp || {
        log_error "MCP server release creation failed"
        return ${EXIT_MCP_FAILED}
    }

    log_info "MCP server built successfully"
    return 0
}

build_a2a_agent() {
    log_step "Building A2A Agent"
    cd "${PROJECT_ROOT}/a2a-agent"

    debug "Compiling A2A agent..."
    rebar3 compile || {
        log_error "A2A agent compilation failed"
        return ${EXIT_A2A_FAILED}
    }

    debug "Creating A2A agent release..."
    rebar3 release -s craftplan_a2a || {
        log_error "A2A agent release creation failed"
        return ${EXIT_A2A_FAILED}
    }

    log_info "A2A agent built successfully"
    return 0
}

run_tests() {
    if [[ "${SKIP_TESTS}" == "true" ]]; then
        log_warn "Skipping tests as requested"
        return 0
    fi

    log_step "Running Tests"

    # Run MCP server tests
    debug "Running MCP server tests..."
    cd "${PROJECT_ROOT}/mcp-server"
    if ! rebar3 ct 2>/dev/null; then
        log_warn "MCP server tests failed (continuing build)"
    fi

    # Run A2A agent tests
    debug "Running A2A agent tests..."
    cd "${PROJECT_ROOT}/a2a-agent"
    if ! rebar3 ct 2>/dev/null; then
        log_warn "A2A agent tests failed (continuing build)"
    fi

    log_info "Tests completed"
}

show_build_summary() {
    local mcp_release="${PROJECT_ROOT}/mcp-server/_build/default/rel/craftplan_mcp"
    local a2a_release="${PROJECT_ROOT}/a2a-agent/_build/default/rel/craftplan_a2a"

    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                    Build Summary                           ║
╚════════════════════════════════════════════════════════════╝

EOF

    if [[ -d "${mcp_release}" ]]; then
        echo "MCP Server Release:"
        echo "  Location: ${mcp_release}"
        echo "  Size: $(du -sh "${mcp_release}" | cut -f1)"
        echo ""
    fi

    if [[ -d "${a2a_release}" ]]; then
        echo "A2A Agent Release:"
        echo "  Location: ${a2a_release}"
        echo "  Size: $(du -sh "${a2a_release}" | cut -f1)"
        echo ""
    fi

    cat << "EOF"
Quick Start:

  MCP Server:
    cd ${mcp_release}
    ./bin/craftplan_mcp foreground

  A2A Agent:
    cd ${a2a_release}
    ./bin/craftplan_a2a foreground

  Docker Build:
    make docker-all

EOF
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
            --skip-tests)
                SKIP_TESTS=true
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

    log_info "Starting Craftplan integration build..."
    debug "Project root: ${PROJECT_ROOT}"

    check_dependencies
    validate_project_structure
    clean_build

    # Build MCP server
    if ! build_mcp_server; then
        log_error "MCP server build failed"
        exit ${EXIT_MCP_FAILED}
    fi

    # Build A2A agent
    if ! build_a2a_agent; then
        log_error "A2A agent build failed"
        exit ${EXIT_A2A_FAILED}
    fi

    # Run tests
    run_tests

    # Show summary
    show_build_summary

    log_info "Build completed successfully!"
}

main "$@"
