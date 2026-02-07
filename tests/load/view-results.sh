#!/bin/bash
# View Load Test Results
# Usage: ./view-results.sh [report-name]

RESULTS_DIR="/home/user/A2A/tests/load/results"

echo "========================================================================"
echo "A2A Protocol Load Test Results Viewer"
echo "========================================================================"
echo ""

# Check if results directory exists
if [ ! -d "$RESULTS_DIR" ]; then
    echo "❌ Results directory not found: $RESULTS_DIR"
    exit 1
fi

# List available reports
echo "Available Test Reports:"
echo "------------------------"
ls -lh "$RESULTS_DIR"
echo ""

# If HTML report exists, show it
if [ -f "$RESULTS_DIR/fortune5-test-report.html" ]; then
    echo "✅ Fortune 5 Scale Test Report Available"
    echo "   Location: $RESULTS_DIR/fortune5-test-report.html"
    echo ""
fi

if [ -f "$RESULTS_DIR/fortune5-test-summary.json" ]; then
    echo "📊 Fortune 5 Scale Test Summary:"
    echo "--------------------------------"
    cat "$RESULTS_DIR/fortune5-test-summary.json" | python3 -m json.tool
    echo ""
fi

echo "========================================================================"
echo "To view detailed reports:"
echo "  - HTML Report: Open $RESULTS_DIR/fortune5-test-report.html in a browser"
echo "  - JSON Summary: $RESULTS_DIR/fortune5-test-summary.json"
echo "  - Console Output: $RESULTS_DIR/fortune5-console-output.txt"
echo "========================================================================"
