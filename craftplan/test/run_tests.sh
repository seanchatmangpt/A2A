#!/bin/bash

# @doc Test runner script for Craftplan MCP + A2A integration
# Runs unit tests, integration tests, and generates coverage reports

set -e

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $1"
}

print_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_NC} $1"
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1"
}

# Function to run tests for a component
run_component_tests() {
    local component="$1"
    local component_dir="/Users/sac/A2A/craftplan/$component"

    print_status "Running tests for $component..."

    cd "$component_dir"

    # Clean previous builds
    print_status "Cleaning previous builds..."
    rebar3 clean

    # Get dependencies
    print_status "Getting dependencies..."
    rebar3 deps

    # Compile
    print_status "Compiling..."
    rebar3 compile

    # Run unit tests
    print_status "Running unit tests..."
    rebar3 eunit

    # Run proper tests
    if [ -f "test/proper_tests.erl" ]; then
        print_status "Running property-based tests..."
        rebar3 proper
    fi

    # Generate coverage report
    print_status "Generating coverage report..."
    rebar3 cover

    print_success "Tests completed for $component"
}

# Function to run integration tests
run_integration_tests() {
    local integration_dir="/Users/sac/A2A/craftplan/test"

    print_status "Running integration tests..."

    cd "$integration_dir"

    # Clean and compile
    print_status "Compiling integration tests..."
    rebar3 compile

    # Run integration tests
    print_status "Running EUnit tests..."
    erl -pa ebin deps/*/ebin -eval "eunit:test([craftplan_integration_tests], [verbose]), halt(0)"

    print_success "Integration tests completed"
}

# Main test execution
main() {
    print_status "Starting Craftplan MCP + A2A Integration Tests"
    print_status "=================================================="

    # Run tests for MCP server
    run_component_tests "mcp-server"

    # Run tests for A2A agent
    run_component_tests "a2a-agent"

    # Run integration tests
    run_integration_tests

    print_status "=================================================="
    print_success "All tests completed successfully!"

    # Print coverage summary
    print_status "Coverage Reports:"
    echo "  - MCP Server: file:///Users/sac/A2A/craftplan/mcp-server/_build/test/cover/index.html"
    echo "  - A2A Agent: file:///Users/sac/A2A/craftplan/a2a-agent/_build/test/cover/index.html"
}

# Handle script interruption
trap 'print_error "Script interrupted"; exit 1' INT

# Run main function
main "$@"