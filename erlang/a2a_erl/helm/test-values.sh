#!/bin/bash
# Helm Values Override Test Script for a2a-erl
# Tests default values, custom values.yaml, --set flags, nested values, and validation

set -e

# Chart directory
CHART_DIR="/Users/sac/A2A/erlang/a2a_erl/helm/a2a-erl"
TEMP_DIR="/tmp/helm-test-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++)) 2>/dev/null || true
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++)) 2>/dev/null || true
}

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"
cp -r "$CHART_DIR" "$TEMP_DIR/a2a-erl"
TEST_CHART="$TEMP_DIR/a2a-erl"

echo "========================================"
echo "A2A Erlang Helm Values Override Tests"
echo "========================================"
echo ""

# Test 1: Default values
info "Test 1: Default values"
if timeout 15 helm template test-release "$TEST_CHART" 2>&1 | grep -q "replicas: 1"; then
    pass "Default replicaCount is 1"
else
    fail "Default replicaCount should be 1"
fi

if timeout 15 helm template test-release "$TEST_CHART" 2>&1 | grep -q 'image: "a2a-erl:0.1.0"'; then
    pass "Default image repository and tag"
else
    fail "Default image should be a2a-erl:0.1.0"
fi

if timeout 15 helm template test-release "$TEST_CHART" 2>&1 | grep -q "port: 8080"; then
    pass "Default service port is 8080"
else
    fail "Default service port"
fi

if timeout 15 helm template test-release "$TEST_CHART" 2>&1 | grep -q "+S 4:4"; then
    pass "Default Erlang SMP is 4:4"
else
    fail "Default Erlang SMP"
fi

if timeout 15 helm template test-release "$TEST_CHART" 2>&1 | grep -q "cpu: 2000m"; then
    pass "Default resource limit CPU is 2000m"
else
    fail "Default CPU limit"
fi

if timeout 15 helm template test-release "$TEST_CHART" 2>&1 | grep -q "memory: 2Gi"; then
    pass "Default resource limit memory is 2Gi"
else
    fail "Default memory limit"
fi

# Test 2: Custom values file
info "Test 2: Custom values.yaml file"
cat > "$TEMP_DIR/custom.yaml" << 'EOF'
replicaCount: 3
image:
  repository: custom-repo
  tag: "2.0.0"
service:
  type: LoadBalancer
  port: 9090
resources:
  limits:
    cpu: 4000m
    memory: 4Gi
erlang:
  smp: "8:8"
  maxPorts: 131072
  nodeName: custom_node
app:
  logLevel: debug
EOF

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "replicas: 3"; then
    pass "Custom replicaCount override (3)"
else
    fail "Custom replicaCount"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q 'image: "custom-repo:2.0.0"'; then
    pass "Custom image repository and tag override"
else
    fail "Custom image override"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "type: LoadBalancer"; then
    pass "Custom service type override"
else
    fail "Custom service type"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "cpu: 4000m"; then
    pass "Custom resource CPU override"
else
    fail "Custom CPU override"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "memory: 4Gi"; then
    pass "Custom resource memory override"
else
    fail "Custom memory override"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "+S 8:8"; then
    pass "Custom Erlang SMP override"
else
    fail "Custom Erlang SMP"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "+Q 131072"; then
    pass "Custom Erlang maxPorts override"
else
    fail "Custom Erlang maxPorts"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "value: custom_node"; then
    pass "Custom Erlang nodeName override"
else
    fail "Custom Erlang nodeName"
fi

if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/custom.yaml" 2>&1 | grep -q "logger_level, debug"; then
    pass "Custom logLevel override"
else
    fail "Custom logLevel"
fi

# Test 3: --set flags
info "Test 3: --set flag overrides"
if timeout 15 helm template test-release "$TEST_CHART" --set replicaCount=5 2>&1 | grep -q "replicas: 5"; then
    pass "--set replicaCount=5"
else
    fail "--set replicaCount"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set image.tag=3.0.0 2>&1 | grep -q 'image: "a2a-erl:3.0.0"'; then
    pass "--set image.tag=3.0.0"
else
    fail "--set image.tag"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set app.port=8888 2>&1 | grep -q "containerPort: 8888"; then
    pass "--set app.port=8888"
else
    fail "--set app.port"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set erlang.nodeName=set_node 2>&1 | grep -q "value: set_node"; then
    pass "--set erlang.nodeName"
else
    fail "--set erlang.nodeName"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set resources.limits.cpu=8000m 2>&1 | grep -q "cpu: 8000m"; then
    pass "--set resources.limits.cpu"
else
    fail "--set resources.limits.cpu"
fi

# Test 4: Nested values
info "Test 4: Nested values override"
if timeout 15 helm template test-release "$TEST_CHART" --set erlang.smp=16:16 2>&1 | grep -q "+S 16:16"; then
    pass "Nested erlang.smp=16:16"
else
    fail "Nested erlang.smp"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set erlang.maxPorts=262144 2>&1 | grep -q "+Q 262144"; then
    pass "Nested erlang.maxPorts=262144"
else
    fail "Nested erlang.maxPorts"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set persistence.enabled=true --set persistence.data.enabled=true 2>&1 | grep -q "kind: PersistentVolumeClaim"; then
    pass "Nested persistence.data.enabled creates PVC"
else
    fail "Nested persistence.data.enabled"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set persistence.enabled=true --set persistence.data.enabled=true --set persistence.data.size=10Gi 2>&1 | grep -q "storage: 10Gi"; then
    pass "Nested persistence.data.size=10Gi"
else
    fail "Nested persistence.data.size"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set healthCheck.path=/healthz 2>&1 | grep -q "path: /healthz"; then
    pass "Nested healthCheck.path=/healthz"
else
    fail "Nested healthCheck.path"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set healthCheck.timeoutSeconds=15 2>&1 | grep -q "timeoutSeconds: 15"; then
    pass "Nested healthCheck.timeoutSeconds=15"
else
    fail "Nested healthCheck.timeoutSeconds"
fi

# Test 5: Autoscaling
info "Test 5: Autoscaling configuration"
if timeout 15 helm template test-release "$TEST_CHART" --set autoscaling.enabled=true 2>&1 | grep -q "kind: HorizontalPodAutoscaler"; then
    pass "Autoscaling enabled creates HPA"
else
    fail "Autoscaling HPA creation"
fi

# When autoscaling is enabled, replicas should not be in Deployment
OUTPUT=$(timeout 15 helm template test-release "$TEST_CHART" --set autoscaling.enabled=true 2>&1)
if ! echo "$OUTPUT" | grep -A 5 "spec:" | head -10 | grep -q "replicas:"; then
    pass "Autoscaling removes replicas from Deployment"
else
    fail "Autoscaling should remove replicas"
fi

# Test 6: fullnameOverride
info "Test 6: Name overrides"
if timeout 15 helm template test-release "$TEST_CHART" --set fullnameOverride=my-name 2>&1 | grep -q "name: my-name"; then
    pass "fullnameOverride works"
else
    fail "fullnameOverride"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set nameOverride=myapp 2>&1 | grep -q "app.kubernetes.io/name: myapp"; then
    pass "nameOverride works"
else
    fail "nameOverride"
fi

# Test 7: Node selector and tolerations (JSON-style)
info "Test 7: Complex values (nodeSelector, tolerations)"
if timeout 15 helm template test-release "$TEST_CHART" --set nodeSelector.disktype=ssd 2>&1 | grep -q "disktype: ssd"; then
    pass "nodeSelector set"
else
    fail "nodeSelector"
fi

# Test 8: Values validation (schema)
info "Test 8: Values validation"
# Valid service types
for svc_type in "ClusterIP" "NodePort" "LoadBalancer"; do
    if timeout 15 helm template test-release "$TEST_CHART" --set service.type="$svc_type" >/dev/null 2>&1; then
        pass "Valid service type: $svc_type"
    else
        fail "Service type $svc_type rejected"
    fi
done

# Test 9: Combined values file and --set
info "Test 9: Values file + --set combination"
cat > "$TEMP_DIR/base.yaml" << 'EOF'
replicaCount: 2
image:
  tag: "1.5.0"
EOF

OUTPUT=$(timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/base.yaml" --set replicaCount=4 2>&1)
if echo "$OUTPUT" | grep -q "replicas: 4"; then
    pass "--set overrides values file"
else
    fail "Values file + --set"
fi

if echo "$OUTPUT" | grep -q 'image: "a2a-erl:1.5.0"'; then
    pass "Values file provides defaults"
else
    fail "Values file defaults"
fi

# Test 10: Rolling update configuration
info "Test 10: Rolling update configuration"
if timeout 15 helm template test-release "$TEST_CHART" --set rollingUpdate.maxSurge=50% 2>&1 | grep -q "maxSurge: 50%"; then
    pass "rollingUpdate.maxSurge override"
else
    fail "rollingUpdate.maxSurge"
fi

if timeout 15 helm template test-release "$TEST_CHART" --set rollingUpdate.maxUnavailable=1 2>&1 | grep -q "maxUnavailable: 1"; then
    pass "rollingUpdate.maxUnavailable override"
else
    fail "rollingUpdate.maxUnavailable"
fi

# Test 11: Revision history limit
info "Test 11: Revision history limit"
if timeout 15 helm template test-release "$TEST_CHART" --set revisionHistoryLimit=5 2>&1 | grep -q "revisionHistoryLimit: 5"; then
    pass "revisionHistoryLimit override"
else
    fail "revisionHistoryLimit"
fi

# Test 12: Pod annotations
info "Test 12: Pod annotations"
# Use a values file for annotations with special characters (keys with /)
cat > "$TEMP_DIR/annotations.yaml" << 'EOF'
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
EOF
if timeout 15 helm template test-release "$TEST_CHART" -f "$TEMP_DIR/annotations.yaml" 2>&1 | grep -q "prometheus.io/scrape: \"true\""; then
    pass "podAnnotations override"
else
    fail "podAnnotations"
fi

# Test simple --set annotation (without special characters)
if timeout 15 helm template test-release "$TEST_CHART" --set podAnnotations.mykey=myvalue 2>&1 | grep -q "mykey: myvalue"; then
    pass "podAnnotations with --set (simple key)"
else
    fail "podAnnotations with --set"
fi

# Test 13: Secret configuration
info "Test 13: Secret configuration"
if timeout 15 helm template test-release "$TEST_CHART" --set secret.create=false --set secret.existingSecret=my-secret 2>&1 | grep -q "name: my-secret"; then
    pass "secret.existingSecret override"
else
    fail "secret.existingSecret"
fi

# Test 14: Service account
info "Test 14: Service account configuration"
if timeout 15 helm template test-release "$TEST_CHART" --set serviceAccount.create=true 2>&1 | grep -q "kind: ServiceAccount"; then
    pass "serviceAccount.create creates ServiceAccount"
else
    fail "serviceAccount.create"
fi

# Test 15: Persistence with log enabled
info "Test 15: Persistence with log enabled"
if timeout 15 helm template test-release "$TEST_CHART" --set persistence.enabled=true --set persistence.log.enabled=true 2>&1 | grep -q "name:.*-log"; then
    pass "persistence.log.enabled creates log PVC"
else
    fail "persistence.log.enabled"
fi

# Summary
echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
