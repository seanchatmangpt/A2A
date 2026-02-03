#!/bin/bash
# Helm Upgrade and Rollback Test Suite
# This script tests upgrade and rollback scenarios for the A2A Helm chart

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELM_CHART_DIR="${PROJECT_ROOT}/helm/a2a-erl"

# Test configuration
RELEASE_NAME="${RELEASE_NAME:-a2a-test}"
NAMESPACE="${NAMESPACE:-a2a-test}"
IMAGE_NAME="${IMAGE_NAME:-a2a-erl}"
REGISTRY="${REGISTRY:-localhost:5000}"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Record test result
record_result() {
    local result=$1
    local test_name=$2

    if [[ "${result}" == "pass" ]]; then
        log_info "PASS: ${test_name}"
        ((TESTS_PASSED++))
    else
        log_error "FAIL: ${test_name}"
        ((TESTS_FAILED++))
    fi
}

# Check if pod is ready
wait_for_pods() {
    local timeout=${1:-120}
    log_info "Waiting for pods to be ready (timeout: ${timeout}s)..."
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=${RELEASE_NAME}" -n "${NAMESPACE}" --timeout="${timeout}s"
}

# Get deployment status
get_deployment_status() {
    kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null || echo "0/0"
}

# Get current revision
get_revision() {
    kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || echo "unknown"
}

# Get image version
get_image_version() {
    kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown"
}

# Test 1: Initial installation
test_initial_install() {
    log_test "Test 1: Initial Helm installation"

    # Install initial version
    helm install "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --set "image.repository=${REGISTRY}/${IMAGE_NAME}" \
        --set "image.tag=0.1.0" \
        --set "tests.enabled=true" \
        --wait \
        --timeout 5m

    if [[ $? -eq 0 ]]; then
        wait_for_pods
        local status=$(get_deployment_status)
        local revision=$(get_revision)
        log_info "Deployment status: ${status}, Revision: ${revision}"

        # Run helm test
        if helm test "${RELEASE_NAME}" -n "${NAMESPACE}" --timeout 5m; then
            record_result "pass" "Initial installation"
            return 0
        fi
    fi

    record_result "fail" "Initial installation"
    return 1
}

# Test 2: Image version upgrade
test_image_upgrade() {
    log_test "Test 2: Image version upgrade (0.1.0 -> 0.2.0)"

    local before_revision=$(get_revision)
    local before_image=$(get_image_version)

    helm upgrade "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --set "image.repository=${REGISTRY}/${IMAGE_NAME}" \
        --set "image.tag=0.2.0" \
        --set "tests.enabled=true" \
        --wait \
        --timeout 5m

    if [[ $? -eq 0 ]]; then
        wait_for_pods
        local after_revision=$(get_revision)
        local after_image=$(get_image_version)

        log_info "Before: Revision ${before_revision}, Image ${before_image}"
        log_info "After:  Revision ${after_revision}, Image ${after_image}"

        if [[ "${after_image}" == *"0.2.0"* ]] && [[ "${after_revision}" != "${before_revision}" ]]; then
            if helm test "${RELEASE_NAME}" -n "${NAMESPACE}" --timeout 5m; then
                record_result "pass" "Image version upgrade"
                return 0
            fi
        fi
    fi

    record_result "fail" "Image version upgrade"
    return 1
}

# Test 3: Configuration change upgrade
test_config_upgrade() {
    log_test "Test 3: Configuration change upgrade"

    local before_revision=$(get_revision)

    # Change configuration
    helm upgrade "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --set "image.repository=${REGISTRY}/${IMAGE_NAME}" \
        --set "image.tag=0.2.0" \
        --set "app.logLevel=debug" \
        --set "replicaCount=2" \
        --set "tests.enabled=true" \
        --reuse-values \
        --wait \
        --timeout 5m

    if [[ $? -eq 0 ]]; then
        wait_for_pods 180
        local after_revision=$(get_revision)
        local replicas=$(kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')

        log_info "Revision changed: ${before_revision} -> ${after_revision}"
        log_info "Replicas: ${replicas}"

        if [[ "${after_revision}" != "${before_revision}" ]] && [[ "${replicas}" == "2" ]]; then
            if helm test "${RELEASE_NAME}" -n "${NAMESPACE}" --timeout 5m; then
                record_result "pass" "Configuration change upgrade"
                return 0
            fi
        fi
    fi

    record_result "fail" "Configuration change upgrade"
    return 1
}

# Test 4: Rollback to previous version
test_rollback() {
    log_test "Test 4: Rollback to previous revision"

    local current_revision=$(get_revision)

    # Get revision history
    local revisions=$(helm history "${RELEASE_NAME}" -n "${NAMESPACE}" -o json | jq -r '.[] | "\(.revision): \(.description)"' || echo "No history available")
    log_info "Revision history:\n${revisions}"

    # Rollback to previous version (revision 2, which had 0.1.0 image)
    helm rollback "${RELEASE_NAME}" 2 -n "${NAMESPACE}" --wait --timeout 5m

    if [[ $? -eq 0 ]]; then
        wait_for_pods
        local rollback_image=$(get_image_version)
        local rollback_revision=$(get_revision)

        log_info "After rollback: Revision ${rollback_revision}, Image ${rollback_image}"

        # Verify rollback occurred (image should be 0.1.0 again)
        if [[ "${rollback_image}" == *"0.1.0"* ]]; then
            if helm test "${RELEASE_NAME}" -n "${NAMESPACE}" --timeout 5m; then
                record_result "pass" "Rollback to previous version"
                return 0
            fi
        fi
    fi

    record_result "fail" "Rollback to previous version"
    return 1
}

# Test 5: Upgrade again after rollback
test_upgrade_after_rollback() {
    log_test "Test 5: Upgrade again after rollback"

    local before_revision=$(get_revision)

    helm upgrade "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --set "image.repository=${REGISTRY}/${IMAGE_NAME}" \
        --set "image.tag=0.3.0" \
        --set "app.logLevel=info" \
        --set "replicaCount=1" \
        --set "tests.enabled=true" \
        --wait \
        --timeout 5m

    if [[ $? -eq 0 ]]; then
        wait_for_pods
        local after_revision=$(get_revision)
        local after_image=$(get_image_version)

        log_info "Revision: ${before_revision} -> ${after_revision}"
        log_info "Image: ${after_image}"

        if [[ "${after_image}" == *"0.3.0"* ]]; then
            if helm test "${RELEASE_NAME}" -n "${NAMESPACE}" --timeout 5m; then
                record_result "pass" "Upgrade after rollback"
                return 0
            fi
        fi
    fi

    record_result "fail" "Upgrade after rollback"
    return 1
}

# Test 6: Rolling update verification
test_rolling_update() {
    log_test "Test 6: Rolling update with zero downtime"

    # Scale up to 3 replicas
    helm upgrade "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --set "image.repository=${REGISTRY}/${IMAGE_NAME}" \
        --set "image.tag=0.3.0" \
        --set "replicaCount=3" \
        --set "rollingUpdate.maxSurge=1" \
        --set "rollingUpdate.maxUnavailable=0" \
        --reuse-values \
        --wait \
        --timeout 5m

    if [[ $? -eq 0 ]]; then
        # Check that all pods are ready
        local ready_pods=$(kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
        local desired_pods=$(kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')

        log_info "Ready pods: ${ready_pods}/${desired_pods}"

        if [[ "${ready_pods}" == "${desired_pods}" ]] && [[ "${ready_pods}" == "3" ]]; then
            if helm test "${RELEASE_NAME}" -n "${NAMESPACE}" --timeout 5m; then
                record_result "pass" "Rolling update verification"
                return 0
            fi
        fi
    fi

    record_result "fail" "Rolling update verification"
    return 1
}

# Test 7: Revision history limit
test_revision_history() {
    log_test "Test 7: Revision history limit verification"

    local replica_sets=$(kubectl get replicasets -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --no-headers | wc -l | tr -d ' ')
    local revision_limit=$(kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o jsonpath='{.spec.revisionHistoryLimit}')

    log_info "ReplicaSets count: ${replica_sets}"
    log_info "Revision history limit: ${revision_limit}"

    if [[ "${replica_sets}" -le "$((revision_limit + 1))" ]]; then
        record_result "pass" "Revision history limit"
        return 0
    fi

    record_result "fail" "Revision history limit"
    return 1
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."

    # Capture final state
    echo ""
    log_info "=== Final Helm Release History ==="
    helm history "${RELEASE_NAME}" -n "${NAMESPACE}" || true

    echo ""
    log_info "=== Final Deployment Status ==="
    kubectl get deployment "${RELEASE_NAME}-a2a-erl" -n "${NAMESPACE}" -o yaml || true

    echo ""
    log_info "=== Pod Status ==="
    kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

    # Uninstall release
    if [[ "${SKIP_CLEANUP:-}" != "true" ]]; then
        log_info "Uninstalling Helm release..."
        helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}" || true

        log_info "Deleting namespace..."
        kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true
    else
        log_warn "Skipping cleanup (SKIP_CLEANUP=true)"
    fi
}

# Print test summary
print_summary() {
    echo ""
    echo "========================================="
    echo "         TEST SUMMARY"
    echo "========================================="
    echo "Tests Passed: ${TESTS_PASSED}"
    echo "Tests Failed: ${TESTS_FAILED}"
    echo "Total Tests:  $((TESTS_PASSED + TESTS_FAILED))"
    echo "========================================="

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_info "All tests passed!"
        return 0
    else
        log_error "Some tests failed!"
        return 1
    fi
}

# Main test runner
main() {
    log_info "Starting Helm Upgrade/Rollback Test Suite"
    log_info "Release: ${RELEASE_NAME}, Namespace: ${NAMESPACE}"

    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install jq for JSON parsing"
        exit 1
    fi

    # Create namespace
    kubectl create namespace "${NAMESPACE}" --ignore-not-found=true

    # Run tests
    trap cleanup EXIT

    test_initial_install
    test_image_upgrade
    test_config_upgrade
    test_rollback
    test_upgrade_after_rollback
    test_rolling_update
    test_revision_history

    print_summary
}

# Run main function
main "$@"
