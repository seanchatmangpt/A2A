#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${PROJECT_ROOT}/logs/verification"
LOG_FILE="${LOG_DIR}/verify_${TIMESTAMP}.log"
RESULTS_FILE="${LOG_DIR}/results_${TIMESTAMP}.json"

# Default endpoints
API_ENDPOINT="${API_ENDPOINT:-http://localhost:8080}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-${API_ENDPOINT}/health}"
METRICS_ENDPOINT="${METRICS_ENDPOINT:-${API_ENDPOINT}/metrics}"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Create log directory
mkdir -p "$LOG_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

# Test result tracking
record_test() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ "$result" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "$test_name: $message"
    elif [[ "$result" == "FAIL" ]]; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "$test_name: $message"
    elif [[ "$result" == "WARN" ]]; then
        WARNINGS=$((WARNINGS + 1))
        log_warning "$test_name: $message"
    fi

    echo "{\"test\": \"$test_name\", \"result\": \"$result\", \"message\": \"$message\", \"timestamp\": \"$(date -Iseconds)\"}" >> "$RESULTS_FILE"
}

# Health Check Functions
check_service_health() {
    log_info "Starting health check verification..."

    # Check if service is responding
    if curl -sf --max-time 10 "$HEALTH_ENDPOINT" > /dev/null 2>&1; then
        record_test "Service Health Endpoint" "PASS" "Health endpoint is accessible"
    else
        record_test "Service Health Endpoint" "FAIL" "Health endpoint not responding"
        return 1
    fi

    # Verify health response format
    local health_response=$(curl -sf --max-time 10 "$HEALTH_ENDPOINT" 2>/dev/null || echo "{}")

    if echo "$health_response" | jq -e '.status' > /dev/null 2>&1; then
        local status=$(echo "$health_response" | jq -r '.status')
        if [[ "$status" == "healthy" || "$status" == "ok" ]]; then
            record_test "Service Health Status" "PASS" "Service status: $status"
        else
            record_test "Service Health Status" "FAIL" "Service status: $status"
        fi
    else
        record_test "Service Health Response Format" "WARN" "Health response missing 'status' field"
    fi
}

check_database_connectivity() {
    log_info "Checking database connectivity..."

    # Check if DATABASE_URL is set
    if [[ -z "${DATABASE_URL:-}" ]]; then
        record_test "Database Configuration" "WARN" "DATABASE_URL not set"
        return 0
    fi

    # Try to ping database (PostgreSQL example)
    if command -v psql >/dev/null 2>&1; then
        if psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1; then
            record_test "Database Connectivity" "PASS" "Successfully connected to database"
        else
            record_test "Database Connectivity" "FAIL" "Cannot connect to database"
        fi
    else
        record_test "Database Connectivity" "WARN" "psql not available, skipping database check"
    fi
}

check_dependencies() {
    log_info "Checking service dependencies..."

    # Check required binaries
    local required_bins=("curl" "jq")
    for bin in "${required_bins[@]}"; do
        if command -v "$bin" >/dev/null 2>&1; then
            record_test "Dependency: $bin" "PASS" "$bin is installed"
        else
            record_test "Dependency: $bin" "FAIL" "$bin is not installed"
        fi
    done

    # Check optional binaries
    local optional_bins=("docker" "kubectl" "aws")
    for bin in "${optional_bins[@]}"; do
        if command -v "$bin" >/dev/null 2>&1; then
            record_test "Optional Dependency: $bin" "PASS" "$bin is available"
        else
            record_test "Optional Dependency: $bin" "WARN" "$bin is not available"
        fi
    done
}

# Smoke Tests
run_smoke_tests() {
    log_info "Running smoke tests..."

    # Test 1: API root endpoint
    if curl -sf --max-time 10 "${API_ENDPOINT}/" > /dev/null 2>&1; then
        record_test "Smoke Test: API Root" "PASS" "API root endpoint accessible"
    else
        record_test "Smoke Test: API Root" "FAIL" "API root endpoint not accessible"
    fi

    # Test 2: API version endpoint
    if curl -sf --max-time 10 "${API_ENDPOINT}/version" > /dev/null 2>&1; then
        local version=$(curl -sf --max-time 10 "${API_ENDPOINT}/version" | jq -r '.version // .Version // "unknown"' 2>/dev/null)
        record_test "Smoke Test: API Version" "PASS" "Version: $version"
    else
        record_test "Smoke Test: API Version" "WARN" "Version endpoint not available"
    fi

    # Test 3: Metrics endpoint (if available)
    if curl -sf --max-time 10 "$METRICS_ENDPOINT" > /dev/null 2>&1; then
        record_test "Smoke Test: Metrics Endpoint" "PASS" "Metrics endpoint accessible"
    else
        record_test "Smoke Test: Metrics Endpoint" "WARN" "Metrics endpoint not available"
    fi

    # Test 4: Response time check
    local start_time=$(date +%s%N)
    curl -sf --max-time 10 "$HEALTH_ENDPOINT" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local response_time=$(( (end_time - start_time) / 1000000 ))

    if [[ $response_time -lt 1000 ]]; then
        record_test "Smoke Test: Response Time" "PASS" "Response time: ${response_time}ms"
    elif [[ $response_time -lt 3000 ]]; then
        record_test "Smoke Test: Response Time" "WARN" "Response time: ${response_time}ms (slow)"
    else
        record_test "Smoke Test: Response Time" "FAIL" "Response time: ${response_time}ms (too slow)"
    fi
}

run_api_smoke_tests() {
    log_info "Running API smoke tests..."

    # Test authenticated endpoints (if applicable)
    if [[ -n "${API_TOKEN:-}" ]]; then
        if curl -sf -H "Authorization: Bearer $API_TOKEN" --max-time 10 "${API_ENDPOINT}/api/users" > /dev/null 2>&1; then
            record_test "API Smoke Test: Authenticated Endpoint" "PASS" "Authentication working"
        else
            record_test "API Smoke Test: Authenticated Endpoint" "FAIL" "Authentication failed"
        fi
    else
        record_test "API Smoke Test: Authentication" "WARN" "API_TOKEN not set, skipping auth tests"
    fi

    # Test CORS headers
    local cors_headers=$(curl -sf -H "Origin: http://example.com" -I --max-time 10 "${API_ENDPOINT}/" 2>/dev/null | grep -i "access-control" || echo "")
    if [[ -n "$cors_headers" ]]; then
        record_test "API Smoke Test: CORS Headers" "PASS" "CORS headers present"
    else
        record_test "API Smoke Test: CORS Headers" "WARN" "CORS headers not found"
    fi
}

# Compliance Validation
validate_security_compliance() {
    log_info "Running security compliance checks..."

    # Check SSL/TLS if HTTPS
    if [[ "$API_ENDPOINT" == https://* ]]; then
        if curl -sf --max-time 10 "$API_ENDPOINT" > /dev/null 2>&1; then
            record_test "Security: SSL/TLS" "PASS" "HTTPS endpoint accessible"
        else
            record_test "Security: SSL/TLS" "FAIL" "HTTPS endpoint not accessible"
        fi

        # Check SSL certificate validity
        if echo | timeout 5 openssl s_client -connect "${API_ENDPOINT#https://}" 2>/dev/null | grep -q "Verify return code: 0"; then
            record_test "Security: SSL Certificate" "PASS" "Valid SSL certificate"
        else
            record_test "Security: SSL Certificate" "WARN" "SSL certificate validation failed"
        fi
    else
        record_test "Security: SSL/TLS" "WARN" "Service not using HTTPS"
    fi

    # Check security headers
    local security_headers=$(curl -sf -I --max-time 10 "$API_ENDPOINT" 2>/dev/null || echo "")

    if echo "$security_headers" | grep -qi "X-Frame-Options"; then
        record_test "Security: X-Frame-Options Header" "PASS" "X-Frame-Options present"
    else
        record_test "Security: X-Frame-Options Header" "WARN" "X-Frame-Options missing"
    fi

    if echo "$security_headers" | grep -qi "X-Content-Type-Options"; then
        record_test "Security: X-Content-Type-Options Header" "PASS" "X-Content-Type-Options present"
    else
        record_test "Security: X-Content-Type-Options Header" "WARN" "X-Content-Type-Options missing"
    fi

    if echo "$security_headers" | grep -qi "Strict-Transport-Security"; then
        record_test "Security: HSTS Header" "PASS" "HSTS header present"
    else
        record_test "Security: HSTS Header" "WARN" "HSTS header missing"
    fi

    # Check for sensitive data exposure
    local api_response=$(curl -sf --max-time 10 "$API_ENDPOINT" 2>/dev/null || echo "")
    if echo "$api_response" | grep -qiE "(password|secret|token|api_key)" 2>/dev/null; then
        record_test "Security: Sensitive Data Exposure" "FAIL" "Potential sensitive data in response"
    else
        record_test "Security: Sensitive Data Exposure" "PASS" "No obvious sensitive data exposure"
    fi
}

validate_configuration_compliance() {
    log_info "Validating configuration compliance..."

    # Check environment variables
    local required_env_vars=("NODE_ENV" "LOG_LEVEL")
    for var in "${required_env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            record_test "Config: $var" "PASS" "$var is set"
        else
            record_test "Config: $var" "WARN" "$var is not set"
        fi
    done

    # Validate production settings
    if [[ "${NODE_ENV:-}" == "production" ]]; then
        if [[ "${DEBUG:-false}" == "false" ]]; then
            record_test "Config: Debug Mode" "PASS" "Debug mode disabled in production"
        else
            record_test "Config: Debug Mode" "FAIL" "Debug mode enabled in production"
        fi
    fi

    # Check log level
    if [[ "${LOG_LEVEL:-info}" =~ ^(error|warn|info)$ ]]; then
        record_test "Config: Log Level" "PASS" "Log level: ${LOG_LEVEL}"
    else
        record_test "Config: Log Level" "WARN" "Unusual log level: ${LOG_LEVEL:-not set}"
    fi
}

validate_resource_limits() {
    log_info "Validating resource limits..."

    # Check memory usage
    if command -v free >/dev/null 2>&1; then
        local mem_available=$(free -m | awk 'NR==2{print $7}')
        if [[ $mem_available -gt 1000 ]]; then
            record_test "Resources: Available Memory" "PASS" "${mem_available}MB available"
        elif [[ $mem_available -gt 500 ]]; then
            record_test "Resources: Available Memory" "WARN" "${mem_available}MB available (low)"
        else
            record_test "Resources: Available Memory" "FAIL" "${mem_available}MB available (critical)"
        fi
    fi

    # Check disk space
    if command -v df >/dev/null 2>&1; then
        local disk_available=$(df -h "$PROJECT_ROOT" | awk 'NR==2{print $4}')
        local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2{print $5}' | tr -d '%')
        if [[ $disk_usage -lt 80 ]]; then
            record_test "Resources: Disk Space" "PASS" "${disk_available} available (${disk_usage}% used)"
        elif [[ $disk_usage -lt 90 ]]; then
            record_test "Resources: Disk Space" "WARN" "${disk_available} available (${disk_usage}% used)"
        else
            record_test "Resources: Disk Space" "FAIL" "${disk_available} available (${disk_usage}% used - critical)"
        fi
    fi

    # Check for running processes
    if pgrep -f "node.*server" > /dev/null 2>&1; then
        local process_count=$(pgrep -f "node.*server" | wc -l)
        record_test "Resources: Service Processes" "PASS" "$process_count process(es) running"
    else
        record_test "Resources: Service Processes" "WARN" "No service processes found"
    fi
}

# Post-Deployment Validation
validate_deployment() {
    log_info "Running post-deployment validation..."

    # Check deployment timestamp
    if [[ -f "${PROJECT_ROOT}/.deployment_timestamp" ]]; then
        local deploy_time=$(cat "${PROJECT_ROOT}/.deployment_timestamp")
        local current_time=$(date +%s)
        local time_diff=$((current_time - deploy_time))

        if [[ $time_diff -lt 300 ]]; then
            record_test "Deployment: Timestamp" "PASS" "Deployed $((time_diff / 60)) minutes ago"
        else
            record_test "Deployment: Timestamp" "WARN" "Deployed $((time_diff / 3600)) hours ago"
        fi
    else
        record_test "Deployment: Timestamp" "WARN" "No deployment timestamp found"
    fi

    # Verify deployment version
    if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        local package_version=$(jq -r '.version' "${PROJECT_ROOT}/package.json" 2>/dev/null || echo "unknown")
        local api_version=$(curl -sf --max-time 10 "${API_ENDPOINT}/version" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")

        if [[ "$package_version" == "$api_version" ]]; then
            record_test "Deployment: Version Match" "PASS" "Version: $package_version"
        else
            record_test "Deployment: Version Match" "WARN" "Package: $package_version, API: $api_version"
        fi
    fi

    # Check for deployment artifacts
    if [[ -d "${PROJECT_ROOT}/dist" ]] || [[ -d "${PROJECT_ROOT}/build" ]]; then
        record_test "Deployment: Build Artifacts" "PASS" "Build artifacts present"
    else
        record_test "Deployment: Build Artifacts" "WARN" "No build artifacts found"
    fi
}

validate_monitoring() {
    log_info "Validating monitoring and observability..."

    # Check metrics endpoint
    if curl -sf --max-time 10 "$METRICS_ENDPOINT" > /dev/null 2>&1; then
        local metrics=$(curl -sf --max-time 10 "$METRICS_ENDPOINT" 2>/dev/null || echo "")

        if echo "$metrics" | grep -q "http_requests_total\|requests_total" 2>/dev/null; then
            record_test "Monitoring: Request Metrics" "PASS" "Request metrics available"
        else
            record_test "Monitoring: Request Metrics" "WARN" "Request metrics not found"
        fi

        if echo "$metrics" | grep -q "process_cpu\|cpu_usage" 2>/dev/null; then
            record_test "Monitoring: CPU Metrics" "PASS" "CPU metrics available"
        else
            record_test "Monitoring: CPU Metrics" "WARN" "CPU metrics not found"
        fi

        if echo "$metrics" | grep -q "process_memory\|memory_usage" 2>/dev/null; then
            record_test "Monitoring: Memory Metrics" "PASS" "Memory metrics available"
        else
            record_test "Monitoring: Memory Metrics" "WARN" "Memory metrics not found"
        fi
    else
        record_test "Monitoring: Metrics Endpoint" "WARN" "Metrics endpoint not available"
    fi

    # Check logging
    if [[ -d "${PROJECT_ROOT}/logs" ]]; then
        local log_count=$(find "${PROJECT_ROOT}/logs" -type f -name "*.log" 2>/dev/null | wc -l)
        if [[ $log_count -gt 0 ]]; then
            record_test "Monitoring: Logging" "PASS" "$log_count log file(s) found"
        else
            record_test "Monitoring: Logging" "WARN" "No log files found"
        fi
    else
        record_test "Monitoring: Logging" "WARN" "Logs directory not found"
    fi
}

# Generate Report
generate_report() {
    log_info "Generating verification report..."

    local pass_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo ""
    echo "======================================================================"
    echo "                    VERIFICATION REPORT                              "
    echo "======================================================================"
    echo ""
    echo "Timestamp:       $(date +'%Y-%m-%d %H:%M:%S')"
    echo "API Endpoint:    $API_ENDPOINT"
    echo ""
    echo "Test Summary:"
    echo "  Total Tests:   $TOTAL_TESTS"
    echo "  Passed:        $PASSED_TESTS"
    echo "  Failed:        $FAILED_TESTS"
    echo "  Warnings:      $WARNINGS"
    echo "  Pass Rate:     ${pass_rate}%"
    echo ""
    echo "Log File:        $LOG_FILE"
    echo "Results File:    $RESULTS_FILE"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All critical tests passed!"
        echo "Status: ✓ VERIFIED"
    else
        log_error "$FAILED_TESTS test(s) failed!"
        echo "Status: ✗ VERIFICATION FAILED"
    fi

    echo "======================================================================"
    echo ""

    # Save summary to JSON
    cat > "${LOG_DIR}/summary_${TIMESTAMP}.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "api_endpoint": "$API_ENDPOINT",
  "total_tests": $TOTAL_TESTS,
  "passed_tests": $PASSED_TESTS,
  "failed_tests": $FAILED_TESTS,
  "warnings": $WARNINGS,
  "pass_rate": $pass_rate,
  "status": "$([[ $FAILED_TESTS -eq 0 ]] && echo "VERIFIED" || echo "FAILED")",
  "log_file": "$LOG_FILE",
  "results_file": "$RESULTS_FILE"
}
EOF
}

# Main execution
main() {
    log_info "Starting post-deployment verification..."
    log_info "API Endpoint: $API_ENDPOINT"
    echo ""

    # Initialize results file
    echo "[]" > "$RESULTS_FILE"

    # Run all validation suites
    check_dependencies
    check_service_health
    check_database_connectivity
    run_smoke_tests
    run_api_smoke_tests
    validate_security_compliance
    validate_configuration_compliance
    validate_resource_limits
    validate_deployment
    validate_monitoring

    # Generate final report
    generate_report

    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
