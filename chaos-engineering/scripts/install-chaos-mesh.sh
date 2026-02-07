#!/bin/bash
# =============================================================================
# Chaos Mesh Installation Script for A2A Project
# =============================================================================
# This script installs Chaos Mesh on a Kubernetes cluster for chaos engineering
# testing of A2A protocol components
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.6.3}"
NAMESPACE="${CHAOS_MESH_NAMESPACE:-chaos-mesh}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-a2a-chaos}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi

    if ! command -v kind &> /dev/null; then
        log_warning "kind not found - will install if needed for local cluster"
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Installing missing tools..."
        install_tools "${missing_tools[@]}"
    fi

    log_success "All prerequisites checked"
}

install_tools() {
    local tools=("$@")

    for tool in "${tools[@]}"; do
        case "$tool" in
            kubectl)
                log_info "Installing kubectl..."
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                chmod +x kubectl
                sudo mv kubectl /usr/local/bin/ || mv kubectl "$HOME/.local/bin/"
                ;;
            helm)
                log_info "Installing helm..."
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                ;;
        esac
    done
}

setup_kind_cluster() {
    log_info "Setting up kind cluster for chaos testing..."

    if ! command -v kind &> /dev/null; then
        log_info "Installing kind..."
        curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64"
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind || mv ./kind "$HOME/.local/bin/kind"
    fi

    # Check if cluster already exists
    if kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_info "Kind cluster '${KIND_CLUSTER_NAME}' already exists"
        return 0
    fi

    # Create kind cluster configuration
    cat <<EOF > /tmp/kind-chaos-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  - containerPort: 30443
    hostPort: 30443
    protocol: TCP
- role: worker
- role: worker
EOF

    log_info "Creating kind cluster '${KIND_CLUSTER_NAME}'..."
    kind create cluster --name "${KIND_CLUSTER_NAME}" --config /tmp/kind-chaos-config.yaml

    kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"
    log_success "Kind cluster created successfully"
}

install_chaos_mesh() {
    log_info "Installing Chaos Mesh version ${CHAOS_MESH_VERSION}..."

    # Add Chaos Mesh Helm repository
    log_info "Adding Chaos Mesh Helm repository..."
    helm repo add chaos-mesh https://charts.chaos-mesh.org
    helm repo update

    # Create namespace
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Install Chaos Mesh
    log_info "Installing Chaos Mesh with Helm..."
    helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
        --namespace="${NAMESPACE}" \
        --version "${CHAOS_MESH_VERSION}" \
        --set chaosDaemon.runtime=containerd \
        --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
        --set dashboard.create=true \
        --set dashboard.securityMode=false \
        --wait \
        --timeout 10m

    log_success "Chaos Mesh installed successfully"
}

verify_installation() {
    log_info "Verifying Chaos Mesh installation..."

    # Wait for pods to be ready
    log_info "Waiting for Chaos Mesh pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n "${NAMESPACE}" --timeout=300s

    # Check CRDs
    log_info "Verifying Chaos Mesh CRDs..."
    local crds=(
        "podchaos.chaos-mesh.org"
        "networkchaos.chaos-mesh.org"
        "iochaos.chaos-mesh.org"
        "stresschaos.chaos-mesh.org"
        "timechaos.chaos-mesh.org"
        "httpchaos.chaos-mesh.org"
        "dnschaos.chaos-mesh.org"
        "workflows.chaos-mesh.org"
    )

    for crd in "${crds[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            log_success "CRD $crd exists"
        else
            log_error "CRD $crd not found"
            return 1
        fi
    done

    log_success "Chaos Mesh installation verified"
}

setup_dashboard() {
    log_info "Setting up Chaos Mesh Dashboard access..."

    # Get dashboard service
    kubectl get svc -n "${NAMESPACE}" chaos-dashboard

    log_info "To access the Chaos Dashboard, run:"
    echo -e "${GREEN}kubectl port-forward -n ${NAMESPACE} svc/chaos-dashboard 2333:2333${NC}"
    echo -e "${GREEN}Then open http://localhost:2333 in your browser${NC}"
}

deploy_test_workloads() {
    log_info "Deploying test workloads for chaos experiments..."

    # Create test namespace
    kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -

    # Deploy sample A2A components for testing
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: a2a-agent-test
  namespace: default
  labels:
    app: a2a-agent
spec:
  replicas: 3
  selector:
    matchLabels:
      app: a2a-agent
  template:
    metadata:
      labels:
        app: a2a-agent
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
          name: http
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: a2a-agent-svc
  namespace: default
spec:
  selector:
    app: a2a-agent
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: craftplan-test
  namespace: default
  labels:
    app: craftplan
spec:
  replicas: 2
  selector:
    matchLabels:
      app: craftplan
  template:
    metadata:
      labels:
        app: craftplan
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elrmcp-bridge-test
  namespace: default
  labels:
    app: elrmcp-bridge
spec:
  replicas: 2
  selector:
    matchLabels:
      app: elrmcp-bridge
  template:
    metadata:
      labels:
        app: elrmcp-bridge
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
EOF

    log_info "Waiting for test deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/a2a-agent-test -n default
    kubectl wait --for=condition=available --timeout=300s deployment/craftplan-test -n default
    kubectl wait --for=condition=available --timeout=300s deployment/elrmcp-bridge-test -n default

    log_success "Test workloads deployed successfully"
}

print_summary() {
    echo ""
    echo "================================================================================"
    log_success "Chaos Mesh Installation Complete!"
    echo "================================================================================"
    echo ""
    echo "Chaos Mesh Version: ${CHAOS_MESH_VERSION}"
    echo "Namespace: ${NAMESPACE}"
    echo "Cluster: ${KIND_CLUSTER_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Access the dashboard:"
    echo "   kubectl port-forward -n ${NAMESPACE} svc/chaos-dashboard 2333:2333"
    echo ""
    echo "2. Run chaos experiments:"
    echo "   cd /home/user/A2A/chaos-engineering"
    echo "   ./scripts/run-chaos-tests.sh"
    echo ""
    echo "3. View chaos experiment status:"
    echo "   kubectl get podchaos,networkchaos,stresschaos -n default"
    echo ""
    echo "4. Clean up:"
    echo "   kind delete cluster --name ${KIND_CLUSTER_NAME}"
    echo "================================================================================"
}

main() {
    log_info "Starting Chaos Mesh installation for A2A Project..."
    echo ""

    check_prerequisites
    setup_kind_cluster
    install_chaos_mesh
    verify_installation
    setup_dashboard
    deploy_test_workloads
    print_summary
}

# Run main function
main "$@"
