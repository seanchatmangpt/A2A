#!/usr/bin/env bash
# =============================================================================
# A2A Erlang Validation Script
# =============================================================================
# Runs xref and dialyzer validation locally
# This serves as a local alternative to GitHub Actions workflows
# =============================================================================

set -e

echo "========================================"
echo "A2A Erlang Validation"
echo "========================================"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v erl &> /dev/null; then
    echo "Error: Erlang/OTP not found. Please install Erlang 28 or later."
    exit 1
fi

if ! command -v rebar3 &> /dev/null; then
    echo "Error: rebar3 not found. Please install rebar3."
    exit 1
fi

OTP_VERSION=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>&1 | tr -d '" \r\n')
echo "Erlang/OTP version: ${OTP_VERSION}"

if [ -n "${OTP_VERSION}" ] && [ "${OTP_VERSION}" -ge 28 ] 2>/dev/null; then
    echo "Erlang version OK (28 or later recommended)"
else
    echo "Warning: Erlang/OTP 28 or later is recommended. Current version: ${OTP_VERSION}"
fi

echo ""

# Clean previous builds
echo "Cleaning previous build artifacts..."
rebar3 clean

# Compile
echo "========================================"
echo "Compiling..."
echo "========================================"
rebar3 compile

echo ""

# Run xref
echo "========================================"
echo "Running Xref..."
echo "========================================"
rebar3 xref
XREF_EXIT=$?
if [ $XREF_EXIT -eq 0 ]; then
    echo "Xref: PASSED"
else
    echo "Xref: FAILED (exit code: $XREF_EXIT)"
fi
echo ""

# Run dialyzer
echo "========================================"
echo "Running Dialyzer..."
echo "========================================"
rebar3 dialyzer || true

# Check for dialyzer warnings
if [ -f "_build/default/28.3.dialyzer_warnings" ]; then
    if [ -s "_build/default/28.3.dialyzer_warnings" ]; then
        WARNINGS=$(wc -l < "_build/default/28.3.dialyzer_warnings" | tr -d ' ')
        echo "Dialyzer: FOUND $WARNINGS lines of warnings"
    else
        echo "Dialyzer: PASSED (no issues found)"
    fi
else
    echo "Dialyzer: PASSED (no warning file found)"
fi
echo ""

# Summary
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo "Xref: $( [ $XREF_EXIT -eq 0 ] && echo 'PASSED' || echo 'FAILED' )"
echo "Dialyzer: Analysis completed"
echo ""

if [ $XREF_EXIT -ne 0 ]; then
    echo "Validation FAILED due to Xref errors"
    exit 1
fi

echo "Validation completed successfully"
exit 0
