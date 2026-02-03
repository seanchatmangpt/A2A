#!/usr/bin/env bash
# Helm Chart Test Runner for a2a-erl
# Tests various value combinations and validates the chart

set -e

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${CHART_DIR}/tests"

echo "========================================"
echo "Helm Chart Test Runner for a2a-erl"
echo "========================================"
echo ""

# Track results
PASS=0
FAIL=0
TEST_FILES=()

# Collect all test files
for test_file in "${TESTS_DIR}"/test-*.yaml; do
    if [[ -f "$test_file" ]]; then
        TEST_FILES+=("$test_file")
    fi
done

echo "Found ${#TEST_FILES[@]} test files"
echo ""

# Function to run a test
run_test() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .yaml)

    echo -n "Testing: $test_name ... "

    # Run helm lint
    if ! helm lint --quiet "$CHART_DIR" -f "$test_file" >/dev/null 2>&1; then
        echo "FAIL (lint)"
        ((FAIL++))
        return 1
    fi

    # Run helm template
    if ! helm template "test-$test_name" "$CHART_DIR" -f "$test_file" >/dev/null 2>&1; then
        echo "FAIL (template)"
        ((FAIL++))
        return 1
    fi

    # Run helm dry-run install
    if ! helm install "test-$test_name" "$CHART_DIR" --dry-run -f "$test_file" >/dev/null 2>&1; then
        echo "FAIL (dry-run)"
        ((FAIL++))
        return 1
    fi

    echo "PASS"
    ((PASS++))
    return 0
}

# Run all tests
for test_file in "${TEST_FILES[@]}"; do
    run_test "$test_file" || true
done

echo ""
echo "========================================"
echo "Test Results"
echo "========================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
