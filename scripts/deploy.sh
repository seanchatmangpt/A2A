#!/bin/bash

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOYMENT_LOG="${PROJECT_ROOT}/deployment.log"
ROLLBACK_STATE="${PROJECT_ROOT}/.deployment_state"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# GCP Configuration
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
MARKETPLACE_IMAGE="${MARKETPLACE_IMAGE:-}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-a2a-deployment-${TIMESTAMP}}"
CLUSTER_NAME="${CLUSTER_NAME:-a2a-cluster}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-}"

# Rollback tracking
PREVIOUS_DEPLOYMENT=""
PREVIOUS_IMAGE=""
DEPLOYMENT_CREATED=false
CLUSTER_CREATED=false

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${DEPLOYMENT_LOG}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${DEPLOYMENT_LOG}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${DEPLOYMENT_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${DEPLOYMENT_LOG}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${DEPLOYMENT_LOG}"
}

# Save deployment state for rollback
save_state() {
    cat > "${ROLLBACK_STATE}" <<EOF
TIMESTAMP=${TIMESTAMP}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
PREVIOUS_DEPLOYMENT=${PREVIOUS_DEPLOYMENT}
PREVIOUS_IMAGE=${PREVIOUS_IMAGE}
CLUSTER_NAME=${CLUSTER_NAME}
GCP_PROJECT_ID=${GCP_PROJECT_ID}
GCP_REGION=${GCP_REGION}
DEPLOYMENT_CREATED=${DEPLOYMENT_CREATED}
CLUSTER_CREATED=${CLUSTER_CREATED}
EOF
    log_info "Deployment state saved to ${ROLLBACK_STATE}"
}

# Load previous deployment state
load_state() {
    if [[ -f "${ROLLBACK_STATE}" ]]; then
        source "${ROLLBACK_STATE}"
        log_info "Loaded previous deployment state"
        return 0
    fi
    return 1
}

# Display usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Automated GCP Marketplace deployment with pre-flight checks and rollback capability.

OPTIONS:
    -p, --project       GCP Project ID (required)
    -r, --region        GCP Region (default: us-central1)
    -z, --zone          GCP Zone (default: us-central1-a)
    -i, --image         Marketplace image name (required)
    -n, --name          Deployment name (default: a2a-deployment-TIMESTAMP)
    -c, --cluster       GKE cluster name (default: a2a-cluster)
    -s, --service-acct  Service account email
    --rollback          Rollback to previous deployment
    --dry-run           Run pre-flight checks only
    -h, --help          Display this help message

ENVIRONMENT VARIABLES:
    GCP_PROJECT_ID      GCP Project ID
    GCP_REGION          GCP Region
    GCP_ZONE            GCP Zone
    MARKETPLACE_IMAGE   Marketplace image name
    DEPLOYMENT_NAME     Deployment name
    CLUSTER_NAME        GKE cluster name
    SERVICE_ACCOUNT     Service account email

EXAMPLES:
    # Deploy with explicit parameters
    $0 -p my-project -i gcr.io/my-project/a2a:latest

    # Deploy using environment variables
    export GCP_PROJECT_ID=my-project
    export MARKETPLACE_IMAGE=gcr.io/my-project/a2a:latest
    $0

    # Dry run to check prerequisites
    $0 -p my-project -i gcr.io/my-project/a2a:latest --dry-run

    # Rollback to previous deployment
    $0 --rollback

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local dry_run=false
    local rollback=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                GCP_PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                GCP_REGION="$2"
                shift 2
                ;;
            -z|--zone)
                GCP_ZONE="$2"
                shift 2
                ;;
            -i|--image)
                MARKETPLACE_IMAGE="$2"
                shift 2
                ;;
            -n|--name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            -c|--cluster)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -s|--service-acct)
                SERVICE_ACCOUNT="$2"
                shift 2
                ;;
            --rollback)
                rollback=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [[ "${rollback}" == "true" ]]; then
        perform_rollback
        exit 0
    fi

    if [[ "${dry_run}" == "true" ]]; then
        pre_flight_checks
        log_success "Pre-flight checks completed. Ready for deployment."
        exit 0
    fi
}

# Pre-flight checks
pre_flight_checks() {
    log_info "Running pre-flight checks..."

    # Check required tools
    local required_tools=("gcloud" "kubectl" "docker" "jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed"
            return 1
        fi
        log_success "Found ${tool}"
    done

    # Check GCP project ID
    if [[ -z "${GCP_PROJECT_ID}" ]]; then
        log_error "GCP_PROJECT_ID is not set. Use -p flag or set GCP_PROJECT_ID environment variable."
        return 1
    fi
    log_success "GCP Project ID: ${GCP_PROJECT_ID}"

    # Check marketplace image
    if [[ -z "${MARKETPLACE_IMAGE}" ]]; then
        log_error "MARKETPLACE_IMAGE is not set. Use -i flag or set MARKETPLACE_IMAGE environment variable."
        return 1
    fi
    log_success "Marketplace Image: ${MARKETPLACE_IMAGE}"

    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found. Run 'gcloud auth login'"
        return 1
    fi
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: ${active_account}"

    # Verify project access
    if ! gcloud projects describe "${GCP_PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project ${GCP_PROJECT_ID}. Check permissions."
        return 1
    fi
    log_success "Project ${GCP_PROJECT_ID} is accessible"

    # Check required APIs
    local required_apis=(
        "compute.googleapis.com"
        "container.googleapis.com"
        "deploymentmanager.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )

    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --project="${GCP_PROJECT_ID}" --format="value(config.name)" | grep -q "^${api}$"; then
            log_warning "API ${api} is not enabled. Enabling..."
            if ! gcloud services enable "${api}" --project="${GCP_PROJECT_ID}"; then
                log_error "Failed to enable ${api}"
                return 1
            fi
        fi
        log_success "API ${api} is enabled"
    done

    # Check quotas
    log_info "Checking compute quotas..."
    local cpus_available=$(gcloud compute project-info describe --project="${GCP_PROJECT_ID}" --format="json" | jq -r '.quotas[] | select(.metric=="CPUS") | .limit' 2>/dev/null || echo "unknown")
    if [[ "${cpus_available}" != "unknown" ]]; then
        log_success "CPU quota available: ${cpus_available}"
    fi

    # Check disk space
    local available_space=$(df -BG "${PROJECT_ROOT}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ ${available_space} -lt 5 ]]; then
        log_warning "Low disk space: ${available_space}GB available (recommended: 5GB+)"
    else
        log_success "Disk space: ${available_space}GB available"
    fi

    # Verify Docker image exists (if using GCR)
    if [[ "${MARKETPLACE_IMAGE}" == gcr.io/* ]] || [[ "${MARKETPLACE_IMAGE}" == *.gcr.io/* ]]; then
        log_info "Verifying Docker image exists..."
        if gcloud container images describe "${MARKETPLACE_IMAGE}" --project="${GCP_PROJECT_ID}" &> /dev/null; then
            log_success "Docker image ${MARKETPLACE_IMAGE} exists"
        else
            log_error "Docker image ${MARKETPLACE_IMAGE} not found"
            return 1
        fi
    fi

    # Check for existing deployments
    if gcloud deployment-manager deployments describe "${DEPLOYMENT_NAME}" --project="${GCP_PROJECT_ID}" &> /dev/null 2>&1; then
        log_warning "Deployment ${DEPLOYMENT_NAME} already exists"
        PREVIOUS_DEPLOYMENT="${DEPLOYMENT_NAME}"
    fi

    # Check service account
    if [[ -n "${SERVICE_ACCOUNT}" ]]; then
        if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" --project="${GCP_PROJECT_ID}" &> /dev/null; then
            log_error "Service account ${SERVICE_ACCOUNT} not found"
            return 1
        fi
        log_success "Service account ${SERVICE_ACCOUNT} exists"
    fi

    log_success "All pre-flight checks passed"
    return 0
}

# Create GKE cluster if it doesn't exist
ensure_gke_cluster() {
    log_info "Checking for GKE cluster ${CLUSTER_NAME}..."

    if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${GCP_ZONE}" --project="${GCP_PROJECT_ID}" &> /dev/null; then
        log_success "Cluster ${CLUSTER_NAME} already exists"
        return 0
    fi

    log_info "Creating GKE cluster ${CLUSTER_NAME}..."

    local create_cmd="gcloud container clusters create ${CLUSTER_NAME} \
        --project=${GCP_PROJECT_ID} \
        --zone=${GCP_ZONE} \
        --machine-type=n1-standard-4 \
        --num-nodes=3 \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=10 \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-ip-alias \
        --network=default \
        --subnetwork=default \
        --enable-stackdriver-kubernetes \
        --addons=HorizontalPodAutoscaling,HttpLoadBalancing"

    if [[ -n "${SERVICE_ACCOUNT}" ]]; then
        create_cmd+=" --service-account=${SERVICE_ACCOUNT}"
    fi

    if ${create_cmd}; then
        CLUSTER_CREATED=true
        save_state
        log_success "GKE cluster ${CLUSTER_NAME} created successfully"
    else
        log_error "Failed to create GKE cluster"
        return 1
    fi

    # Get cluster credentials
    gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone="${GCP_ZONE}" --project="${GCP_PROJECT_ID}"
    log_success "Cluster credentials configured"
}

# Deploy to GCP Marketplace
deploy_marketplace() {
    log_info "Starting GCP Marketplace deployment..."

    # Set gcloud project
    gcloud config set project "${GCP_PROJECT_ID}"

    # Create deployment configuration
    local config_file="${PROJECT_ROOT}/deployment-config-${TIMESTAMP}.yaml"

    cat > "${config_file}" <<EOF
resources:
- name: ${DEPLOYMENT_NAME}
  type: container.v1.cluster
  properties:
    zone: ${GCP_ZONE}
    cluster:
      name: ${CLUSTER_NAME}
      initialNodeCount: 3
      nodeConfig:
        machineType: n1-standard-4
        oauthScopes:
        - https://www.googleapis.com/auth/cloud-platform
        - https://www.googleapis.com/auth/compute
        - https://www.googleapis.com/auth/devstorage.read_only
        - https://www.googleapis.com/auth/logging.write
        - https://www.googleapis.com/auth/monitoring
      addonsConfig:
        httpLoadBalancing:
          disabled: false
        horizontalPodAutoscaling:
          disabled: false
      network: default
      subnetwork: default

- name: ${DEPLOYMENT_NAME}-deployment
  type: deploymentmanager.v2.deployment
  properties:
    target:
      config:
        content: |
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: a2a-application
            namespace: default
          spec:
            replicas: 3
            selector:
              matchLabels:
                app: a2a
            template:
              metadata:
                labels:
                  app: a2a
              spec:
                containers:
                - name: a2a
                  image: ${MARKETPLACE_IMAGE}
                  ports:
                  - containerPort: 8080
                  resources:
                    requests:
                      cpu: 500m
                      memory: 512Mi
                    limits:
                      cpu: 2000m
                      memory: 2Gi
                  env:
                  - name: DEPLOYMENT_TIMESTAMP
                    value: "${TIMESTAMP}"
                  - name: GCP_PROJECT_ID
                    value: "${GCP_PROJECT_ID}"
          ---
          apiVersion: v1
          kind: Service
          metadata:
            name: a2a-service
            namespace: default
          spec:
            type: LoadBalancer
            selector:
              app: a2a
            ports:
            - protocol: TCP
              port: 80
              targetPort: 8080
EOF

    log_info "Deployment configuration created: ${config_file}"

    # Create the deployment using Deployment Manager
    if gcloud deployment-manager deployments create "${DEPLOYMENT_NAME}" \
        --config="${config_file}" \
        --project="${GCP_PROJECT_ID}" \
        --automatic-rollback-on-error 2>&1 | tee -a "${DEPLOYMENT_LOG}"; then

        DEPLOYMENT_CREATED=true
        save_state
        log_success "Deployment ${DEPLOYMENT_NAME} created successfully"
    else
        log_error "Deployment failed"
        return 1
    fi

    # Deploy to Kubernetes
    log_info "Deploying to Kubernetes cluster..."

    # Get cluster credentials if not already configured
    gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone="${GCP_ZONE}" --project="${GCP_PROJECT_ID}"

    # Create Kubernetes manifests
    local k8s_manifest="${PROJECT_ROOT}/k8s-manifest-${TIMESTAMP}.yaml"

    cat > "${k8s_manifest}" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: a2a-application
  namespace: default
  labels:
    app: a2a
    version: ${TIMESTAMP}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: a2a
  template:
    metadata:
      labels:
        app: a2a
        version: ${TIMESTAMP}
    spec:
      containers:
      - name: a2a
        image: ${MARKETPLACE_IMAGE}
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2000m
            memory: 2Gi
        env:
        - name: DEPLOYMENT_TIMESTAMP
          value: "${TIMESTAMP}"
        - name: GCP_PROJECT_ID
          value: "${GCP_PROJECT_ID}"
        - name: GCP_REGION
          value: "${GCP_REGION}"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: a2a-service
  namespace: default
  labels:
    app: a2a
spec:
  type: LoadBalancer
  selector:
    app: a2a
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
    name: http
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: a2a-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: a2a-application
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF

    log_info "Applying Kubernetes manifests..."
    if kubectl apply -f "${k8s_manifest}"; then
        log_success "Kubernetes resources deployed"
    else
        log_error "Failed to deploy Kubernetes resources"
        return 1
    fi

    # Wait for deployment to be ready
    log_info "Waiting for deployment to be ready..."
    if kubectl rollout status deployment/a2a-application -n default --timeout=10m; then
        log_success "Deployment is ready"
    else
        log_warning "Deployment rollout did not complete within timeout"
    fi

    # Get service endpoint
    log_info "Retrieving service endpoint..."
    local max_attempts=30
    local attempt=0
    local external_ip=""

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        external_ip=$(kubectl get service a2a-service -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "${external_ip}" ]]; then
            break
        fi
        attempt=$((attempt + 1))
        log_info "Waiting for external IP... (${attempt}/${max_attempts})"
        sleep 10
    done

    if [[ -n "${external_ip}" ]]; then
        log_success "Service endpoint: http://${external_ip}"
        echo "EXTERNAL_IP=${external_ip}" >> "${ROLLBACK_STATE}"
    else
        log_warning "Could not retrieve external IP. Check service status with: kubectl get svc a2a-service"
    fi

    # Save deployment manifest for rollback
    cp "${k8s_manifest}" "${PROJECT_ROOT}/.last_deployment.yaml"

    log_success "Deployment completed successfully"
    return 0
}

# Perform health checks
health_checks() {
    log_info "Performing post-deployment health checks..."

    # Check deployment status
    if ! kubectl get deployment a2a-application -n default &> /dev/null; then
        log_error "Deployment not found"
        return 1
    fi

    local ready_replicas=$(kubectl get deployment a2a-application -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas=$(kubectl get deployment a2a-application -n default -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [[ "${ready_replicas}" == "${desired_replicas}" ]] && [[ "${ready_replicas}" -gt 0 ]]; then
        log_success "All replicas are ready (${ready_replicas}/${desired_replicas})"
    else
        log_warning "Not all replicas are ready (${ready_replicas}/${desired_replicas})"
    fi

    # Check pods
    log_info "Checking pod status..."
    kubectl get pods -n default -l app=a2a

    # Check service
    if kubectl get service a2a-service -n default &> /dev/null; then
        log_success "Service is running"
    else
        log_error "Service not found"
        return 1
    fi

    return 0
}

# Rollback to previous deployment
perform_rollback() {
    log_warning "Initiating rollback..."

    if ! load_state; then
        log_error "No previous deployment state found. Cannot rollback."
        return 1
    fi

    log_info "Rolling back deployment: ${DEPLOYMENT_NAME}"

    # Set project
    gcloud config set project "${GCP_PROJECT_ID}"

    # Rollback Kubernetes deployment
    if kubectl get deployment a2a-application -n default &> /dev/null; then
        log_info "Rolling back Kubernetes deployment..."
        if kubectl rollout undo deployment/a2a-application -n default; then
            log_success "Kubernetes deployment rolled back"
        else
            log_error "Failed to rollback Kubernetes deployment"
        fi
    fi

    # Restore previous manifest if exists
    if [[ -f "${PROJECT_ROOT}/.last_deployment.yaml" ]]; then
        log_info "Restoring previous deployment manifest..."
        if kubectl apply -f "${PROJECT_ROOT}/.last_deployment.yaml"; then
            log_success "Previous manifest restored"
        fi
    fi

    # Delete Deployment Manager deployment if it was created
    if [[ "${DEPLOYMENT_CREATED}" == "true" ]] && [[ -n "${DEPLOYMENT_NAME}" ]]; then
        log_info "Deleting Deployment Manager deployment..."
        if gcloud deployment-manager deployments delete "${DEPLOYMENT_NAME}" \
            --project="${GCP_PROJECT_ID}" \
            --quiet 2>&1 | tee -a "${DEPLOYMENT_LOG}"; then
            log_success "Deployment Manager deployment deleted"
        else
            log_warning "Failed to delete Deployment Manager deployment"
        fi
    fi

    # Delete cluster if it was created
    if [[ "${CLUSTER_CREATED}" == "true" ]] && [[ -n "${CLUSTER_NAME}" ]]; then
        log_warning "Cluster ${CLUSTER_NAME} was created during this deployment"
        read -p "Do you want to delete the cluster? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Deleting cluster ${CLUSTER_NAME}..."
            if gcloud container clusters delete "${CLUSTER_NAME}" \
                --zone="${GCP_ZONE}" \
                --project="${GCP_PROJECT_ID}" \
                --quiet; then
                log_success "Cluster deleted"
            else
                log_error "Failed to delete cluster"
            fi
        fi
    fi

    log_success "Rollback completed"
}

# Cleanup on error
cleanup_on_error() {
    local exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed with exit code ${exit_code}"
        log_warning "Run '$0 --rollback' to rollback changes"

        # Save state for potential rollback
        save_state
    fi

    exit ${exit_code}
}

# Main deployment flow
main() {
    log_info "=== GCP Marketplace Deployment Script ==="
    log_info "Timestamp: ${TIMESTAMP}"

    # Parse arguments
    parse_args "$@"

    # Set up error handling
    trap cleanup_on_error EXIT

    # Run pre-flight checks
    if ! pre_flight_checks; then
        log_error "Pre-flight checks failed. Aborting deployment."
        exit 1
    fi

    # Ensure GKE cluster exists
    if ! ensure_gke_cluster; then
        log_error "Failed to ensure GKE cluster. Aborting deployment."
        exit 1
    fi

    # Perform deployment
    if ! deploy_marketplace; then
        log_error "Deployment failed. Attempting rollback..."
        perform_rollback
        exit 1
    fi

    # Run health checks
    if ! health_checks; then
        log_warning "Health checks failed. You may want to investigate."
    fi

    # Display summary
    log_success "=== Deployment Summary ==="
    log_info "Project: ${GCP_PROJECT_ID}"
    log_info "Region: ${GCP_REGION}"
    log_info "Zone: ${GCP_ZONE}"
    log_info "Cluster: ${CLUSTER_NAME}"
    log_info "Deployment: ${DEPLOYMENT_NAME}"
    log_info "Image: ${MARKETPLACE_IMAGE}"
    log_info "Timestamp: ${TIMESTAMP}"
    log_info "Deployment log: ${DEPLOYMENT_LOG}"
    log_info ""
    log_info "To check deployment status:"
    log_info "  kubectl get deployments -n default"
    log_info "  kubectl get pods -n default -l app=a2a"
    log_info "  kubectl get svc a2a-service -n default"
    log_info ""
    log_info "To rollback this deployment:"
    log_info "  $0 --rollback"
    log_info ""
    log_success "Deployment completed successfully!"

    # Remove error trap on success
    trap - EXIT
}

# Run main function
main "$@"
