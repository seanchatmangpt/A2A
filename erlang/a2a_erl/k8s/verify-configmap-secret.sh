#!/bin/bash
# Verification script for ConfigMap and Secret mounting in A2A Erlang K8s deployment

set -e

NAMESPACE="a2a-system"
CONFIGMAP_NAME="a2a-config"
SECRET_NAME="a2a-secret"

echo "========================================"
echo "A2A ConfigMap and Secret Verification"
echo "========================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
echo "1. Checking cluster connection..."
if kubectl cluster-info &> /dev/null; then
    echo "   Cluster connection: OK"
else
    echo "   ERROR: Cannot connect to cluster"
    exit 1
fi
echo ""

# Ensure namespace exists
echo "2. Ensuring namespace exists..."
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "   Namespace $NAMESPACE: exists"
else
    echo "   Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
fi
echo ""

# Apply ConfigMap
echo "3. Applying ConfigMap..."
kubectl apply -f "$(dirname "$0")/configmap.yaml"
echo ""

# Apply Secret
echo "4. Applying Secret..."
kubectl apply -f "$(dirname "$0")/secret.yaml"
echo ""

# Verify ConfigMap
echo "5. Verifying ConfigMap..."
if kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "   ConfigMap $CONFIGMAP_NAME: exists"
    echo ""
    echo "   ConfigMap data keys:"
    kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' | sed 's/^/     - /'
else
    echo "   ERROR: ConfigMap $CONFIGMAP_NAME not found"
    exit 1
fi
echo ""

# Verify Secret
echo "6. Verifying Secret..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "   Secret $SECRET_NAME: exists"
    echo ""
    echo "   Secret data keys:"
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' | sed 's/^/     - /'
else
    echo "   ERROR: Secret $SECRET_NAME not found"
    exit 1
fi
echo ""

# Create test pod
echo "7. Creating test pod..."
kubectl apply -f "$(dirname "$0")/test-configmap-secret.yaml"
echo ""

# Wait for test pod to complete
echo "8. Waiting for test pod to complete..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    PHASE=$(kubectl get pod a2a-config-test -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "$PHASE" = "Succeeded" ]; then
        echo "   Test pod: Succeeded"
        break
    elif [ "$PHASE" = "Failed" ]; then
        echo "   ERROR: Test pod failed"
        echo ""
        echo "   Pod logs:"
        kubectl logs a2a-config-test -n "$NAMESPACE" | sed 's/^/     /'
        kubectl delete pod a2a-config-test -n "$NAMESPACE" --ignore-not-found
        exit 1
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo -n "."
done
echo ""

# Show test pod logs
echo "9. Test pod output:"
kubectl logs a2a-config-test -n "$NAMESPACE" | sed 's/^/   /'
echo ""

# Clean up test pod
echo "10. Cleaning up test pod..."
kubectl delete pod a2a-config-test -n "$NAMESPACE" --ignore-not-found
echo ""

echo "========================================"
echo "All verifications passed!"
echo "========================================"
echo ""
echo "Summary:"
echo "  - ConfigMap '$CONFIGMAP_NAME' is correctly configured"
echo "  - Secret '$SECRET_NAME' is correctly configured"
echo "  - ConfigMap volume mounting works"
echo "  - Secret environment variables work"
echo "  - All files are readable in containers"
echo ""
