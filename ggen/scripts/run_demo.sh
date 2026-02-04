#!/bin/bash

# A2A Comprehensive Demo System Runner
# This script runs the comprehensive demo system with various options

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

# Check if erl is available
check_erlang() {
    if ! command -v erl &> /dev/null; then
        log_error "Erlang/OTP is not installed. Please install Erlang 27.0 or later."
        exit 1
    fi

    log_info "Erlang version: $(erl -eval 'io:format(erlang:system_info(otp_release)), halt().' -noshell)"
}

# Check if required files exist
check_files() {
    local required_files=(
        "demo_comprehensive.erl"
        "test_validation.erl"
        "src/ggen_generator.erl"
        "Makefile"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done

    log_success "All required files found"
}

# Compile Erlang modules
compile_erlang() {
    log_info "Compiling Erlang modules..."
    make clean
    make compile
    log_success "Erlang modules compiled successfully"
}

# Run specific demo
run_demo() {
    local demo_type="$1"

    log_info "Running $demo_type demo..."

    case $demo_type in
        "all")
            erl -pa ebin -eval "demo_comprehensive:main([demo, all])" -s init stop
            ;;
        "erlang")
            erl -pa ebin -eval "demo_comprehensive:main([demo, erlang])" -s init stop
            ;;
        "advanced")
            erl -pa ebin -eval "demo_comprehensive:main([demo, advanced])" -s init stop
            ;;
        "cloud")
            erl -pa ebin -eval "demo_comprehensive:main([demo, cloud])" -s init stop
            ;;
        "hotci")
            erl -pa ebin -eval "demo_comprehensive:main([demo, hotci])" -s init stop
            ;;
        "integration")
            erl -pa ebin -eval "demo_comprehensive:main([demo, integration])" -s init stop
            ;;
        *)
            log_error "Unknown demo type: $demo_type"
            show_help
            exit 1
            ;;
    esac
}

# Run tests
run_tests() {
    log_info "Running test suite..."

    case $1 in
        "all")
            erl -pa ebin -eval "test_validation:main([test, all])" -s init stop
            ;;
        "syntax")
            erl -pa ebin -eval "test_validation:main([test, syntax])" -s init stop
            ;;
        "logic")
            erl -pa ebin -eval "test_validation:main([test, logic])" -s init stop
            ;;
        "integration")
            erl -pa ebin -eval "test_validation:main([test, integration])" -s init stop
            ;;
        "performance")
            erl -pa ebin -eval "test_validation:main([test, performance])" -s init stop
            ;;
        *)
            erl -pa ebin -eval "test_validation:main([test])" -s init stop
            ;;
    esac
}

# Generate scenarios
generate_scenarios() {
    log_info "Generating all scenarios..."
    erl -pa ebin -eval "demo_comprehensive:main([generate])" -s init stop
    log_success "All scenarios generated"
}

# Validate code
validate_code() {
    log_info "Validating generated code..."
    erl -pa ebin -eval "test_validation:main([validate])" -s init stop
    log_success "Code validation completed"
}

# Clean generated files
clean_generated() {
    log_info "Cleaning generated files..."
    rm -rf generated/*
    rm -f demo_*.json
    make clean
    log_success "Generated files cleaned"
}

# Show help
show_help() {
    cat << EOF
A2A Comprehensive Demo System Runner

Usage: $0 [command] [option]

Commands:
  demo [type]         Run a demo
    all               Run all demos
    erlang            Run Erlang demo
    advanced          Run advanced demo
    cloud             Run cloud demo
    hotci             Run HotCI demo
    integration       Run integration demo

  test [type]         Run tests
    all               Run all tests
    syntax            Run syntax tests
    logic             Run logic tests
    integration       Run integration tests
    performance       Run performance tests

  generate            Generate all scenarios
  validate            Validate generated code
  clean               Clean generated files
  help               Show this help

Examples:
  $0 demo all          # Run all demos
  $0 test syntax       # Run syntax tests
  $0 generate          # Generate all scenarios
  $0 validate          # Validate code
EOF
}

# Main script execution
main() {
    local command="$1"
    local option="$2"

    # Check if we're in the correct directory
    if [ ! -f "demo_comprehensive.erl" ]; then
        log_error "Please run this script from the ggen directory"
        exit 1
    fi

    # Check Erlang installation
    check_erlang

    # Check required files
    check_files

    # Compile Erlang modules
    compile_erlang

    # Execute command
    case $command in
        "demo")
            run_demo "$option"
            ;;
        "test")
            run_tests "$option"
            ;;
        "generate")
            generate_scenarios
            ;;
        "validate")
            validate_code
            ;;
        "clean")
            clean_generated
            ;;
        "help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"