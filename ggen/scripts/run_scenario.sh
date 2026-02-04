#!/bin/bash

# A2A Scenario Runner
# This script runs specific generation scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required files exist
check_scenario_files() {
    local scenario="$1"
    local scenario_file="scenarios/scenario_${scenario}.erl"

    if [ ! -f "$scenario_file" ]; then
        log_error "Scenario file not found: $scenario_file"
        exit 1
    fi

    log_success "Scenario file found: $scenario_file"
}

# Run specific scenario
run_scenario() {
    local scenario="$1"
    local output_dir="$2"
    local extra_args="$3"

    log_info "Running scenario: $scenario"

    # Check scenario file
    check_scenario_files "$scenario"

    # Compile scenario module
    log_info "Compiling scenario module..."
    erl -pa ebin -eval "c(scenario_${scenario}), scenario_${scenario}:main([$extra_args])" -s init stop

    log_success "Scenario '$scenario' completed"
}

# Show scenario help
show_scenario_help() {
    cat << EOF
A2A Scenario Runner

Usage: $0 [scenario] [option]

Available Scenarios:
  basic              Basic module generation
  advanced           Advanced generation with HotCI

Options:
  --output-dir DIR   Specify output directory
  --help            Show this help

Examples:
  $0 basic               # Run basic scenario
  $0 advanced            # Run advanced scenario
  $0 basic --output-dir my_project/  # Custom output directory

Environment Variables:
  SCENARIO_OUTPUT_DIR  Default output directory
EOF
}

# List available scenarios
list_scenarios() {
    log_info "Available scenarios:"
    for scenario_file in scenarios/scenario_*.erl; do
        if [ -f "$scenario_file" ]; then
            local scenario=$(basename "$scenario_file" .erl | sed 's/scenario_//')
            echo "  - $scenario"
        fi
    done
}

# Main script execution
main() {
    local scenario="$1"
    local output_dir="$2"
    local extra_args=""

    # Check if we're in the correct directory
    if [ ! -f "scenarios" ] || [ ! -d "scenarios" ]; then
        log_error "Please run this script from the ggen directory"
        exit 1
    fi

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --help)
                show_scenario_help
                exit 0
                ;;
            *)
                extra_args="$extra_args $1"
                shift
                ;;
        esac
    done

    # Handle no arguments
    if [ -z "$scenario" ]; then
        log_info "No scenario specified. Available scenarios:"
        list_scenarios
        echo
        show_scenario_help
        exit 0
    fi

    # Check if scenario exists
    local scenario_file="scenarios/scenario_${scenario}.erl"
    if [ ! -f "$scenario_file" ]; then
        log_error "Scenario '$scenario' not found"
        echo
        list_scenarios
        exit 1
    fi

    # Set default output directory
    if [ -z "$output_dir" ]; then
        output_dir="generated/${scenario}/"
    fi

    # Run scenario
    run_scenario "$scenario" "$output_dir" "\"${output_dir}\" ${extra_args}"
}

# Run main function with all arguments
main "$@"