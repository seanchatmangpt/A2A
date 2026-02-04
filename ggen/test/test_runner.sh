#!/bin/bash

# GGen Test Runner
# Comprehensive test runner for ggen system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_DIR="test"
EBIN_DIR="ebin"
REBAR3="rebar3"
ERLC="erlc"
ERL="erl"

# Test categories
UNIT_TESTS="unit"
INTEGRATION_TESTS="integration"
VALIDATION_TESTS="validation"
PERFORMANCE_TESTS="performance"

# Global variables
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local color=$3

    case $status in
        "SUCCESS") echo -e "${color}✅ $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "START") echo -e "${GREEN}🚀 $message${NC}" ;;
    esac
}

# Function to check if required tools are available
check_requirements() {
    print_status "INFO" "Checking requirements..."

    # Check if erlang is installed
    if ! command -v $ERL &> /dev/null; then
        print_status "ERROR" "Erlang is not installed or not in PATH"
        exit 1
    fi

    # Check if erlc is installed
    if ! command -v $ERLC &> /dev/null; then
        print_status "ERROR" "Erlang compiler (erlc) is not installed or not in PATH"
        exit 1
    fi

    # Check if rebar3 is available (optional for some tests)
    if [ "$REBAR3" != "" ]; then
        if ! command -v $REBAR3 &> /dev/null; then
            print_status "WARNING" "rebar3 is not available, skipping some tests"
            REBAR3=""
        fi
    fi

    print_status "SUCCESS" "All requirements met"
}

# Function to create ebin directory
setup_ebin() {
    if [ ! -d "$EBIN_DIR" ]; then
        mkdir -p "$EBIN_DIR"
        print_status "INFO" "Created ebin directory"
    fi
}

# Function to compile a single file
compile_erlang_file() {
    local file=$1

    if [ -f "$file" ]; then
        local beam_file="$EBIN_DIR/$(basename "$file" .erl).beam"

        if $ERLC -o "$EBIN_DIR" "$file"; then
            print_status "SUCCESS" "Compiled: $file"
            return 0
        else
            print_status "ERROR" "Failed to compile: $file"
            return 1
        fi
    else
        print_status "ERROR" "File not found: $file"
        return 1
    fi
}

# Function to run eunit tests
run_eunit_test() {
    local test_file=$1
    local module_name=$(basename "$test_file" .erl)

    print_status "START" "Running EUnit test: $module_name"

    # Compile the test file
    if ! compile_erlang_file "$test_file"; then
        return 1
    fi

    # Run the test using erl
    $ERL -noshell -pa "$EBIN_DIR" \
         -eval "eunit:test($module_name, [verbose])" \
         -s init stop > "${test_file}.log" 2>&1

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        print_status "SUCCESS" "EUnit test passed: $module_name"
        return 0
    else
        print_status "ERROR" "EUnit test failed: $module_name"
        print_status "INFO" "Test log saved to: ${test_file}.log"
        return 1
    fi
}

# Function to run unit tests
run_unit_tests() {
    print_status "START" "Running unit tests..."

    local test_files=()

    # Find all unit test files
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$TEST_DIR/$UNIT_TESTS" -name "*_tests.erl" -print0)

    if [ ${#test_files[@]} -eq 0 ]; then
        print_status "WARNING" "No unit test files found"
        return 0
    fi

    local passed=0
    local failed=0

    for test_file in "${test_files[@]}"; do
        if run_eunit_test "$test_file"; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))
    PASSED_TESTS=$((PASSED_TESTS + passed))
    FAILED_TESTS=$((FAILED_TESTS + failed))

    if [ $failed -eq 0 ]; then
        print_status "SUCCESS" "All unit tests passed ($passed/$((passed + failed)))"
    else
        print_status "ERROR" "Some unit tests failed ($passed passed, $failed failed)"
    fi
}

# Function to run integration tests
run_integration_tests() {
    print_status "START" "Running integration tests..."

    local test_files=()

    # Find all integration test files
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$TEST_DIR/$INTEGRATION_TESTS" -name "*_tests.erl" -print0)

    if [ ${#test_files[@]} -eq 0 ]; then
        print_status "WARNING" "No integration test files found"
        return 0
    fi

    local passed=0
    local failed=0

    for test_file in "${test_files[@]}"; do
        if run_eunit_test "$test_file"; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))
    PASSED_TESTS=$((PASSED_TESTS + passed))
    FAILED_TESTS=$((FAILED_TESTS + failed))

    if [ $failed -eq 0 ]; then
        print_status "SUCCESS" "All integration tests passed ($passed/$((passed + failed)))"
    else
        print_status "ERROR" "Some integration tests failed ($passed passed, $failed failed)"
    fi
}

# Function to run validation tests
run_validation_tests() {
    print_status "START" "Running validation tests..."

    local test_files=()

    # Find all validation test files
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$TEST_DIR/$VALIDATION_TESTS" -name "*_tests.erl" -print0)

    if [ ${#test_files[@]} -eq 0 ]; then
        print_status "WARNING" "No validation test files found"
        return 0
    fi

    local passed=0
    local failed=0

    for test_file in "${test_files[@]}"; do
        if run_eunit_test "$test_file"; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))
    PASSED_TESTS=$((PASSED_TESTS + passed))
    FAILED_TESTS=$((FAILED_TESTS + failed))

    if [ $failed -eq 0 ]; then
        print_status "SUCCESS" "All validation tests passed ($passed/$((passed + failed)))"
    else
        print_status "ERROR" "Some validation tests failed ($passed passed, $failed failed)"
    fi
}

# Function to run performance tests
run_performance_tests() {
    print_status "START" "Running performance tests..."

    local test_files=()

    # Find all performance test files
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$TEST_DIR/$PERFORMANCE_TESTS" -name "*_tests.erl" -print0)

    if [ ${#test_files[@]} -eq 0 ]; then
        print_status "WARNING" "No performance test files found"
        return 0
    fi

    local passed=0
    local failed=0

    for test_file in "${test_files[@]}"; do
        if run_eunit_test "$test_file"; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))
    PASSED_TESTS=$((PASSED_TESTS + passed))
    FAILED_TESTS=$((FAILED_TESTS + failed))

    if [ $failed -eq 0 ]; then
        print_status "SUCCESS" "All performance tests passed ($passed/$((passed + failed)))"
    else
        print_status "ERROR" "Some performance tests failed ($passed passed, $failed failed)"
    fi
}

# Function to clean up test artifacts
cleanup() {
    print_status "INFO" "Cleaning up test artifacts..."

    # Remove beam files
    if [ -d "$EBIN_DIR" ]; then
        rm -rf "$EBIN_DIR"
    fi

    # Remove test output directories
    rm -rf "test_output" "validation_test_output" "performance_test_output" "integration_test_workspace"

    # Remove log files
    find "$TEST_DIR" -name "*.log" -delete

    print_status "SUCCESS" "Cleanup completed"
}

# Function to generate test report
generate_test_report() {
    print_status "INFO" "Generating test report..."

    local report_file="test_report.txt"

    cat > "$report_file" << EOF
GGen Test Report
================

Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS

$(date)

Test Categories:
- Unit Tests: $PASSED_UNIT_TESTS/$((PASSED_UNIT_TESTS + FAILED_UNIT_TESTS))
- Integration Tests: $PASSED_INTEGRATION_TESTS/$((PASSED_INTEGRATION_TESTS + FAILED_INTEGRATION_TESTS))
- Validation Tests: $PASSED_VALIDATION_TESTS/$((PASSED_VALIDATION_TESTS + FAILED_VALIDATION_TESTS))
- Performance Tests: $PASSED_PERFORMANCE_TESTS/$((PASSED_PERFORMANCE_TESTS + FAILED_PERFORMANCE_TESTS))

EOF

    print_status "SUCCESS" "Test report saved to: $report_file"
}

# Function to show help
show_help() {
    echo "GGen Test Runner"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -u, --unit          Run only unit tests"
    echo "  -i, --integration   Run only integration tests"
    echo "  -v, --validation    Run only validation tests"
    echo "  -p, --performance   Run only performance tests"
    echo "  -a, --all           Run all tests (default)"
    echo "  -c, --clean         Clean up test artifacts"
    echo "  -r, --report        Generate test report"
    echo ""
    echo "Examples:"
    echo "  $0 --unit"
    echo "  $0 --integration"
    echo "  $0 --clean"
    echo "  $0 --all --report"
}

# Main function
main() {
    print_status "START" "Starting GGen test suite..."

    # Parse command line arguments
    local run_all=true
    local run_clean=false
    local run_report=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -u|--unit)
                run_all=false
                run_unit=true
                shift
                ;;
            -i|--integration)
                run_all=false
                run_integration=true
                shift
                ;;
            -v|--validation)
                run_all=false
                run_validation=true
                shift
                ;;
            -p|--performance)
                run_all=false
                run_performance=true
                shift
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -c|--clean)
                run_clean=true
                shift
                ;;
            -r|--report)
                run_report=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check requirements
    check_requirements

    # Setup
    setup_ebin

    # Clean up if requested
    if [ "$run_clean" = true ]; then
        cleanup
    fi

    # Run tests
    if [ "$run_all" = true ]; then
        run_unit_tests
        run_integration_tests
        run_validation_tests
        run_performance_tests
    else
        if [ "$run_unit" = true ]; then
            run_unit_tests
        fi
        if [ "$run_integration" = true ]; then
            run_integration_tests
        fi
        if [ "$run_validation" = true ]; then
            run_validation_tests
        fi
        if [ "$run_performance" = true ]; then
            run_performance_tests
        fi
    fi

    # Generate report if requested
    if [ "$run_report" = true ]; then
        generate_test_report
    fi

    # Final summary
    print_status "INFO" "Test execution completed"
    print_status "INFO" "Total tests: $TOTAL_TESTS"
    print_status "INFO" "Passed: $PASSED_TESTS"
    print_status "INFO" "Failed: $FAILED_TESTS"

    if [ $FAILED_TESTS -eq 0 ]; then
        print_status "SUCCESS" "All tests passed!"
        exit 0
    else
        print_status "ERROR" "Some tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"