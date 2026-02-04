#!/bin/bash

# @doc Verification script for test structure
# Checks that all required test files and directories are present

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

print_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_NC} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1"
}

# Function to check if a file exists
check_file() {
    if [ -f "$1" ]; then
        print_success "✓ $1"
    else
        print_error "✗ $1"
        return 1
    fi
}

# Function to check if a directory exists
check_dir() {
    if [ -d "$1" ]; then
        print_success "✓ $1"
    else
        print_error "✗ $1"
        return 1
    fi
}

echo "Verifying Craftplan MCP + A2A Test Structure"
echo "==========================================="

# Check test directories
echo -e "\n1. Checking test directories:"
check_dir "/Users/sac/A2A/craftplan/mcp-server/test"
check_dir "/Users/sac/A2A/craftplan/a2a-agent/test"
check_dir "/Users/sac/A2A/craftplan/test"

# Check MCP server test files
echo -e "\n2. Checking MCP server test files:"
check_file "/Users/sac/A2A/craftplan/mcp-server/test/craftplan_mcp_server_tests.erl"
check_file "/Users/sac/A2A/craftplan/mcp-server/test/craftplan_api_client_tests.erl"
check_file "/Users/sac/A2A/craftplan/mcp-server/test/craftplan_test_support.erl"
check_file "/Users/sac/A2A/craftplan/mcp-server/test/cover.spec"

# Check A2A agent test files
echo -e "\n3. Checking A2A agent test files:"
check_file "/Users/sac/A2A/craftplan/a2a-agent/test/craftplan_a2a_server_tests.erl"
check_file "/Users/sac/A2A/craftplan/a2a-agent/test/craftplan_task_handler_tests.erl"
check_file "/Users/sac/A2A/craftplan/a2a-agent/test/craftplan_agent_card_tests.erl"
check_file "/Users/sac/A2A/craftplan/a2a-agent/test/craftplan_test_support.erl"
check_file "/Users/sac/A2A/craftplan/a2a-agent/test/cover.spec"

# Check integration test files
echo -e "\n4. Checking integration test files:"
check_file "/Users/sac/A2A/craftplan/test/craftplan_integration_tests.erl"

# Check script files
echo -e "\n5. Checking script files:"
check_file "/Users/sac/A2A/craftplan/test/run_tests.sh"
check_file "/Users/sac/A2A/craftplan/test/verify_test_structure.sh"

# Check rebar config files
echo -e "\n6. Checking rebar config files:"
check_file "/Users/sac/A2A/craftplan/mcp-server/rebar.config"
check_file "/Users/sac/A2A/craftplan/a2a-agent/rebar.config"

echo -e "\n==========================================="
echo "Test structure verification complete!"