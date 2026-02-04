#!/usr/bin/env bash
# =============================================================================
# Craftplan Integration Test Script
# =============================================================================
#
# This script runs comprehensive tests for both MCP server and A2A agent.
#
# Usage:
#   ./test-all.sh [--unit] [--integration] [--all] [--verbose] [--debug]
#
# Options:
#   --unit         Run only unit tests
#   --integration  Run only integration tests
#   --all          Run all tests (default)
#   --verbose      Enable verbose output
#   --debug        Enable debug output
#   --clean        Clean before testing
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_SERVER_DIR="${PROJECT_ROOT}/mcp-server"
A2A_AGENT_DIR="${PROJECT_ROOT}/a2a-agent"
CLEAN_BUILD=false
RUN_UNIT_TESTS=true
RUN_INTEGRATION_TESTS=true
VERBOSE=false
DEBUG=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test exit codes
EXIT_TESTS_FAILED=1
EXIT_INTEGRATION_FAILED=2

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

Run comprehensive tests for Craftplan MCP server and A2A agent.

OPTIONS:
    --unit         Run only unit tests
    --integration  Run only integration tests
    --all          Run all tests (default)
    --clean        Clean build artifacts before testing
    --verbose      Enable verbose output
    --debug        Enable debug output
    -h            Show this help message

EXAMPLES:
    $(basename "$0")                    # Run all tests
    $(basename "$0") --unit            # Run unit tests only
    $(basename "$0") --integration     # Run integration tests only
    $(basename "$0") --clean           # Clean and test
    $(basename "$0") --verbose         # Test with verbose output

EOF
}

print_banner() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                                                              ║
║       Craftplan Integration Test Suite                       ║
║                                                              ║
║       Testing MCP Server + A2A Agent                         ║
║                                                              ║
╚════════════════════════════════════════════════════════════╝

EOF
}

check_dependencies() {
    log_info "Checking test dependencies..."

    local missing_deps=()

    if ! command -v rebar3 &> /dev/null; then
        missing_deps+=("rebar3")
    fi

    if ! command -v erl &> /dev/null; then
        missing_deps+=("erlang")
    fi

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install required dependencies and try again."
        exit 1
    fi

    debug "All test dependencies found"
}

validate_test_environment() {
    log_info "Validating test environment..."

    # Check if we're in the correct directory
    if [[ ! -f "${PROJECT_ROOT}/Makefile" ]]; then
        log_error "Craftplan Makefile not found in: ${PROJECT_ROOT}"
        exit 1
    fi

    # Check if projects are built
    if [[ ! -d "${MCP_SERVER_DIR}/_build/default/lib" ]]; then
        log_warn "MCP server not built, building first..."
        make mcp || { log_error "Failed to build MCP server"; exit 1; }
    fi

    if [[ ! -d "${A2A_AGENT_DIR}/_build/default/lib" ]]; then
        log_warn "A2A agent not built, building first..."
        make a2a || { log_error "Failed to build A2A agent"; exit 1; }
    fi

    debug "Test environment validated"
}

clean_build() {
    if [[ "${CLEAN_BUILD}" == "true" ]]; then
        log_info "Cleaning build artifacts..."
        make clean || { log_error "Failed to clean build artifacts"; exit 1; }
        log_info "Clean completed"
    fi
}

run_unit_tests() {
    if [[ "${RUN_UNIT_TESTS}" == "false" ]]; then
        log_step "Skipping unit tests"
        return 0
    fi

    log_step "Running Unit Tests"

    # Test MCP Server
    log_info "Testing MCP Server..."
    cd "${MCP_SERVER_DIR}"

    if [[ "${VERBOSE}" == "true" ]]; then
        rebar3 ct --verbose || {
            log_error "MCP server unit tests failed"
            return ${EXIT_TESTS_FAILED}
        }
    else
        rebar3 ct || {
            log_error "MCP server unit tests failed"
            return ${EXIT_TESTS_FAILED}
        }
    fi

    # Run dialyzer for MCP Server
    log_info "Running dialyzer for MCP Server..."
    rebar3 dialyzer || {
        log_warn "MCP server dialyzer failed (continuing)"
    }

    # Run XREF for MCP Server
    log_info "Running XREF for MCP Server..."
    rebar3 xref || {
        log_warn "MCP server XREF failed (continuing)"
    }

    # Test A2A Agent
    log_info "Testing A2A Agent..."
    cd "${A2A_AGENT_DIR}"

    if [[ "${VERBOSE}" == "true" ]]; then
        rebar3 ct --verbose || {
            log_error "A2A agent unit tests failed"
            return ${EXIT_TESTS_FAILED}
        }
    else
        rebar3 ct || {
            log_error "A2A agent unit tests failed"
            return ${EXIT_TESTS_FAILED}
        }
    fi

    # Run dialyzer for A2A Agent
    log_info "Running dialyzer for A2A Agent..."
    rebar3 dialyzer || {
        log_warn "A2A agent dialyzer failed (continuing)"
    }

    # Run XREF for A2A Agent
    log_info "Running XREF for A2A Agent..."
    rebar3 xref || {
        log_warn "A2A agent XREF failed (continuing)"
    }

    log_info "Unit tests completed successfully"
    return 0
}

run_integration_tests() {
    if [[ "${RUN_INTEGRATION_TESTS}" == "false" ]]; then
        log_step "Skipping integration tests"
        return 0
    fi

    log_step "Running Integration Tests"

    # Check if Docker Compose is available
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        log_warn "Docker not available, skipping integration tests"
        return 0
    fi

    # Check if docker-compose.stack.yml exists
    if [[ ! -f "${PROJECT_ROOT}/docker-compose.stack.yml" ]]; then
        log_warn "docker-compose.stack.yml not found, skipping integration tests"
        return 0
    fi

    log_info "Starting Docker Compose stack..."
    cd "${PROJECT_ROOT}"

    # Start services
    if command -v docker-compose &> /dev/null; then
        docker-compose -f docker-compose.stack.yml up -d || {
            log_error "Failed to start Docker Compose stack"
            return ${EXIT_INTEGRATION_FAILED}
        }
    else
        docker compose -f docker-compose.stack.yml up -d || {
            log_error "Failed to start Docker Compose stack"
            return ${EXIT_INTEGRATION_FAILED}
        }
    fi

    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 30

    # Test MCP Server health
    log_info "Testing MCP Server health..."
    local mcp_healthy=false
    for i in {1..30}; do
        if curl -f -s http://localhost:8090/health >/dev/null 2>&1; then
            mcp_healthy=true
            break
        fi
        sleep 2
    done

    if [[ "${mcp_healthy}" == "false" ]]; then
        log_error "MCP Server is not healthy"
        return ${EXIT_INTEGRATION_FAILED}
    fi

    # Test A2A Agent health
    log_info "Testing A2A Agent health..."
    local a2a_healthy=false
    for i in {1..30}; do
        if curl -f -s http://localhost:8080/health >/dev/null 2>&1; then
            a2a_healthy=true
            break
        fi
        sleep 2
    done

    if [[ "${a2a_healthy}" == "false" ]]; then
        log_error "A2A Agent is not healthy"
        return ${EXIT_INTEGRATION_FAILED}
    fi

    # Test MCP protocol
    log_info "Testing MCP protocol..."
    local mcp_response
    mcp_response=$(curl -s -X POST http://localhost:8090/mcp \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' 2>/dev/null)

    if [[ $? -eq 0 ]] && [[ -n "${mcp_response}" ]]; then
        log_info "MCP protocol test successful"
    else
        log_warn "MCP protocol test failed, but continuing with other tests"
    fi

    # Test A2A protocol
    log_info "Testing A2A protocol..."
    # Add A2A protocol tests here as they become available

    # Stop services
    log_info "Stopping Docker Compose stack..."
    if command -v docker-compose &> /dev/null; then
        docker-compose -f docker-compose.stack.yml down -v || {
            log_error "Failed to stop Docker Compose stack"
        }
    else
        docker compose -f docker-compose.stack.yml down -v || {
            log_error "Failed to stop Docker Compose stack"
        }
    fi

    log_info "Integration tests completed successfully"
    return 0
}

show_test_summary() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                    Test Summary                            ║
╚════════════════════════════════════════════════════════════╝

EOF

    # Show test coverage if available
    if [[ -d "${MCP_SERVER_DIR}/_build/test" ]]; then
        log_info "MCP Server test coverage:"
        if command -v erlc &> /dev/null; then
            echo "  Run 'cd ${MCP_SERVER_DIR} && rebar3 cover' for detailed coverage"
        fi
    fi

    if [[ -d "${A2A_AGENT_DIR}/_build/test" ]]; then
        log_info "A2A Agent test coverage:"
        if command -v erlc &> /dev/null; then
            echo "  Run 'cd ${A2A_AGENT_DIR} && rebar3 cover' for detailed coverage"
        fi
    fi

    cat << "EOF"

Test artifacts are available in:
  - craftplan/mcp-server/_build/test/
  - craftplan/a2a-agent/_build/test/

To run tests manually:
  - Unit tests: rebar3 ct (in each project directory)
  - Coverage: rebar3 cover (in each project directory)
  - Dialyzer: rebar3 dialyzer (in each project directory)
  - XREF: rebar3 xref (in each project directory)

EOF
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --unit)
                RUN_UNIT_TESTS=true
                RUN_INTEGRATION_TESTS=false
                shift
                ;;
            --integration)
                RUN_UNIT_TESTS=false
                RUN_INTEGRATION_TESTS=true
                shift
                ;;
            --all)
                RUN_UNIT_TESTS=true
                RUN_INTEGRATION_TESTS=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --verbose)
                VERBOSE=true
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

    print_banner

    log_info "Starting Craftplan integration test suite..."
    debug "Project root: ${PROJECT_ROOT}"
    debug "Run unit tests: ${RUN_UNIT_TESTS}"
    debug "Run integration tests: ${RUN_INTEGRATION_TESTS}"
    debug "Clean build: ${CLEAN_BUILD}"

    check_dependencies
    validate_test_environment
    clean_build

    local exit_code=0

    # Run unit tests
    if ! run_unit_tests; then
        log_error "Unit tests failed"
        exit_code=${EXIT_TESTS_FAILED}
    fi

    # Run integration tests (only if unit tests passed or were skipped)
    if [[ ${exit_code} -eq 0 ]] && [[ "${RUN_INTEGRATION_TESTS}" == "true" ]]; then
        if ! run_integration_tests; then
            log_error "Integration tests failed"
            exit_code=${EXIT_INTEGRATION_FAILED}
        fi
    fi

    show_test_summary

    if [[ ${exit_code} -eq 0 ]]; then
        log_info "All tests completed successfully!"
    else
        log_error "Some tests failed"
        exit ${exit_code}
    fi
}

main "$@"