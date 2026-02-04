#!/bin/bash
# Helm Upgrade/Rollback Test Infrastructure - Kind Cluster Setup
# This script creates a local Kubernetes cluster using Kind for testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CLUSTER_NAME="${CLUSTER_NAME:-a2a-test}"
K8S_VERSION="${K8S_VERSION:-v1.28.0}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kind is installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    if ! command -v kind &> /dev/null; then
        log_error "kind is not installed. Please install it from https://kind.sigs.k8s.io/"
        exit 1
    fi
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install it from https://helm.sh/"
        exit 1
    fi
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it from https://kubernetes.io/"
        exit 1
    fi
    log_info "Prerequisites check passed!"
}

# Check if cluster exists
check_cluster_exists() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster '${CLUSTER_NAME}' already exists"
        return 0
    fi
    return 1
}

# Create kind cluster
create_cluster() {
    log_info "Creating Kind cluster '${CLUSTER_NAME}' with Kubernetes ${K8S_VERSION}..."

    cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:${K8S_VERSION}
  extraPortMappings:
  - containerPort: 30080
    hostPort: 28080
    protocol: TCP
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
EOF

    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=ready pod --all -n kube-system --timeout=300s
    log_info "Cluster '${CLUSTER_NAME}' created successfully!"
}

# Delete kind cluster
delete_cluster() {
    if check_cluster_exists; then
        log_info "Deleting Kind cluster '${CLUSTER_NAME}'..."
        kind delete cluster --name "${CLUSTER_NAME}"
        log_info "Cluster deleted!"
    else
        log_warn "Cluster '${CLUSTER_NAME}' does not exist"
    fi
}

# Get cluster status
cluster_status() {
    if check_cluster_exists; then
        log_info "Cluster '${CLUSTER_NAME}' status:"
        kubectl cluster-info --context kind-"${CLUSTER_NAME}"
        echo ""
        log_info "Nodes:"
        kubectl get nodes -o wide
        echo ""
        log_info "Namespaces:"
        kubectl get namespaces
    else
        log_warn "Cluster '${CLUSTER_NAME}' does not exist"
        return 1
    fi
}

# Main script logic
case "${1:-create}" in
    create)
        check_prerequisites
        if ! check_cluster_exists; then
            create_cluster
        else
            log_info "Using existing cluster '${CLUSTER_NAME}'"
        fi
        ;;
    delete)
        delete_cluster
        ;;
    status)
        cluster_status
        ;;
    recreate)
        delete_cluster
        check_prerequisites
        create_cluster
        ;;
    *)
        echo "Usage: $0 {create|delete|status|recreate}"
        echo ""
        echo "Environment variables:"
        echo "  CLUSTER_NAME - Name of the Kind cluster (default: a2a-test)"
        echo "  K8S_VERSION  - Kubernetes version (default: v1.28.0)"
        exit 1
        ;;
esac
