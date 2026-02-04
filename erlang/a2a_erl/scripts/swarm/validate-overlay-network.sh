#!/usr/bin/env bash
# =============================================================================
# Docker Swarm Overlay Network Validation for A2A Services
# =============================================================================
# Validates:
# 1. Overlay networks create
# 2. Services attach to networks
# 3. Service discovery by name works
# 4. Inter-service communication works
# 5. Network isolation is correct
# =============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

record_result() {
    local result=$1
    local test_name=$2
    local message="${3:-}"
    ((TESTS_TOTAL++))
    if [[ "${result}" == "pass" ]]; then
        log_info "PASS: ${test_name}"
        [[ -n "${message}" ]] && log_info "      ${message}"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "FAIL: ${test_name}"
        [[ -n "${message}" ]] && log_error "      ${message}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Configuration
STACK_NAME="a2a-validate"
NETWORK_NAME="a2a-validate-overlay"

# Cleanup trap
cleanup() {
    echo ""
    log_info "Cleaning up..."
    docker stack rm "${STACK_NAME}" 2>/dev/null || true
    sleep 3
    docker network rm "${NETWORK_NAME}" 2>/dev/null || true
}

trap cleanup EXIT

# =============================================================================
# Test 1: Overlay Network Creation
# =============================================================================
test_overlay_network_creation() {
    log_test "Test 1: Overlay network creation"

    # Create overlay network first - suppress network ID output
    if docker network create --driver overlay --attachable "${NETWORK_NAME}" >/dev/null 2>&1; then
        log_info "Created overlay network ${NETWORK_NAME}"
    else
        log_info "Network ${NETWORK_NAME} already exists or creation failed"
    fi

    # Verify network exists
    sleep 2
    if ! docker network inspect "${NETWORK_NAME}" &>/dev/null; then
        record_result "fail" "Overlay network creation" "Network not found after creation"
        return 1
    fi

    # Verify network properties
    local driver
    driver=$(docker network inspect "${NETWORK_NAME}" --format '{{.Driver}}' 2>/dev/null || echo "")
    local attachable
    attachable=$(docker network inspect "${NETWORK_NAME}" --format '{{.Attachable}}' 2>/dev/null || echo "")
    local scope
    scope=$(docker network inspect "${NETWORK_NAME}" --format '{{.Scope}}' 2>/dev/null || echo "")

    if [[ "${driver}" == "overlay" ]] && [[ "${attachable}" == "true" ]] && [[ "${scope}" == "swarm" ]]; then
        record_result "pass" "Overlay network creation" "Driver: ${driver}, Attachable: ${attachable}, Scope: ${scope}"
        return 0
    else
        record_result "fail" "Overlay network creation" "Driver: ${driver}, Attachable: ${attachable}, Scope: ${scope}"
        return 1
    fi
}

# =============================================================================
# Test 2: Services Attach to Networks
# =============================================================================
test_services_attach() {
    log_test "Test 2: Services attach to networks"

    # Create compose file
    local compose_file="/tmp/${STACK_NAME}-stack-${RANDOM}.yml"

    printf '%s' "version: '3.8'

services:
  a2a-1:
    image: a2a-erl:runtime
    networks:
      - ${NETWORK_NAME}
    deploy:
      replicas: 1
      endpoint_mode: dnsrr

  a2a-2:
    image: a2a-erl:runtime
    networks:
      - ${NETWORK_NAME}
    deploy:
      replicas: 1
      endpoint_mode: dnsrr

  discovery:
    image: nicolaka/netshoot:latest
    command: /bin/sh -c 'sleep 3600'
    networks:
      - ${NETWORK_NAME}
    deploy:
      replicas: 1

networks:
  ${NETWORK_NAME}:
    external: true
" > "${compose_file}"

    # Deploy stack
    docker stack deploy -c "${compose_file}" "${STACK_NAME}" 2>&1 | grep -v "detach" || true
    rm -f "${compose_file}"

    # Wait for services
    local max_wait=90
    local waited=0
    while [[ ${waited} -lt ${max_wait} ]]; do
        local running
        running=$(docker stack ps "${STACK_NAME}" --format "{{.CurrentState}}" 2>/dev/null | grep -c "Running" || true)
        running=${running:-0}
        if [[ "${running}" -ge 3 ]]; then
            break
        fi
        sleep 3
        ((waited+=3))
        echo -n "."
    done
    echo ""

    # Check network has containers using python3
    local containers
    containers=$(docker network inspect "${NETWORK_NAME}" --format '{{json .Containers}}' 2>/dev/null | python3 -c "import sys,json; c=json.load(sys.stdin); print(len(c) if c else 0)" 2>/dev/null || echo "0")

    if [[ "${containers}" -ge 3 ]]; then
        record_result "pass" "Services attach to network" "Found ${containers} containers on overlay network"
        return 0
    else
        record_result "fail" "Services attach to network" "Found only ${containers} containers, expected 3"
        return 1
    fi
}

# =============================================================================
# Test 3: Service Discovery by Name
# =============================================================================
test_service_discovery() {
    log_test "Test 3: Service discovery by name"

    # Find discovery container
    local discovery_container
    discovery_container=$(docker ps --filter "label=com.docker.swarm.service.name=${STACK_NAME}_discovery" --format "{{.ID}}" | head -1)

    if [[ -z "${discovery_container}" ]]; then
        record_result "fail" "Service discovery" "Discovery container not found"
        return 1
    fi

    # Test DNS resolution for a2a-1
    if ! docker exec "${discovery_container}" nslookup a2a-1 &>/dev/null; then
        record_result "fail" "Service discovery" "Cannot resolve a2a-1"
        return 1
    fi

    local ip
    ip=$(docker exec "${discovery_container}" nslookup a2a-1 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    if [[ -n "${ip}" ]]; then
        log_info "  a2a-1 resolves to ${ip}"
    fi

    # Test DNS resolution for a2a-2
    if ! docker exec "${discovery_container}" nslookup a2a-2 &>/dev/null; then
        record_result "fail" "Service discovery" "Cannot resolve a2a-2"
        return 1
    fi

    ip=$(docker exec "${discovery_container}" nslookup a2a-2 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    if [[ -n "${ip}" ]]; then
        log_info "  a2a-2 resolves to ${ip}"
    fi

    # Test tasks discovery
    if ! docker exec "${discovery_container}" nslookup tasks.a2a-1 &>/dev/null; then
        record_result "fail" "Service discovery" "Cannot resolve tasks.a2a-1"
        return 1
    fi

    record_result "pass" "Service discovery by name" "All services resolvable via DNS"
    return 0
}

# =============================================================================
# Test 4: Inter-Service Communication
# =============================================================================
test_inter_service_communication() {
    log_test "Test 4: Inter-service communication"

    local discovery_container
    discovery_container=$(docker ps --filter "label=com.docker.swarm.service.name=${STACK_NAME}_discovery" --format "{{.ID}}" | head -1)

    if [[ -z "${discovery_container}" ]]; then
        record_result "fail" "Inter-service communication" "Discovery container not found"
        return 1
    fi

    # Wait for services to be ready
    log_info "  Waiting for services to be healthy..."
    sleep 15

    # Test HTTP to a2a-1
    local http_code_1
    http_code_1=$(docker exec "${discovery_container}" curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://a2a-1:8080/health 2>/dev/null || echo "000")

    # Test HTTP to a2a-2
    local http_code_2
    http_code_2=$(docker exec "${discovery_container}" curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://a2a-2:8080/health 2>/dev/null || echo "000")

    if [[ "${http_code_1}" == "200" ]] && [[ "${http_code_2}" == "200" ]]; then
        record_result "pass" "Inter-service communication" "a2a-1: HTTP ${http_code_1}, a2a-2: HTTP ${http_code_2}"
        return 0
    else
        record_result "fail" "Inter-service communication" "a2a-1: HTTP ${http_code_1}, a2a-2: HTTP ${http_code_2}"
        return 1
    fi
}

# =============================================================================
# Test 5: Network Isolation
# =============================================================================
test_network_isolation() {
    log_test "Test 5: Network isolation"

    # Create a temporary container on bridge network
    local bridge_result
    bridge_result=$(docker run --rm --network bridge nicolaka/netshoot:latest nslookup a2a-1 2>&1 || echo "NXDOMAIN")

    if echo "${bridge_result}" | grep -q "NXDOMAIN\|can't find"; then
        record_result "pass" "Network isolation" "Services not reachable from bridge network (correct)"
        return 0
    else
        record_result "fail" "Network isolation" "Services reachable from bridge network (isolation broken)"
        return 1
    fi
}

# =============================================================================
# Test 6: Subnet Configuration
# =============================================================================
test_subnet_config() {
    log_test "Test 6: Subnet configuration"

    local subnet
    subnet=$(docker network inspect "${NETWORK_NAME}" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")

    if [[ -n "${subnet}" ]]; then
        record_result "pass" "Subnet configuration" "Overlay subnet: ${subnet}"
        return 0
    else
        record_result "fail" "Subnet configuration" "No subnet configured"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo "========================================"
    echo "  Overlay Network Validation"
    echo "========================================"
    echo ""

    # Check prerequisites
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found"
        exit 1
    fi

    local swarm_status
    swarm_status=$(docker info 2>/dev/null | grep "Swarm:" | awk '{print $2}' || echo "inactive")
    if [[ "${swarm_status}" != "active" ]]; then
        log_error "Docker Swarm is not active"
        exit 1
    fi

    # Run tests
    test_overlay_network_creation
    test_services_attach
    test_service_discovery
    test_inter_service_communication
    test_network_isolation
    test_subnet_config

    # Summary
    echo ""
    echo "========================================"
    echo "         TEST SUMMARY"
    echo "========================================"
    echo "Tests Passed: ${TESTS_PASSED}"
    echo "Tests Failed: ${TESTS_FAILED}"
    echo "Total Tests:  ${TESTS_TOTAL}"
    echo "========================================"
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_info "All overlay network tests passed!"
        exit 0
    else
        log_error "Some tests failed!"
        exit 1
    fi
}

main "$@"
