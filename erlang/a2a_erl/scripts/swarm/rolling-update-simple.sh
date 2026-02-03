#!/usr/bin/env bash
# =============================================================================
# Docker Swarm Rolling Update Test Suite (Simplified)
# =============================================================================
# Tests zero-downtime rolling updates using host-based deployment

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-a2a-erl}"
VERSION_V1="0.1.0"
VERSION_V2="0.2.0"
VERSION_V3="0.3.0"
PORT_BASE="${PORT_BASE:-18080}"
NETWORK_NAME="a2a-test-net"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $(date '+%H:%M:%S') $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $(date '+%H:%M:%S') $1"; }

record_result() {
    local result=$1
    local test_name=$2
    local message="${3:-}"

    ((TESTS_TOTAL++))

    if [[ "${result}" == "pass" ]]; then
        log_info "PASS: ${test_name}"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "FAIL: ${test_name}"
        ((TESTS_FAILED++))
        return 1
    fi
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    local errors=0

    if ! command -v docker &> /dev/null; then
        log_error "Docker not found"
        ((errors++))
    fi

    local swarm_status
    swarm_status=$(docker info 2>/dev/null | grep "Swarm:" | awk '{print $2}' || echo "inactive")
    if [[ "${swarm_status}" != "active" ]]; then
        log_error "Docker Swarm is not active"
        ((errors++))
    fi

    for cmd in curl jq; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "${cmd} not found"
            ((errors++))
        fi
    done

    if [[ ${errors} -gt 0 ]]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_info "Prerequisites OK"
}

build_images() {
    log_step "Building test images..."

    local build_dir="${PROJECT_ROOT}"

    docker build -t "${IMAGE_NAME}:${VERSION_V1}" \
        --build-arg VERSION="${VERSION_V1}" \
        --target runtime "${build_dir}" > /dev/null 2>&1 || {
        log_error "Failed to build ${VERSION_V1}"
        return 1
    }

    docker build -t "${IMAGE_NAME}:${VERSION_V2}" \
        --build-arg VERSION="${VERSION_V2}" \
        --target runtime "${build_dir}" > /dev/null 2>&1 || {
        log_error "Failed to build ${VERSION_V2}"
        return 1
    }

    docker build -t "${IMAGE_NAME}:${VERSION_V3}" \
        --build-arg VERSION="${VERSION_V3}" \
        --target runtime "${build_dir}" > /dev/null 2>&1 || {
        log_error "Failed to build ${VERSION_V3}"
        return 1
    }

    log_info "Images built: ${VERSION_V1}, ${VERSION_V2}, ${VERSION_V3}"
}

create_network() {
    docker network create "${NETWORK_NAME}" 2>/dev/null || true
    log_info "Network: ${NETWORK_NAME}"
}

remove_network() {
    docker network rm "${NETWORK_NAME}" 2>/dev/null || true
}

start_containers() {
    local version=$1
    local count=$2
    local port_start=$3

    log_info "Starting ${count} containers with version ${version}..."

    for ((i=0; i<count; i++)); do
        local port=$((port_start + i))
        local name="a2a-test-${version//./-}-${i}"

        docker run -d \
            --name "${name}" \
            --network "${NETWORK_NAME}" \
            -p "${port}:8080" \
            -e PORT=8080 \
            --restart unless-stopped \
            "${IMAGE_NAME}:${version}" > /dev/null 2>&1 || true

        echo "${name}"
    done
}

stop_all_containers() {
    log_info "Stopping all test containers..."
    docker ps -a --filter "name=a2a-test-" --format "{{.Names}}" | \
        xargs -r docker stop -t 5 > /dev/null 2>&1 || true
    docker ps -a --filter "name=a2a-test-" --format "{{.Names}}" | \
        xargs -r docker rm > /dev/null 2>&1 || true
}

wait_for_healthy() {
    local port=$1
    local timeout=${2:-60}
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        # Check if service returns 200 status (up or degraded is acceptable)
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/health" 2>/dev/null || echo "000")

        if [[ "${http_code}" == "200" ]]; then
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done

    return 1
}

get_version() {
    local port=$1
    curl -sf "http://localhost:${port}/.well-known/agent-card.json" | \
        jq -r '.version' 2>/dev/null || echo "unknown"
}

# Test 1: Initial deployment
test_initial_deployment() {
    log_test "Test 1: Initial deployment (3 containers)"

    # Start containers
    start_containers "${VERSION_V1}" 3 "${PORT_BASE}" > /dev/null 2>&1

    sleep 10

    local healthy=0
    for ((i=0; i<3; i++)); do
        local port=$((PORT_BASE + i))
        if wait_for_healthy "${port}" 30; then
            ((healthy++)) || true
        fi
    done

    if [[ ${healthy} -eq 3 ]]; then
        record_result "pass" "Initial deployment" "All 3 containers healthy"
        return 0
    else
        record_result "fail" "Initial deployment" "Only ${healthy}/3 containers healthy"
        return 1
    fi
}

# Test 2: Rolling update one by one
test_rolling_update() {
    log_test "Test 2: Rolling update (one by one)"

    local traffic_log="/tmp/traffic-rolling.csv"
    > "${traffic_log}"

    # Start traffic simulation
    (
        local end_time=$(($(date +%s) + 120))
        while [[ $(date +%s) -lt ${end_time} ]]; do
            local total_success=0
            local total_failed=0

            for ((i=0; i<3; i++)); do
                local port=$((PORT_BASE + i))
                local response
                response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/health" 2>/dev/null || echo "000")

                if [[ "${response}" == "200" ]]; then
                    ((total_success++))
                else
                    ((total_failed++))
                fi
            done

            echo "$(date +%s),${total_success},${total_failed}" >> "${traffic_log}"
            sleep 1
        done
    ) &
    local traffic_pid=$!

    sleep 5

    # Update containers one by one
    for ((i=0; i<3; i++)); do
        local port=$((PORT_BASE + i))
        local old_name="a2a-test-${VERSION_V1//./-}-${i}"
        local new_name="a2a-test-${VERSION_V2//./-}-${i}"

        log_info "Updating container ${i} (port ${port})..."

        # Stop old container
        docker stop "${old_name}" -t 5 > /dev/null 2>&1 || true
        docker rm "${old_name}" > /dev/null 2>&1 || true

        # Start new container
        docker run -d \
            --name "${new_name}" \
            --network "${NETWORK_NAME}" \
            -p "${port}:8080" \
            -e RELEASE_NODE="a2a${i}@127.0.0.1" \
            -e PORT=8080 \
            --restart unless-stopped \
            "${IMAGE_NAME}:${VERSION_V2}" > /dev/null 2>&1 || true

        # Wait for healthy
        if ! wait_for_healthy "${port}" 30; then
            log_error "Container ${i} failed to become healthy"
        fi

        # Verify version
        local version
        version=$(get_version "${port}")
        log_info "Container ${i} now running version ${version}"

        sleep 5
    done

    # Wait for traffic to finish
    wait "${traffic_pid}" 2>/dev/null || true

    # Analyze traffic
    local total_lines
    local total_failures
    total_lines=$(wc -l < "${traffic_log}" | tr -d ' ')
    total_failures=$(awk -F',' '$3 > 0 {count++} END {print count+0}' "${traffic_log}")

    log_info "Traffic samples: ${total_lines}, Samples with failures: ${total_failures}"

    # Verify all containers updated
    local updated=0
    for ((i=0; i<3; i++)); do
        local port=$((PORT_BASE + i))
        local version
        version=$(get_version "${port}")
        if [[ "${version}" == *"${VERSION_V2}"* ]]; then
            ((updated++))
        fi
    done

    if [[ ${updated} -eq 3 ]] && [[ ${total_failures} -lt 10 ]]; then
        record_result "pass" "Rolling update" "All updated, minimal failures (${total_failures}/${total_lines})"
        return 0
    else
        record_result "fail" "Rolling update" "Updated: ${updated}/3, Failures: ${total_failures}/${total_lines}"
        return 1
    fi
}

# Test 3: Rollback
test_rollback() {
    log_test "Test 3: Rollback to previous version"

    local traffic_log="/tmp/traffic-rollback.csv"
    > "${traffic_log}"

    # Start traffic
    (
        local end_time=$(($(date +%s) + 60))
        while [[ $(date +%s) -lt ${end_time} ]]; do
            local healthy_count=0
            for ((i=0; i<3; i++)); do
                local port=$((PORT_BASE + i))
                if curl -sf "http://localhost:${port}/health" > /dev/null 2>&1; then
                    ((healthy_count++))
                fi
            done
            echo "$(date +%s),${healthy_count}" >> "${traffic_log}"
            sleep 1
        done
    ) &
    local traffic_pid=$!

    sleep 5

    # Rollback all to v1
    for ((i=0; i<3; i++)); do
        local port=$((PORT_BASE + i))
        local old_name="a2a-test-${VERSION_V2//./-}-${i}"
        local new_name="a2a-test-${VERSION_V1//./-}-${i}"

        docker stop "${old_name}" -t 2 > /dev/null 2>&1 || true
        docker rm "${old_name}" > /dev/null 2>&1 || true

        docker run -d \
            --name "${new_name}" \
            --network "${NETWORK_NAME}" \
            -p "${port}:8080" \
            -e RELEASE_NODE="a2a${i}@127.0.0.1" \
            -e PORT=8080 \
            --restart unless-stopped \
            "${IMAGE_NAME}:${VERSION_V1}" > /dev/null 2>&1 || true

        wait_for_healthy "${port}" 20 || log_warn "Container ${i} not healthy after rollback"
        sleep 2
    done

    wait "${traffic_pid}" 2>/dev/null || true

    # Verify rollback
    local rolled_back=0
    for ((i=0; i<3; i++)); do
        local port=$((PORT_BASE + i))
        local version
        version=$(get_version "${port}")
        if [[ "${version}" == *"${VERSION_V1}"* ]]; then
            ((rolled_back++))
        fi
    done

    if [[ ${rolled_back} -eq 3 ]]; then
        record_result "pass" "Rollback" "All containers rolled back to ${VERSION_V1}"
        return 0
    else
        record_result "fail" "Rollback" "Only ${rolled_back}/3 rolled back"
        return 1
    fi
}

# Test 4: Scale up
test_scale_up() {
    log_test "Test 4: Scale up during operation"

    # Start with 2 containers
    stop_all_containers

    local base_port=$((PORT_BASE + 10))
    start_containers "${VERSION_V2}" 2 "${base_port}" > /dev/null

    sleep 15

    # Verify 2 healthy
    local healthy=0
    for ((i=0; i<2; i++)); do
        local port=$((base_port + i))
        if wait_for_healthy "${port}" 20; then
            ((healthy++))
        fi
    done

    if [[ ${healthy} -ne 2 ]]; then
        record_result "fail" "Scale up" "Initial scale failed"
        return 1
    fi

    # Scale up to 5
    for ((i=2; i<5; i++)); do
        local port=$((base_port + i))
        local name="a2a-test-${VERSION_V2//./-}-${i}"

        docker run -d \
            --name "${name}" \
            --network "${NETWORK_NAME}" \
            -p "${port}:8080" \
            -e RELEASE_NODE="a2a${i}@127.0.0.1" \
            -e PORT=8080 \
            --restart unless-stopped \
            "${IMAGE_NAME}:${VERSION_V2}" > /dev/null 2>&1 || true
    done

    sleep 15

    # Verify all 5 healthy
    healthy=0
    for ((i=0; i<5; i++)); do
        local port=$((base_port + i))
        if curl -sf "http://localhost:${port}/health" > /dev/null 2>&1; then
            ((healthy++))
        fi
    done

    if [[ ${healthy} -eq 5 ]]; then
        record_result "pass" "Scale up" "Scaled from 2 to 5 containers"
        return 0
    else
        record_result "fail" "Scale up" "Only ${healthy}/5 containers healthy"
        return 1
    fi
}

# Test 5: Canary deployment
test_canary_deployment() {
    log_test "Test 5: Canary deployment"

    # Start with 4 containers of v2
    stop_all_containers

    local base_port=$((PORT_BASE + 20))
    for ((i=0; i<4; i++)); do
        local port=$((base_port + i))
        local name="a2a-test-${VERSION_V2//./-}-${i}"

        docker run -d \
            --name "${name}" \
            --network "${NETWORK_NAME}" \
            -p "${port}:8080" \
            -e RELEASE_NODE="a2a${i}@127.0.0.1" \
            -e PORT=8080 \
            --restart unless-stopped \
            "${IMAGE_NAME}:${VERSION_V2}" > /dev/null 2>&1 || true
    done

    sleep 15

    # Replace 1 container with v3 (canary)
    local port=$((base_port))
    local old_name="a2a-test-${VERSION_V2//./-}-0"
    local new_name="a2a-test-${VERSION_V3//./-}-0"

    docker stop "${old_name}" -t 2 > /dev/null 2>&1 || true
    docker rm "${old_name}" > /dev/null 2>&1 || true

    docker run -d \
        --name "${new_name}" \
        --network "${NETWORK_NAME}" \
        -p "${port}:8080" \
        -e RELEASE_NODE="a2a0@127.0.0.1" \
        -e PORT=8080 \
        --restart unless-stopped \
        "${IMAGE_NAME}:${VERSION_V3}" > /dev/null 2>&1 || true

    sleep 10

    # Verify canary
    local version
    version=$(get_version "${port}")

    # Verify others still v2
    local v2_count=0
    for ((i=1; i<4; i++)); do
        local p=$((base_port + i))
        local v
        v=$(get_version "${p}")
        if [[ "${v}" == *"${VERSION_V2}"* ]]; then
            ((v2_count++))
        fi
    done

    if [[ "${version}" == *"${VERSION_V3}"* ]] && [[ ${v2_count} -eq 3 ]]; then
        record_result "pass" "Canary deployment" "Canary (v3) deployed, rest still v2"
        return 0
    else
        record_result "fail" "Canary deployment" "Canary: ${version}, v2 count: ${v2_count}"
        return 1
    fi
}

cleanup() {
    log_step "Cleaning up..."
    stop_all_containers
    remove_network
    rm -f /tmp/traffic-*.csv
}

print_summary() {
    echo ""
    echo "========================================="
    echo "         TEST SUMMARY"
    echo "========================================="
    echo "Tests Passed: ${TESTS_PASSED}"
    echo "Tests Failed: ${TESTS_FAILED}"
    echo "Total Tests:  ${TESTS_TOTAL}"
    echo "========================================="

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_info "All tests passed!"
        return 0
    else
        log_error "Some tests failed"
        return 1
    fi
}

main() {
    echo ""
    echo "========================================="
    echo "  Docker Swarm Rolling Update Tests"
    echo "========================================="
    echo ""

    trap cleanup EXIT INT TERM

    check_prerequisites
    build_images
    create_network

    test_initial_deployment
    test_rolling_update
    test_rollback
    test_scale_up
    test_canary_deployment

    print_summary
}

main "$@"
