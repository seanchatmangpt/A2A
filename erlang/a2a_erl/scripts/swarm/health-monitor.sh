#!/usr/bin/env bash
# =============================================================================
# Docker Swarm Health Monitor for A2A Services
# =============================================================================
# Continuously monitors service health during rolling updates

set -euo pipefail

# Configuration
SERVICE_NAME="${SERVICE_NAME:-a2a-erl}"
STACK_NAME="${STACK_NAME:-a2a-test}"
PORT="${PORT:-8080}"
CHECK_INTERVAL="${CHECK_INTERVAL:-2}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/swarm-health-monitor.log}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_health() {
    local status=$1
    local message=$2
    local color=$3

    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${status} | ${message}" | tee -a "${OUTPUT_FILE}"
    echo -e "${color}[${status}]${NC} ${message}"
}

check_service_health() {
    local endpoint=$1
    local response
    local http_code
    local response_time

    local start_time=$(date +%s%N)
    response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}${endpoint}" 2>/dev/null || echo "000")
    local end_time=$(date +%s%N)

    response_time=$(( (end_time - start_time) / 1000000 ))

    echo "${response}|${response_time}"
}

check_task_health() {
    local service_name="${STACK_NAME}_${SERVICE_NAME}"
    local running_tasks
    local total_tasks

    running_tasks=$(docker service ps "${service_name}" --format "{{.CurrentState}}" 2>/dev/null | grep -c "Running" || echo "0")
    total_tasks=$(docker service ps "${service_name}" --format "{{.CurrentState}}" 2>/dev/null | wc -l | tr -d ' ')

    echo "${running_tasks}/${total_tasks}"
}

get_service_version() {
    curl -s "http://localhost:${PORT}/.well-known/agent-card.json" | jq -r '.version' 2>/dev/null || echo "unknown"
}

monitor_continuously() {
    local duration=${1}

    log_health "START" "Starting health monitor for ${duration}s" "${BLUE}"

    local end_time=$(($(date +%s) + duration))
    local check_count=0
    local health_failures=0
    local readiness_failures=0
    local liveness_failures=0
    local total_response_time=0
    local min_response_time=999999
    local max_response_time=0

    while [[ $(date +%s) -lt ${end_time} ]]; do
        ((check_count++))

        # Health check
        local health_result
        health_result=$(check_service_health "/health")
        local health_code=$(echo "${health_result}" | cut -d'|' -f1)
        local health_time=$(echo "${health_result}" | cut -d'|' -f2)

        # Readiness check
        local ready_result
        ready_result=$(check_service_health "/health/ready")
        local ready_code=$(echo "${ready_result}" | cut -d'|' -f1)

        # Liveness check
        local live_result
        live_result=$(check_service_health "/health/live")
        local live_code=$(echo "${live_result}" | cut -d'|' -f1)

        # Update statistics
        if [[ "${health_time}" -gt 0 ]]; then
            total_response_time=$((total_response_time + health_time))
            if [[ ${health_time} -lt ${min_response_time} ]]; then
                min_response_time=${health_time}
            fi
            if [[ ${health_time} -gt ${max_response_time} ]]; then
                max_response_time=${health_time}
            fi
        fi

        # Check for failures
        if [[ "${health_code}" != "200" ]]; then
            ((health_failures++))
            log_health "FAIL" "Health check failed: HTTP ${health_code}" "${RED}"
        fi

        if [[ "${ready_code}" != "200" ]]; then
            ((readiness_failures++))
        fi

        if [[ "${live_code}" != "200" ]]; then
            ((liveness_failures++))
        fi

        # Get task status
        local task_status
        task_status=$(check_task_health)

        # Get version
        local version
        version=$(get_service_version)

        # Log status every 10 checks
        if [[ $((check_count % 10)) -eq 0 ]]; then
            local avg_time=$((total_response_time / check_count))
            log_health "STATS" "Check: ${check_count} | Tasks: ${task_status} | Health: ${health_code} | Ready: ${ready_code} | Live: ${live_code} | Version: ${version} | Avg: ${avg_time}ms | Min: ${min_response_time}ms | Max: ${max_response_time}ms" "${GREEN}"
        fi

        sleep "${CHECK_INTERVAL}"
    done

    # Print summary
    echo ""
    echo "========================================="
    echo "         HEALTH MONITOR SUMMARY"
    echo "========================================="
    echo "Duration:           ${duration}s"
    echo "Total Checks:       ${check_count}"
    echo "Health Failures:    ${health_failures}"
    echo "Readiness Failures: ${readiness_failures}"
    echo "Liveness Failures:  ${liveness_failures}"

    local avg_response=0
    if [[ ${check_count} -gt 0 ]]; then
        avg_response=$((total_response_time / check_count))
    fi

    echo "Avg Response Time:  ${avg_response}ms"
    echo "Min Response Time:  ${min_response_time}ms"
    echo "Max Response Time:  ${max_response_time}ms"

    local uptime_percent=0
    if [[ ${check_count} -gt 0 ]]; then
        uptime_percent=$(awk "BEGIN {printf \"%.2f\", ((${check_count} - ${health_failures})/${check_count})*100}")
    fi

    echo "Uptime:             ${uptime_percent}%"
    echo "========================================="

    # Return success if uptime > 99%
    if (( $(echo "${uptime_percent} > 99.0" | bc -l 2>/dev/null || echo "0") )); then
        return 0
    else
        return 1
    fi
}

# Main
case "${1:-monitor}" in
    monitor)
        monitor_continuously "${2:-120}"
        ;;
    single)
        check_service_health "/health"
        ;;
    tasks)
        check_task_health
        ;;
    version)
        get_service_version
        ;;
    *)
        echo "Usage: $0 {monitor|single|tasks|version} [duration]"
        exit 1
        ;;
esac
