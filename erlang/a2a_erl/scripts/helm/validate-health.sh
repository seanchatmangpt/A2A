#!/bin/bash
# Health validation script for Helm upgrades
# This script validates the health of the deployment after upgrade/rollback

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

RELEASE_NAME="${RELEASE_NAME:-a2a-test}"
NAMESPACE="${NAMESPACE:-a2a-test}"
TIMEOUT="${TIMEOUT:-120}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if all pods are ready
check_pods_ready() {
    log_info "Checking pod readiness..."

    local end_time=$((SECONDS + TIMEOUT))

    while [[ ${SECONDS} -lt ${end_time} ]]; do
        local not_ready=$(kubectl get pods -n "${NAMESPACE}" \
            -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
            -o jsonpath='{range .items[*]}{.metadata.name}:{.status.phase}:{range .status.conditions[?(@.type=="Ready")]}{.status}{"\n"}{end}{end}' | \
            grep -c ":False:" || true)

        if [[ ${not_ready} -eq 0 ]]; then
            local ready_count=$(kubectl get pods -n "${NAMESPACE}" \
                -l "app.kubernetes.io/instance=${RELEASE_NAME}" --no-headers | grep -c "Running" || echo "0")

            log_info "All ${ready_count} pods are ready!"
            return 0
        fi

        log_warn "Waiting for ${not_ready} pods to be ready..."
        sleep 5
    done

    log_error "Timeout waiting for pods to be ready"
    return 1
}

# Check deployment status
check_deployment_status() {
    log_info "Checking deployment status..."

    local deployment="${RELEASE_NAME}-a2a-erl"
    local ready_replicas=$(kubectl get deployment "${deployment}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas=$(kubectl get deployment "${deployment}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    log_info "Ready replicas: ${ready_replicas}/${desired_replicas}"

    if [[ "${ready_replicas}" == "${desired_replicas}" ]] && [[ "${ready_replicas}" -gt 0 ]]; then
        return 0
    fi

    log_error "Deployment not ready"
    return 1
}

# Check service endpoints
check_endpoints() {
    log_info "Checking service endpoints..."

    local service="${RELEASE_NAME}-a2a-erl"
    local endpoints=$(kubectl get endpoints "${service}" -n "${NAMESPACE}" \
        -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")

    if [[ -n "${endpoints}" ]]; then
        log_info "Service endpoints available: ${endpoints}"
        return 0
    fi

    log_error "No service endpoints available"
    return 1
}

# Check health endpoint
check_health_endpoint() {
    log_info "Checking health endpoint..."

    local pod_name=$(kubectl get pods -n "${NAMESPACE}" \
        -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "${pod_name}" ]]; then
        log_error "No pods found"
        return 1
    fi

    log_info "Checking health on pod: ${pod_name}"

    # Port forward to local port
    kubectl port-forward -n "${NAMESPACE}" "${pod_name}" 18080:8080 &
    local pf_pid=$!
    sleep 3

    local result=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:18080/.well-known/agent-card.json 2>/dev/null || echo "000")
    kill ${pf_pid} 2>/dev/null || true

    if [[ "${result}" == "200" ]]; then
        log_info "Health endpoint returned: ${result}"
        return 0
    fi

    log_error "Health endpoint returned: ${result}"
    return 1
}

# Print detailed status
print_status() {
    echo ""
    log_info "=== Deployment Status ==="
    kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o yaml | grep -A 20 "status:" || true

    echo ""
    log_info "=== Pod Status ==="
    kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}"

    echo ""
    log_info "=== Events ==="
    kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -20 || true
}

# Main validation
main() {
    local all_passed=true

    log_info "Starting health validation for ${RELEASE_NAME}..."

    check_pods_ready || all_passed=false
    check_deployment_status || all_passed=false
    check_endpoints || all_passed=false
    check_health_endpoint || all_passed=false

    if [[ "${all_passed}" == "true" ]]; then
        log_info "All health checks passed!"
        return 0
    else
        log_error "Some health checks failed!"
        print_status
        return 1
    fi
}

main "$@"
