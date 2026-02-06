#!/bin/bash
# YAWL XES Test Runner
#
# This script runs all XES-related tests and generates a comprehensive
# validation report for IEEE 1849-2016 compliance.
#
# Usage:
#   ./run_xes_tests.sh [options]
#
# Options:
#   --unit           Run unit tests only
#   --integration    Run integration tests only
#   --escript        Run escript validation tests
#   --all            Run all tests (default)
#   --report         Generate test report
#   --verbose        Show detailed output
#
# Examples:
#   ./run_xes_tests.sh
#   ./run_xes_tests.sh --all --report
#   ./run_xes_tests.sh --unit --verbose

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test directories
UNIT_TEST_DIR="$SCRIPT_DIR/unit"
INTEGRATION_TEST_DIR="$SCRIPT_DIR/integration"
REPORT_DIR="$SCRIPT_DIR/reports"

# Test files
XES_LOGGER_TEST="$UNIT_TEST_DIR/yawl_xes_logger_tests.erl"
XES_FORMATTER_TEST="$UNIT_TEST_DIR/yawl_xes_formatter_tests.erl"
XES_INTEGRATION_TEST="$INTEGRATION_TEST_DIR/yawl_xes_integration_tests.erl"
XES_VALIDATION_ESCRIPT="$SCRIPT_DIR/xes_validation.escript"

# Output
VERBOSE=false
GENERATE_REPORT=false
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_ESCRIPT=false
RUN_ALL=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            RUN_UNIT=true
            RUN_ALL=false
            shift
            ;;
        --integration)
            RUN_INTEGRATION=true
            RUN_ALL=false
            shift
            ;;
        --escript)
            RUN_ESCRIPT=true
            RUN_ALL=false
            shift
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "YAWL XES Test Runner"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --unit           Run unit tests only"
            echo "  --integration    Run integration tests only"
            echo "  --escript        Run escript validation tests"
            echo "  --all            Run all tests (default)"
            echo "  --report         Generate test report"
            echo "  --verbose        Show detailed output"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --all --report"
            echo "  $0 --unit --verbose"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to print colored output
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Create report directory
mkdir -p "$REPORT_DIR"

# Start test run
print_header "YAWL XES Test Suite"
echo ""

TEST_START_TIME=$(date +%s)
TEST_DATE=$(date +"%Y-%m-%d %H:%M:%S")

# Report file
if [ "$GENERATE_REPORT" = true ]; then
    REPORT_FILE="$REPORT_DIR/xes_test_report_$(date +%Y%m%d_%H%M%S).txt"
    echo "YAWL XES Test Report" > "$REPORT_FILE"
    echo "====================" >> "$REPORT_FILE"
    echo "Date: $TEST_DATE" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Function to append to report
append_report() {
    if [ "$GENERATE_REPORT" = true ]; then
        echo "$1" >> "$REPORT_FILE"
    fi
}

# ============================================================================
# Run Unit Tests
# ============================================================================

run_unit_tests() {
    print_header "Running Unit Tests"
    echo ""

    UNIT_TESTS_PASSED=0
    UNIT_TESTS_FAILED=0

    # Check if test files exist
    if [ ! -f "$XES_LOGGER_TEST" ]; then
        print_warning "XES Logger test file not found: $XES_LOGGER_TEST"
    else
        append_report "## XES Logger Unit Tests"
        echo "Running: yawl_xes_logger_tests..."

        if [ "$VERBOSE" = true ]; then
            if erl -noshell -pa "$PROJECT_ROOT/ebin" -eval "eunit:test(yawl_xes_logger_tests, [verbose])" -s init stop; then
                print_success "yawl_xes_logger_tests"
                UNIT_TESTS_PASSED=$((UNIT_TESTS_PASSED + 1))
                append_report "  - PASSED"
            else
                print_error "yawl_xes_logger_tests"
                UNIT_TESTS_FAILED=$((UNIT_TESTS_FAILED + 1))
                append_report "  - FAILED"
            fi
        else
            if erl -noshell -pa "$PROJECT_ROOT/ebin" -eval "eunit:test(yawl_xes_logger_tests)" -s init stop 2>/dev/null; then
                print_success "yawl_xes_logger_tests"
                UNIT_TESTS_PASSED=$((UNIT_TESTS_PASSED + 1))
                append_report "  - PASSED"
            else
                print_error "yawl_xes_logger_tests"
                UNIT_TESTS_FAILED=$((UNIT_TESTS_FAILED + 1))
                append_report "  - FAILED"
            fi
        fi
    fi

    if [ ! -f "$XES_FORMATTER_TEST" ]; then
        print_warning "XES Formatter test file not found: $XES_FORMATTER_TEST"
    else
        append_report "## XES Formatter Unit Tests"
        echo "Running: yawl_xes_formatter_tests..."

        if [ "$VERBOSE" = true ]; then
            if erl -noshell -pa "$PROJECT_ROOT/ebin" -eval "eunit:test(yawl_xes_formatter_tests, [verbose])" -s init stop; then
                print_success "yawl_xes_formatter_tests"
                UNIT_TESTS_PASSED=$((UNIT_TESTS_PASSED + 1))
                append_report "  - PASSED"
            else
                print_error "yawl_xes_formatter_tests"
                UNIT_TESTS_FAILED=$((UNIT_TESTS_FAILED + 1))
                append_report "  - FAILED"
            fi
        else
            if erl -noshell -pa "$PROJECT_ROOT/ebin" -eval "eunit:test(yawl_xes_formatter_tests)" -s init stop 2>/dev/null; then
                print_success "yawl_xes_formatter_tests"
                UNIT_TESTS_PASSED=$((UNIT_TESTS_PASSED + 1))
                append_report "  - PASSED"
            else
                print_error "yawl_xes_formatter_tests"
                UNIT_TESTS_FAILED=$((UNIT_TESTS_FAILED + 1))
                append_report "  - FAILED"
            fi
        fi
    fi

    echo ""
    echo "Unit Tests Summary:"
    echo "  Passed: $UNIT_TESTS_PASSED"
    echo "  Failed: $UNIT_TESTS_FAILED"
    append_report ""
    append_report "Unit Tests Summary:"
    append_report "  Passed: $UNIT_TESTS_PASSED"
    append_report "  Failed: $UNIT_TESTS_FAILED"
}

# ============================================================================
# Run Integration Tests
# ============================================================================

run_integration_tests() {
    print_header "Running Integration Tests"
    echo ""

    INTEGRATION_TESTS_PASSED=0
    INTEGRATION_TESTS_FAILED=0

    if [ ! -f "$XES_INTEGRATION_TEST" ]; then
        print_warning "XES Integration test file not found: $XES_INTEGRATION_TEST"
    else
        append_report "## XES Integration Tests"
        echo "Running: yawl_xes_integration_tests..."

        # Compile test if needed
        if [ ! -f "$PROJECT_ROOT/ebin/yawl_xes_integration_tests.beam" ]; then
            echo "Compiling integration tests..."
            erlc -o "$PROJECT_ROOT/ebin" -I "$PROJECT_ROOT/include" "$XES_INTEGRATION_TEST" 2>/dev/null || true
        fi

        # Run with CT
        if [ "$VERBOSE" = true ]; then
            if erl -noshell -pa "$PROJECT_ROOT/ebin" -eval "ct:run_test([{spec, \"$XES_INTEGRATION_TEST\"}])" -s init stop; then
                print_success "yawl_xes_integration_tests"
                INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
                append_report "  - PASSED"
            else
                print_error "yawl_xes_integration_tests"
                INTEGRATION_TESTS_FAILED=$((INTEGRATION_TESTS_FAILED + 1))
                append_report "  - FAILED"
            fi
        else
            if erl -noshell -pa "$PROJECT_ROOT/ebin" -eval "ct:run_test([{spec, \"$XES_INTEGRATION_TEST\"}])" -s init stop 2>/dev/null; then
                print_success "yawl_xes_integration_tests"
                INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
                append_report "  - PASSED"
            else
                print_error "yawl_xes_integration_tests"
                INTEGRATION_TESTS_FAILED=$((INTEGRATION_TESTS_FAILED + 1))
                append_report "  - FAILED"
            fi
        fi
    fi

    echo ""
    echo "Integration Tests Summary:"
    echo "  Passed: $INTEGRATION_TESTS_PASSED"
    echo "  Failed: $INTEGRATION_TESTS_FAILED"
    append_report ""
    append_report "Integration Tests Summary:"
    append_report "  Passed: $INTEGRATION_TESTS_PASSED"
    append_report "  Failed: $INTEGRATION_TESTS_FAILED"
}

# ============================================================================
# Run Escript Validation Tests
# ============================================================================

run_escript_tests() {
    print_header "Running XES Validation Escript"
    echo ""

    ESCRIPT_TESTS_PASSED=0
    ESCRIPT_TESTS_FAILED=0

    if [ ! -f "$XES_VALIDATION_ESCRIPT" ]; then
        print_warning "XES validation escript not found: $XES_VALIDATION_ESCRIPT"
    else
        append_report "## XES Validation Escript Tests"
        chmod +x "$XES_VALIDATION_ESCRIPT"

        # Create sample XES file for validation test
        SAMPLE_XES="$REPORT_DIR/sample.xes"
        cat > "$SAMPLE_XES" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<log xes.version="1.0" xmlns="http://www.xes-standard.org/">
  <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>
  <extension name="Time" prefix="time" uri="http://www.xes-standard.org/time.xesext"/>
  <extension name="Lifecycle" prefix="lifecycle" uri="http://www.xes-standard.org/lifecycle.xesext"/>
  <trace>
    <string key="concept:name" value="Sample Trace"/>
    <event>
      <string key="concept:name" value="Sample Event"/>
      <date key="time:timestamp" value="2024-01-01T00:00:00.000Z"/>
      <string key="lifecycle:transition" value="complete"/>
    </event>
  </trace>
</log>
EOF

        echo "Validating sample XES file..."

        if escript "$XES_VALIDATION_ESCRIPT" "$SAMPLE_XES" ${VERBOSE:+--verbose}; then
            print_success "XES validation escript"
            ESCRIPT_TESTS_PASSED=$((ESCRIPT_TESTS_PASSED + 1))
            append_report "  - Sample XES validation: PASSED"
        else
            print_error "XES validation escript"
            ESCRIPT_TESTS_FAILED=$((ESCRIPT_TESTS_FAILED + 1))
            append_report "  - Sample XES validation: FAILED"
        fi
    fi

    echo ""
    echo "Escript Tests Summary:"
    echo "  Passed: $ESCRIPT_TESTS_PASSED"
    echo "  Failed: $ESCRIPT_TESTS_FAILED"
    append_report ""
    append_report "Escript Tests Summary:"
    append_report "  Passed: $ESCRIPT_TESTS_PASSED"
    append_report "  Failed: $ESCRIPT_TESTS_FAILED"
}

# ============================================================================
# Run All Tests
# ============================================================================

if [ "$RUN_ALL" = true ]; then
    RUN_UNIT=true
    RUN_INTEGRATION=true
    RUN_ESCRIPT=true
fi

if [ "$RUN_UNIT" = true ]; then
    run_unit_tests
    echo ""
fi

if [ "$RUN_INTEGRATION" = true ]; then
    run_integration_tests
    echo ""
fi

if [ "$RUN_ESCRIPT" = true ]; then
    run_escript_tests
    echo ""
fi

# ============================================================================
# Final Summary
# ============================================================================

TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

TOTAL_PASSED=$((UNIT_TESTS_PASSED + INTEGRATION_TESTS_PASSED + ESCRIPT_TESTS_PASSED))
TOTAL_FAILED=$((UNIT_TESTS_FAILED + INTEGRATION_TESTS_FAILED + ESCRIPT_TESTS_FAILED))
TOTAL_TESTS=$((TOTAL_PASSED + TOTAL_FAILED))

print_header "Test Suite Summary"
echo ""
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $TOTAL_PASSED"
echo "Failed: $TOTAL_FAILED"
echo "Duration: ${TEST_DURATION}s"
echo ""

if [ "$GENERATE_REPORT" = true ]; then
    append_report ""
    append_report "## Overall Summary"
    append_report "Total Tests: $TOTAL_TESTS"
    append_report "Passed: $TOTAL_PASSED"
    append_report "Failed: $TOTAL_FAILED"
    append_report "Duration: ${TEST_DURATION}s"
    append_report ""
    append_report "Report generated at: $(date)"
    echo "Report saved to: $REPORT_FILE"
fi

if [ $TOTAL_FAILED -eq 0 ]; then
    print_success "All tests passed!"
    exit 0
else
    print_error "Some tests failed!"
    exit 1
fi
