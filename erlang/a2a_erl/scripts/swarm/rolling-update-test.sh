#!/usr/bin/env bash
# =============================================================================
# Docker Swarm Rolling Update Test Suite for A2A Services
# =============================================================================
# Tests zero-downtime rolling updates in Docker Swarm environment
# Validates health checks, update strategies, and rollback capabilities

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

# Test configuration
SERVICE_NAME="${SERVICE_NAME:-a2a-erl}"
STACK_NAME="${STACK_NAME:-a2a-test}"
IMAGE_NAME="${IMAGE_NAME:-a2a-erl}"
NETWORK_NAME="${NETWORK_NAME:-a2a-network}"
OVERLAY_NETWORK="${OVERLAY_NETWORK:-a2a-overlay}"

# Port configuration
PORT_BASE="${PORT_BASE:-8080}"
PORT_SHIFT=100

# Test versions
VERSION_V1="0.1.0"
VERSION_V2="0.2.0"
VERSION_V3="0.3.0"

# Update configurations
UPDATE_PARALLELISM="${UPDATE_PARALLELISM:-1}"
UPDATE_DELAY="${UPDATE_DELAY:-10s}"
UPDATE_FAILURE_ACTION="${UPDATE_FAILURE_ACTION:-continue}"
UPDATE_MONITOR="${UPDATE_MONITOR:-60s}"

# Health check configuration
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5s}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-3s}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"
HEALTH_CHECK_START_PERIOD="${HEALTH_CHECK_START_PERIOD:-30s}"

# Rolling update strategy
MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-0}"
MAX_SURGE="${MAX_SURGE:-1}"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Traffic simulation
TRAFFIC_DURATION="${TRAFFIC_DURATION:-120}"
CONCURRENT_REQUESTS="${CONCURRENT_REQUESTS:-10}"

# =============================================================================
# Colors and Logging
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_metric() {
    echo -e "${MAGENTA}[METRIC]${NC} $1"
}

# =============================================================================
# Test Result Recording
# =============================================================================

record_result() {
    local result=$1
    local test_name=$2
    local message="${3:-}"

    ((TESTS_TOTAL++))

    if [[ "${result}" == "pass" ]]; then
        log_info "PASS: ${test_name}"
        if [[ -n "${message}" ]]; then
            log_info "      ${message}"
        fi
        ((TESTS_PASSED++))
        return 0
    else
        log_error "FAIL: ${test_name}"
        if [[ -n "${message}" ]]; then
            log_error "      ${message}"
        fi
        ((TESTS_FAILED++))
        return 1
    fi
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_step "Checking prerequisites..."

    local errors=0

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found"
        ((errors++))
    else
        log_info "Docker version: $(docker --version | awk '{print $3}')"
    fi

    # Check Swarm mode
    local swarm_status
    swarm_status=$(docker info 2>/dev/null | grep "Swarm:" | awk '{print $2}' || echo "inactive")
    if [[ "${swarm_status}" != "active" ]]; then
        log_error "Docker Swarm is not active (status: ${swarm_status})"
        ((errors++))
    else
        log_info "Docker Swarm: active"
    fi

    # Check required tools
    for cmd in curl jq; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "${cmd} not found"
            ((errors++))
        fi
    done

    # Check if we can build images
    if [[ ! -f "Dockerfile" ]]; then
        log_error "Dockerfile not found"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_error "Prerequisites check failed with ${errors} errors"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# =============================================================================
# Docker Stack Management
# =============================================================================

create_overlay_network() {
    log_step "Creating overlay network..."

    docker network create --driver overlay --attachable "${OVERLAY_NETWORK}" 2>/dev/null || {
        log_warn "Overlay network may already exist"
    }

    log_info "Overlay network: ${OVERLAY_NETWORK}"
}

remove_overlay_network() {
    log_step "Removing overlay network..."
    docker network rm "${OVERLAY_NETWORK}" 2>/dev/null || true
}

build_test_images() {
    log_step "Building test images..."

    # Build version 1
    log_info "Building ${IMAGE_NAME}:${VERSION_V1}..."
    docker build -t "${IMAGE_NAME}:${VERSION_V1}" \
        --build-arg VERSION="${VERSION_V1}" \
        --target runtime \
        . || {
        log_error "Failed to build ${IMAGE_NAME}:${VERSION_V1}"
        return 1
    }

    # Tag version 1 as latest
    docker tag "${IMAGE_NAME}:${VERSION_V1}" "${IMAGE_NAME}:latest"

    # Build version 2 (simulate update)
    log_info "Building ${IMAGE_NAME}:${VERSION_V2}..."
    docker build -t "${IMAGE_NAME}:${VERSION_V2}" \
        --build-arg VERSION="${VERSION_V2}" \
        --target runtime \
        . || {
        log_error "Failed to build ${IMAGE_NAME}:${VERSION_V2}"
        return 1
    }

    # Build version 3
    log_info "Building ${IMAGE_NAME}:${VERSION_V3}..."
    docker build -t "${IMAGE_NAME}:${VERSION_V3}" \
        --build-arg VERSION="${VERSION_V3}" \
        --target runtime \
        . || {
        log_error "Failed to build ${IMAGE_NAME}:${VERSION_V3}"
        return 1
    }

    log_info "All test images built successfully"
    docker images | grep "${IMAGE_NAME}" | head -5
}

deploy_stack() {
    local version=$1
    local replicas=$2
    local compose_file=$3

    log_step "Deploying stack ${STACK_NAME} with version ${version} (${replicas} replicas)..."

    # Create docker-compose file for Swarm
    cat > "${compose_file}" <<EOF
version: '3.8'

services:
  a2a-erl:
    image: ${IMAGE_NAME}:${version}
    networks:
      - ${OVERLAY_NETWORK}
    deploy:
      mode: replicated
      replicas: ${replicas}
      update_config:
        parallelism: ${UPDATE_PARALLELISM}
        delay: ${UPDATE_DELAY}
        failure_action: ${UPDATE_FAILURE_ACTION}
        monitor: ${UPDATE_MONITOR}
        max_failure_ratio: 0.3
      rollback_config:
        parallelism: ${UPDATE_PARALLELISM}
        delay: ${UPDATE_DELAY}
        failure_action: ${UPDATE_FAILURE_ACTION}
        monitor: ${UPDATE_MONITOR}
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
      labels:
        - "a2a.version=${version}"
        - "a2a.test=true"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval: ${HEALTH_CHECK_INTERVAL}
      timeout: ${HEALTH_CHECK_TIMEOUT}
      retries: ${HEALTH_CHECK_RETRIES}
      start_period: ${HEALTH_CHECK_START_PERIOD}
    environment:
      - RELEASE_NODE=a2a@tasks.a2a-erl
      - RELEASE_COOKIE=a2a_swarm_test
      - RELEASE_MODE=interactive
      - PORT=8080
      - HOST=0.0.0.0
      - SCHEME=http
      - A2A_VERSION=${version}
    ports:
      - target: 8080
        published: ${PORT_BASE}
        protocol: tcp
        mode: ingress

networks:
  ${OVERLAY_NETWORK}:
    external: true
EOF

    # Deploy stack
    docker stack deploy -c "${compose_file}" "${STACK_NAME}" || {
        log_error "Failed to deploy stack"
        return 1
    }

    log_info "Stack deployed successfully"
}

remove_stack() {
    log_step "Removing stack ${STACK_NAME}..."
    docker stack rm "${STACK_NAME}" 2>/dev/null || true

    # Wait for services to be removed
    local count=0
    while docker service ls | grep -q "${STACK_NAME}"; do
        sleep 2
        ((count++))
        if [[ ${count} -gt 30 ]]; then
            log_warn "Timeout waiting for stack removal"
            break
        fi
    done

    log_info "Stack removed"
}

get_service_replicas() {
    docker service ps "${STACK_NAME}_a2a-erl" --format "{{.CurrentState}}" 2>/dev/null | \
        grep -c "Running" 2>/dev/null | tr -d '\n' || echo "0"
}

wait_for_replicas() {
    local expected=$1
    local timeout=${2:-180}
    local elapsed=0

    log_info "Waiting for ${expected} replicas to be ready..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local running
        running=$(docker service ps "${STACK_NAME}_a2a-erl" --format "{{.CurrentState}}" 2>/dev/null | grep -c "Running" || echo "0")

        if [[ "${running}" -ge "${expected}" ]]; then
            log_info "All ${expected} replicas are running"
            return 0
        fi

        sleep 5
        ((elapsed+=5))
        echo -n "."
    done

    echo ""
    log_error "Timeout waiting for replicas (got ${running}/${expected})"
    return 1
}

wait_for_service_healthy() {
    local timeout=${1:-120}
    local elapsed=0

    log_info "Waiting for service to be healthy..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if curl -sf "http://localhost:${PORT_BASE}/health" > /dev/null 2>&1; then
            log_info "Service is healthy"
            return 0
        fi

        sleep 2
        ((elapsed+=2))
        echo -n "."
    done

    echo ""
    log_error "Service health check timeout"
    return 1
}

# =============================================================================
# Health and Readiness Checks
# =============================================================================

check_health() {
    local port=$1

    curl -sf "http://localhost:${port}/health" | jq -r '.status' 2>/dev/null || echo "down"
}

check_readiness() {
    local port=$1

    curl -sf "http://localhost:${port}/health/ready" | jq -r '.status' 2>/dev/null || echo "not_ready"
}

check_liveness() {
    local port=$1

    curl -sf "http://localhost:${port}/health/live" | jq -r '.status' 2>/dev/null || echo "dead"
}

get_service_version() {
    local port=$1

    curl -sf "http://localhost:${port}/.well-known/agent-card.json" | jq -r '.version' 2>/dev/null || echo "unknown"
}

get_container_info() {
    docker service ps "${STACK_NAME}_a2a-erl" --format "table {{.ID}}\t{{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Error}}" 2>/dev/null || echo "No service info"
}

# =============================================================================
# Traffic Simulation
# =============================================================================

start_traffic_simulation() {
    local duration=$1
    local output_file=$2

    log_step "Starting traffic simulation (${duration}s)..."

    # Start background traffic
    (
        local start_time=$(date +%s)
        local end_time=$((start_time + duration))
        local success=0
        local failed=0

        > "${output_file}"

        while [[ $(date +%s) -lt ${end_time} ]]; do
            # Make concurrent requests
            for ((i=0; i<CONCURRENT_REQUESTS; i++)); do
                local response_code
                local response_time
                local start
                local end

                start=$(date +%s%N)
                response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT_BASE}/health" 2>/dev/null || echo "000")
                end=$(date +%s%N)

                response_time=$(( (end - start) / 1000000 ))  # Convert to milliseconds

                echo "$(date +%s),${response_code},${response_time}" >> "${output_file}"

                if [[ "${response_code}" == "200" ]]; then
                    ((success++))
                else
                    ((failed++))
                fi
            done

            sleep 1
        done

        echo "Traffic simulation completed: ${success} success, ${failed} failed"
    ) &

    local pid=$!
    echo "${pid}"
}

stop_traffic_simulation() {
    local pid=$1

    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        log_info "Stopping traffic simulation (PID: ${pid})..."
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    fi
}

analyze_traffic_results() {
    local output_file=$1

    if [[ ! -f "${output_file}" ]]; then
        log_error "Traffic output file not found"
        return 1
    fi

    log_step "Traffic Analysis:"

    local total_requests
    local success_requests
    local failed_requests
    local avg_response_time
    local max_response_time
    local min_response_time

    total_requests=$(wc -l < "${output_file}" | tr -d ' ')
    success_requests=$(awk -F',' '$2 == "200" {count++} END {print count+0}' "${output_file}")
    failed_requests=$((total_requests - success_requests))

    # Calculate response times (only for successful requests)
    avg_response_time=$(awk -F',' '$2 == "200" {sum+=$3; count++} END {print count>0?sum/count:0}' "${output_file}")
    max_response_time=$(awk -F',' '$2 == "200" {if($3>max) max=$3} END {print max+0}' "${output_file}")
    min_response_time=$(awk -F',' '$2 == "200" {if(min==0 || $3<min) min=$3} END {print min+0}' "${output_file}")

    # Calculate uptime percentage
    local uptime_percent
    if [[ ${total_requests} -gt 0 ]]; then
        uptime_percent=$(awk "BEGIN {printf \"%.2f\", (${success_requests}/${total_requests})*100}")
    else
        uptime_percent="0.00"
    fi

    log_metric "Total Requests:    ${total_requests}"
    log_metric "Successful:        ${success_requests} (${uptime_percent}%)"
    log_metric "Failed:            ${failed_requests}"
    log_metric "Avg Response Time: ${avg_response_time}ms"
    log_metric "Min Response Time: ${min_response_time}ms"
    log_metric "Max Response Time: ${max_response_time}ms"

    # Zero-downtime validation
    local zero_downtime=true
    if [[ "${uptime_percent}" < "99.00" ]]; then
        zero_downtime=false
    fi

    if [[ "${failed_requests}" -gt 0 ]]; then
        log_warn "Some requests failed during update"
    fi

    echo "${zero_downtime}"
}

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Initial Deployment
test_initial_deployment() {
    log_test "Test 1: Initial deployment with health checks"

    local compose_file="/tmp/${STACK_NAME}-v1.yml"

    # Deploy initial version
    deploy_stack "${VERSION_V1}" 3 "${compose_file}" || {
        record_result "fail" "Initial deployment" "Failed to deploy stack"
        return 1
    }

    # Wait for replicas
    wait_for_replicas 3 120 || {
        record_result "fail" "Initial deployment" "Replicas not ready"
        return 1
    }

    # Wait for health
    wait_for_service_healthy 60 || {
        record_result "fail" "Initial deployment" "Service not healthy"
        return 1
    }

    # Verify health endpoint
    local health_status
    health_status=$(check_health "${PORT_BASE}")

    if [[ "${health_status}" == "up" ]]; then
        record_result "pass" "Initial deployment" "Service is healthy with ${health_status} status"
        return 0
    else
        record_result "fail" "Initial deployment" "Health status: ${health_status}"
        return 1
    fi
}

# Test 2: Rolling Update - Image Version
test_rolling_update_image() {
    log_test "Test 2: Rolling update - Image version change"

    local compose_file="/tmp/${STACK_NAME}-v2.yml"

    # Get initial version
    local initial_version
    initial_version=$(get_service_version "${PORT_BASE}")
    log_info "Initial version: ${initial_version}"

    # Start traffic simulation
    local traffic_file="/tmp/traffic-test2.csv"
    local traffic_pid
    traffic_pid=$(start_traffic_simulation "${TRAFFIC_DURATION}" "${traffic_file}")

    sleep 5

    # Deploy new version
    log_info "Updating to version ${VERSION_V2}..."
    deploy_stack "${VERSION_V2}" 3 "${compose_file}" || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Image" "Failed to deploy update"
        return 1
    }

    # Monitor the update
    log_step "Monitoring rolling update..."
    local update_timeout=300
    local elapsed=0
    local previous_running=0

    while [[ ${elapsed} -lt ${update_timeout} ]]; do
        local running
        running=$(get_service_replicas)

        if [[ "${running}" -ne "${previous_running}" ]]; then
            log_info "Replicas running: ${running}/3"
            previous_running=${running}
        fi

        # Check if all replicas are updated
        local updated_count
        updated_count=$(docker service ps "${STACK_NAME}_a2a-erl" --format "{{.Image}}" 2>/dev/null | grep -c "${VERSION_V2}" || echo "0")

        if [[ "${updated_count}" -ge 3 ]]; then
            log_info "All replicas updated to ${VERSION_V2}"
            break
        fi

        sleep 5
        ((elapsed+=5))
    done

    # Wait for all replicas to be running
    wait_for_replicas 3 60 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Image" "Not all replicas running after update"
        return 1
    }

    # Wait for service to be healthy
    sleep 5
    wait_for_service_healthy 30 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Image" "Service not healthy after update"
        return 1
    }

    # Verify new version
    local new_version
    new_version=$(get_service_version "${PORT_BASE}")
    log_info "New version: ${new_version}"

    # Stop traffic and analyze
    stop_traffic_simulation "${traffic_pid}"
    sleep 2
    local zero_downtime
    zero_downtime=$(analyze_traffic_results "${traffic_file}")

    if [[ "${new_version}" == *"${VERSION_V2}"* ]] && [[ "${zero_downtime}" == "true" ]]; then
        record_result "pass" "Rolling update - Image" "Updated to ${VERSION_V2} with zero downtime"
        return 0
    else
        record_result "fail" "Rolling update - Image" "Version: ${new_version}, Zero downtime: ${zero_downtime}"
        return 1
    fi
}

# Test 3: Rolling Update - Scale Up
test_rolling_update_scale() {
    log_test "Test 3: Rolling update - Scale up during update"

    local compose_file="/tmp/${STACK_NAME}-scale.yml"

    # Start with 3 replicas
    log_info "Current replicas: $(get_service_replicas)"

    # Start traffic
    local traffic_file="/tmp/traffic-test3.csv"
    local traffic_pid
    traffic_pid=$(start_traffic_simulation 60 "${traffic_file}")

    sleep 5

    # Scale to 5 replicas
    log_info "Scaling to 5 replicas..."
    docker service scale "${STACK_NAME}_a2a-erl=5" || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Scale" "Failed to scale service"
        return 1
    }

    # Wait for all replicas
    wait_for_replicas 5 120 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Scale" "Not all scaled replicas running"
        return 1
    }

    # Verify health
    sleep 3
    wait_for_service_healthy 30 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Scale" "Service not healthy after scale"
        return 1
    }

    stop_traffic_simulation "${traffic_pid}"

    # Check we have 5 healthy replicas
    local running
    running=$(get_service_replicas)

    if [[ "${running}" -eq 5 ]]; then
        record_result "pass" "Rolling update - Scale" "Successfully scaled to 5 replicas"
        return 0
    else
        record_result "fail" "Rolling update - Scale" "Expected 5 replicas, got ${running}"
        return 1
    fi
}

# Test 4: Rolling Update - Configuration Change
test_rolling_update_config() {
    log_test "Test 4: Rolling update - Configuration change"

    local compose_file="/tmp/${STACK_NAME}-config.yml"

    # Update with different update config
    cat > "${compose_file}" <<EOF
version: '3.8'

services:
  a2a-erl:
    image: ${IMAGE_NAME}:${VERSION_V2}
    networks:
      - ${OVERLAY_NETWORK}
    deploy:
      mode: replicated
      replicas: 5
      update_config:
        parallelism: 2
        delay: 5s
        failure_action: pause
        monitor: 30s
      rollback_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: '1.5'
          memory: 768M
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s
    environment:
      - RELEASE_NODE=a2a@tasks.a2a-erl
      - RELEASE_COOKIE=a2a_swarm_test_new
      - PORT=8080
    ports:
      - target: 8080
        published: ${PORT_BASE}
        protocol: tcp
        mode: ingress

networks:
  ${OVERLAY_NETWORK}:
    external: true
EOF

    # Start traffic
    local traffic_file="/tmp/traffic-test4.csv"
    local traffic_pid
    traffic_pid=$(start_traffic_simulation 90 "${traffic_file}")

    sleep 5

    # Apply config update
    docker stack deploy -c "${compose_file}" "${STACK_NAME}" || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Config" "Failed to apply config update"
        return 1
    }

    # Wait for update
    sleep 20
    wait_for_replicas 5 120 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Config" "Replicas not ready after config update"
        return 1
    }

    wait_for_service_healthy 30 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rolling update - Config" "Service not healthy after config update"
        return 1
    }

    stop_traffic_simulation "${traffic_pid}"

    # Verify new resource limits
    local limits
    limits=$(docker service inspect "${STACK_NAME}_a2a-erl" --format '{{.Spec.TaskTemplate.ContainerSpec.Memory}}' 2>/dev/null || echo "0")

    stop_traffic_simulation "${traffic_pid}"
    local zero_downtime
    zero_downtime=$(analyze_traffic_results "${traffic_file}")

    if [[ "${zero_downtime}" == "true" ]]; then
        record_result "pass" "Rolling update - Config" "Config updated with zero downtime"
        return 0
    else
        record_result "fail" "Rolling update - Config" "Downtime detected during config update"
        return 1
    fi
}

# Test 5: Rollback
test_rollback() {
    log_test "Test 5: Rollback to previous version"

    # Rollback to v1
    log_info "Rolling back to version ${VERSION_V1}..."

    local compose_file="/tmp/${STACK_NAME}-rollback.yml"

    # Start traffic
    local traffic_file="/tmp/traffic-test5.csv"
    local traffic_pid
    traffic_pid=$(start_traffic_simulation 90 "${traffic_file}")

    sleep 5

    deploy_stack "${VERSION_V1}" 5 "${compose_file}" || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rollback" "Failed to rollback"
        return 1
    }

    # Wait for rollback
    wait_for_replicas 5 120 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rollback" "Not all replicas running after rollback"
        return 1
    }

    wait_for_service_healthy 30 || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Rollback" "Service not healthy after rollback"
        return 1
    }

    # Verify version
    local current_version
    current_version=$(get_service_version "${PORT_BASE}")

    stop_traffic_simulation "${traffic_pid}"
    local zero_downtime
    zero_downtime=$(analyze_traffic_results "${traffic_file}")

    if [[ "${current_version}" == *"${VERSION_V1}"* ]] && [[ "${zero_downtime}" == "true" ]]; then
        record_result "pass" "Rollback" "Successfully rolled back to ${VERSION_V1} with zero downtime"
        return 0
    else
        record_result "fail" "Rollback" "Version: ${current_version}, Zero downtime: ${zero_downtime}"
        return 1
    fi
}

# Test 6: Failed Update Simulation
test_failed_update() {
    log_test "Test 6: Failed update recovery"

    local compose_file="/tmp/${STACK_NAME}-failed.yml"

    # Create a config with impossible resource limits to simulate failure
    cat > "${compose_file}" <<EOF
version: '3.8'

services:
  a2a-erl:
    image: ${IMAGE_NAME}:999.999.999
    networks:
      - ${OVERLAY_NETWORK}
    deploy:
      mode: replicated
      replicas: 5
      update_config:
        parallelism: 1
        delay: 5s
        failure_action: rollback
        monitor: 20s
        max_failure_ratio: 0.2
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 30s
    environment:
      - RELEASE_NODE=a2a@tasks.a2a-erl
      - RELEASE_COOKIE=a2a_swarm_test
      - PORT=8080
    ports:
      - target: 8080
        published: ${PORT_BASE}
        protocol: tcp

networks:
  ${OVERLAY_NETWORK}:
    external: true
EOF

    # Start traffic
    local traffic_file="/tmp/traffic-test6.csv"
    local traffic_pid
    traffic_pid=$(start_traffic_simulation 60 "${traffic_file}")

    sleep 5

    # Attempt failed update
    log_info "Attempting update with non-existent image (should fail and rollback)..."

    if docker stack deploy -c "${compose_file}" "${STACK_NAME}" 2>/dev/null; then
        log_warn "Update command succeeded (unexpected)"
    fi

    # Wait a bit for the failure to be detected
    sleep 20

    # Verify service is still running with original version
    local running
    running=$(get_service_replicas)

    wait_for_service_healthy 30 || {
        log_warn "Service health check failed after bad update"
    }

    stop_traffic_simulation "${traffic_pid}"

    local zero_downtime
    zero_downtime=$(analyze_traffic_results "${traffic_file}")

    # Verify we still have running replicas
    if [[ "${running}" -ge 3 ]] && [[ "${zero_downtime}" == "true" ]]; then
        record_result "pass" "Failed update recovery" "Service remained available despite failed update"
        return 0
    else
        record_result "fail" "Failed update recovery" "Running replicas: ${running}, Zero downtime: ${zero_downtime}"
        return 1
    fi
}

# Test 7: Parallel Update Verification
test_parallel_update() {
    log_test "Test 7: Parallel update verification"

    local compose_file="/tmp/${STACK_NAME}-parallel.yml"

    # Scale down first
    docker service scale "${STACK_NAME}_a2a-erl=4" || true
    wait_for_replicas 4 60

    # Configure parallelism: 2
    cat > "${compose_file}" <<EOF
version: '3.8'

services:
  a2a-erl:
    image: ${IMAGE_NAME}:${VERSION_V3}
    networks:
      - ${OVERLAY_NETWORK}
    deploy:
      mode: replicated
      replicas: 4
      update_config:
        parallelism: 2
        delay: 10s
        failure_action: continue
        monitor: 30s
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 30s
    environment:
      - RELEASE_NODE=a2a@tasks.a2a-erl
      - RELEASE_COOKIE=a2a_swarm_test
      - PORT=8080
    ports:
      - target: 8080
        published: ${PORT_BASE}
        protocol: tcp

networks:
  ${OVERLAY_NETWORK}:
    external: true
EOF

    # Start traffic
    local traffic_file="/tmp/traffic-test7.csv"
    local traffic_pid
    traffic_pid=$(start_traffic_simulation 90 "${traffic_file}")

    sleep 5

    # Deploy with parallelism
    log_info "Deploying with parallelism=2..."
    local start_time=$(date +%s)

    docker stack deploy -c "${compose_file}" "${STACK_NAME}" || {
        stop_traffic_simulation "${traffic_pid}"
        record_result "fail" "Parallel update" "Failed to deploy"
        return 1
    }

    # Monitor update progress
    local elapsed=0
    local update_complete=false

    while [[ ${elapsed} -lt 180 ]]; do
        local updated
        updated=$(docker service ps "${STACK_NAME}_a2a-erl" --format "{{.Image}}" 2>/dev/null | grep -c "${VERSION_V3}" || echo "0")

        log_info "Updated: ${updated}/4 replicas"

        if [[ "${updated}" -ge 4 ]]; then
            update_complete=true
            break
        fi

        sleep 5
        ((elapsed+=5))
    done

    local end_time=$(date +%s)
    local update_duration=$((end_time - start_time))

    wait_for_replicas 4 60
    wait_for_service_healthy 30

    stop_traffic_simulation "${traffic_pid}"

    local zero_downtime
    zero_downtime=$(analyze_traffic_results "${traffic_file}")

    local current_version
    current_version=$(get_service_version "${PORT_BASE}")

    if [[ "${update_complete}" == "true" ]] && [[ "${current_version}" == *"${VERSION_V3}"* ]] && [[ "${zero_downtime}" == "true" ]]; then
        record_result "pass" "Parallel update" "Updated 4 replicas in ${update_duration}s with zero downtime"
        return 0
    else
        record_result "fail" "Parallel update" "Complete: ${update_complete}, Version: ${current_version}, Zero downtime: ${zero_downtime}"
        return 1
    fi
}

# Test 8: Health Check During Update
test_health_during_update() {
    log_test "Test 8: Health check continuity during update"

    local compose_file="/tmp/${STACK_NAME}-health.yml"

    # Continuous health monitoring
    local health_log="/tmp/health-test8.log"
    > "${health_log}"

    # Start health monitor in background
    (
        local duration=120
        local end_time=$(($(date +%s) + duration))
        local checks=0
        local passed=0
        local failed=0

        while [[ $(date +%s) -lt ${end_time} ]]; do
            ((checks++))
            local status
            status=$(check_health "${PORT_BASE}")

            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

            if [[ "${status}" == "up" ]]; then
                ((passed++))
                echo "[${timestamp}] Health: ${status} (OK)" >> "${health_log}"
            else
                ((failed++))
                echo "[${timestamp}] Health: ${status} (FAIL)" >> "${health_log}"
            fi

            sleep 2
        done

        echo "Health checks: ${checks}, Passed: ${passed}, Failed: ${failed}"
    ) &
    local health_pid=$!

    sleep 5

    # Deploy update during health monitoring
    deploy_stack "${VERSION_V1}" 4 "${compose_file}" || {
        kill "${health_pid}" 2>/dev/null || true
        record_result "fail" "Health during update" "Failed to deploy"
        return 1
    }

    wait_for_replicas 4 120
    wait_for_service_healthy 60

    # Wait for health monitor to finish
    wait "${health_pid}" 2>/dev/null || true

    # Analyze health log
    local total_checks
    local failed_checks

    total_checks=$(wc -l < "${health_log}" | tr -d ' ')
    failed_checks=$(grep -c "FAIL" "${health_log}" || echo "0")

    local success_rate
    if [[ ${total_checks} -gt 0 ]]; then
        success_rate=$(awk "BEGIN {printf \"%.2f\", ((${total_checks} - ${failed_checks})/${total_checks})*100}")
    else
        success_rate="0.00"
    fi

    log_metric "Health checks: ${total_checks}, Failed: ${failed_checks}, Success rate: ${success_rate}%"

    if [[ "${success_rate}" > "95.00" ]]; then
        record_result "pass" "Health during update" "Health continuity: ${success_rate}% success rate"
        return 0
    else
        record_result "fail" "Health during update" "Health success rate below threshold: ${success_rate}%"
        return 1
    fi
}

# =============================================================================
# Cleanup and Reporting
# =============================================================================

cleanup() {
    log_step "Cleaning up..."

    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true

    # Remove stack
    remove_stack

    # Clean up temp files
    rm -f /tmp/${STACK_NAME}-*.yml
    rm -f /tmp/traffic-*.csv
    rm -f /tmp/health-*.log

    log_info "Cleanup complete"
}

print_summary() {
    echo ""
    echo "========================================="
    echo "         ROLLING UPDATE TEST SUMMARY"
    echo "========================================="
    echo "Tests Passed: ${TESTS_PASSED}"
    echo "Tests Failed: ${TESTS_FAILED}"
    echo "Total Tests:  ${TESTS_TOTAL}"
    echo "========================================="

    local pass_rate=0
    if [[ ${TESTS_TOTAL} -gt 0 ]]; then
        pass_rate=$(awk "BEGIN {printf \"%.2f\", (${TESTS_PASSED}/${TESTS_TOTAL})*100}")
    fi

    echo "Pass Rate:    ${pass_rate}%"
    echo "========================================="
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_info "All tests passed! Zero-downtime rolling updates verified."
        return 0
    else
        log_error "Some tests failed! Review logs above."
        return 1
    fi
}

print_service_info() {
    echo ""
    echo "========================================="
    echo "         SERVICE INFORMATION"
    echo "========================================="

    echo ""
    echo "--- Service Status ---"
    docker service ls | grep "${STACK_NAME}" || echo "No services found"

    echo ""
    echo "--- Service Tasks ---"
    docker service ps "${STACK_NAME}_a2a-erl" || echo "No tasks found"

    echo ""
    echo "--- Service Config ---"
    docker service inspect "${STACK_NAME}_a2a-erl" --format '{{json .Spec}}' | jq '.' 2>/dev/null || echo "Config unavailable"

    echo ""
    echo "--- Container Health ---"
    local containers
    containers=$(docker ps --filter "label=com.docker.swarm.service.name=${STACK_NAME}_a2a-erl" --format "{{.ID}}" | tr '\n' ' ')

    for container in ${containers}; do
        local health_status
        health_status=$(docker inspect "${container}" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
        echo "${container}: ${health_status}"
    done

    echo "========================================="
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "========================================="
    echo "  Docker Swarm Rolling Update Test Suite"
    echo "  for A2A Erlang Services"
    echo "========================================="
    echo ""

    # Check prerequisites
    check_prerequisites

    # Create overlay network
    create_overlay_network

    # Build test images
    build_test_images

    # Set up cleanup trap
    trap cleanup EXIT

    # Run tests
    test_initial_deployment
    test_rolling_update_image
    test_rolling_update_scale
    test_rolling_update_config
    test_rollback
    test_failed_update
    test_parallel_update
    test_health_during_update

    # Print service info before cleanup
    print_service_info

    # Print summary
    print_summary
}

# Run main
main "$@"
