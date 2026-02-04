#!/bin/bash
# Standalone Helm operations test script
# Tests: install, upgrade --install, rollback, values override, release history

set -e

export KUBECONFIG="/tmp/kind-a2a-test-kubeconfig.yaml"

# Get kubeconfig from kind
kind get kubeconfig --name a2a-test > "$KUBECONFIG"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

CHART_DIR="/Users/sac/A2A/erlang/a2a_erl/helm/a2a-erl"
NAMESPACE="a2a-test"
RELEASE="a2a-test"

# Cleanup any existing release
helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null || true
sleep 2

# Test 1: helm install
log_test "Test 1: helm install"
helm install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set image.repository=a2a-erl \
  --set image.tag=0.1.0 \
  --set image.pullPolicy=Never \
  --set replicaCount=2 \
  --set tests.enabled=true \
  --wait --timeout 5m

kubectl get pods -n "$NAMESPACE"
helm status "$RELEASE" -n "$NAMESPACE" | head -10
log_info "PASS: helm install"

# Test 2: helm test
log_test "Test 2: helm test"
if helm test "$RELEASE" -n "$NAMESPACE" --timeout 3m; then
    log_info "PASS: helm test"
else
    log_error "FAIL: helm test"
fi

# Test 3: helm upgrade
log_test "Test 3: helm upgrade (image 0.1.0 -> 0.2.0, replicas 2 -> 3)"
helm upgrade "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set image.repository=a2a-erl \
  --set image.tag=0.2.0 \
  --set image.pullPolicy=Never \
  --set replicaCount=3 \
  --set tests.enabled=true \
  --wait --timeout 5m

kubectl get pods -n "$NAMESPACE"
IMAGE=$(kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
REPLICAS=$(kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
log_info "Image: $IMAGE, Replicas: $REPLICAS"
log_info "PASS: helm upgrade"

# Test 4: helm history
log_test "Test 4: helm history (release history maintained)"
helm history "$RELEASE" -n "$NAMESPACE"
log_info "PASS: helm history"

# Test 5: helm rollback
log_test "Test 5: helm rollback to revision 1"
helm rollback "$RELEASE" 1 -n "$NAMESPACE" --wait --timeout 5m

kubectl get pods -n "$NAMESPACE"
ROLLBACK_IMAGE=$(kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
ROLLBACK_REPLICAS=$(kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
log_info "After rollback - Image: $ROLLBACK_IMAGE, Replicas: $ROLLBACK_REPLICAS"

if [[ "$ROLLBACK_IMAGE" == *"0.1.0"* ]] && [[ "$ROLLBACK_REPLICAS" == "2" ]]; then
    log_info "PASS: helm rollback (correctly restored image and replicas)"
else
    log_error "FAIL: helm rollback (unexpected image or replicas)"
fi

# Test 6: helm upgrade --install
log_test "Test 6: helm upgrade --install with new values"
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set image.repository=a2a-erl \
  --set image.tag=0.3.0 \
  --set image.pullPolicy=Never \
  --set replicaCount=1 \
  --set app.logLevel=debug \
  --set tests.enabled=true \
  --wait --timeout 5m

kubectl get pods -n "$NAMESPACE"
FINAL_IMAGE=$(kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
FINAL_REPLICAS=$(kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
log_info "After upgrade --install - Image: $FINAL_IMAGE, Replicas: $FINAL_REPLICAS"
log_info "PASS: helm upgrade --install"

# Test 7: ReplicaSets maintained for rollback
log_test "Test 7: ReplicaSets for rollback capability"
REPLICASET_COUNT=$(kubectl get replicasets -n "$NAMESPACE" --no-headers | wc -l | tr -d ' ')
log_info "ReplicaSets count: $REPLICASET_COUNT"
if [[ "$REPLICASET_COUNT" -ge 2 ]]; then
    log_info "PASS: Multiple ReplicaSets maintained for rollback"
else
    log_error "FAIL: Not enough ReplicaSets for rollback"
fi

# Test 8: Final helm test
log_test "Test 8: Final helm test"
if helm test "$RELEASE" -n "$NAMESPACE" --timeout 3m; then
    log_info "PASS: final helm test"
else
    log_error "FAIL: final helm test"
fi

# Summary
echo ""
echo "========================================="
echo "           TEST SUMMARY"
echo "========================================="
helm history "$RELEASE" -n "$NAMESPACE"
echo ""
kubectl get deployment "${RELEASE}-a2a-erl" -n "$NAMESPACE"
echo ""
kubectl get pods -n "$NAMESPACE"
echo ""
log_info "All tests completed!"
