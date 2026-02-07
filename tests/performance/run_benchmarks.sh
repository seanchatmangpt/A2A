#!/bin/bash
# Performance Benchmark Runner Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================================================"
echo "A2A Protocol Performance Benchmark Suite"
echo "======================================================================"
echo ""

# Check if dependencies are installed
echo "Checking dependencies..."
if ! python3 -c "import aiohttp, psutil" 2>/dev/null; then
    echo "Installing dependencies..."
    pip install -q -r requirements.txt
fi

# Check if server is running
echo "Checking if API server is running..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/health | grep -q "200"; then
    echo "✓ API server is running"
    USE_MOCK=false
else
    echo "✗ API server not detected"
    echo ""
    read -p "Start mock server for testing? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_MOCK=true
        echo "Starting mock server..."
        python3 mock_server.py &
        MOCK_PID=$!
        sleep 2
        echo "Mock server started (PID: $MOCK_PID)"
    else
        echo "Please start the API server and try again"
        exit 1
    fi
fi

echo ""
echo "======================================================================"
echo "Running Performance Benchmarks"
echo "======================================================================"
echo ""

python3 benchmark_suite.py

echo ""
echo "======================================================================"
echo "Running SLA Validation"
echo "======================================================================"
echo ""

python3 sla_validator.py

# Cleanup mock server if started
if [ "$USE_MOCK" = true ]; then
    echo ""
    echo "Stopping mock server..."
    kill $MOCK_PID 2>/dev/null || true
    echo "Mock server stopped"
fi

echo ""
echo "======================================================================"
echo "Benchmark Suite Completed"
echo "======================================================================"
echo ""
echo "Results saved in:"
echo "  - benchmark_results_*.json"
echo "  - sla_validation_*.json"
echo ""
