#!/bin/bash
# =============================================================================
# GCP Deployment Manager One-Click Deployment Script
# A2A Erlang/OTP Application - Complete Infrastructure Deployment
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Variables
# =============================================================================

# Required environment variables
: ${PROJECT_ID:=$(gcloud config get-value project 2>/dev/null)}
: ${DEPLOYMENT_NAME:=a2a-deployment}
: ${REGION:=us-central1}
: ${ZONE:=us-central1-a}

# Application configuration
: ${APP_VERSION:=v0.2.0}
: ${NAMESPACE:=a2a-system}
: ${APP_INSTANCE_NAME:=a2a-erl}
: ${REPLICAS:=3}
: ${MIN_REPLICAS:=2}
: ${MAX_REPLICAS:=10}

# GKE configuration
: ${NODE_COUNT:=3}
: ${MIN_NODE_COUNT:=1}
: ${MAX_NODE_COUNT:=10}
: ${MACHINE_TYPE:=n1-standard-4}
: ${DISK_SIZE_GB:=100}
: ${RELEASE_CHANNEL:=REGULAR}

# Database configuration
: ${DATABASE_VERSION:=POSTGRES_15}
: ${DATABASE_TIER:=db-custom-2-7680}
: ${DATABASE_DISK_SIZE:=100}
: ${DATABASE_AVAILABILITY_TYPE:=REGIONAL}
: ${MAX_DATABASE_CONNECTIONS:=100}

# Storage configuration
: ${DATA_STORAGE_SIZE:=10Gi}
: ${LOG_STORAGE_SIZE:=5Gi}
: ${STORAGE_CLASS:=pd-ssd}

# Resource limits
: ${CPU_REQUEST:=250m}
: ${CPU_LIMIT:=1000m}
: ${MEMORY_REQUEST:=256Mi}
: ${MEMORY_LIMIT:=1Gi}

# Networking
: ${SERVICE_TYPE:=LoadBalancer}
: ${ENABLE_CDN:=true}
: ${ENABLE_IAP:=false}
: ${SSL_DOMAINS:=[]}

# Security
: ${ERLANG_COOKIE:=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)}
: ${SERVICE_ACCOUNT_NAME:=a2a-service-account}

# Image configuration
: ${IMAGE_REGISTRY:=gcr.io}
: ${IMAGE_REPOSITORY:=${PROJECT_ID}/a2a-erl}
: ${IMAGE_TAG:=latest}
: ${IMAGE:=${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG}}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi

    # Check project ID
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID is not set. Please set it or configure gcloud default project."
        exit 1
    fi

    log_success "All prerequisites met"
}

enable_apis() {
    log_info "Enabling required GCP APIs..."

    local apis=(
        "compute.googleapis.com"
        "container.googleapis.com"
        "deploymentmanager.googleapis.com"
        "sqladmin.googleapis.com"
        "servicenetworking.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "storage-api.googleapis.com"
        "cloudkms.googleapis.com"
        "secretmanager.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" \
            --project="${PROJECT_ID}" \
            --quiet || log_warn "Failed to enable ${api}, it may already be enabled"
    done

    log_success "APIs enabled"
}

create_deployment_config() {
    log_info "Creating deployment configuration..."

    cat > /tmp/a2a-config.yaml <<EOF
imports:
- path: deployer.yaml

resources:
- name: ${DEPLOYMENT_NAME}
  type: deployer.yaml
  properties:
    # Basic configuration
    name: ${APP_INSTANCE_NAME}
    namespace: ${NAMESPACE}
    version: ${APP_VERSION}
    region: ${REGION}
    zone: ${ZONE}

    # Image configuration
    image: ${IMAGE}

    # Replica configuration
    replicas: ${REPLICAS}
    minReplicas: ${MIN_REPLICAS}
    maxReplicas: ${MAX_REPLICAS}

    # GKE configuration
    nodeCount: ${NODE_COUNT}
    minNodeCount: ${MIN_NODE_COUNT}
    maxNodeCount: ${MAX_NODE_COUNT}
    machineType: ${MACHINE_TYPE}
    diskSizeGb: ${DISK_SIZE_GB}
    releaseChannel: ${RELEASE_CHANNEL}

    # Database configuration
    databaseVersion: ${DATABASE_VERSION}
    databaseTier: ${DATABASE_TIER}
    databaseDiskSize: ${DATABASE_DISK_SIZE}
    databaseAvailabilityType: ${DATABASE_AVAILABILITY_TYPE}
    maxDatabaseConnections: "${MAX_DATABASE_CONNECTIONS}"

    # Storage configuration
    dataStorageSize: ${DATA_STORAGE_SIZE}
    logStorageSize: ${LOG_STORAGE_SIZE}
    storageClass: ${STORAGE_CLASS}

    # Resource limits
    cpuRequest: ${CPU_REQUEST}
    cpuLimit: ${CPU_LIMIT}
    memoryRequest: ${MEMORY_REQUEST}
    memoryLimit: ${MEMORY_LIMIT}

    # Networking
    serviceType: ${SERVICE_TYPE}
    enableCdn: ${ENABLE_CDN}
    enableIap: ${ENABLE_IAP}
    sslDomains: ${SSL_DOMAINS}

    # Security
    erlangCookie: ${ERLANG_COOKIE}
    serviceAccountName: ${SERVICE_ACCOUNT_NAME}
EOF

    log_success "Deployment configuration created at /tmp/a2a-config.yaml"
}

build_and_push_image() {
    log_info "Building and pushing Docker image..."

    # Check if Dockerfile exists
    if [[ ! -f "Dockerfile" ]]; then
        log_error "Dockerfile not found in current directory"
        exit 1
    fi

    # Configure Docker to use gcloud as credential helper
    gcloud auth configure-docker --quiet

    # Build the image
    log_info "Building image ${IMAGE}..."
    docker build -t "${IMAGE}" .

    # Push to GCR
    log_info "Pushing image to ${IMAGE_REGISTRY}..."
    docker push "${IMAGE}"

    log_success "Image built and pushed successfully"
}

deploy_with_deployment_manager() {
    log_info "Deploying with GCP Deployment Manager..."

    local config_file="/tmp/a2a-config.yaml"
    local deployer_file="$(dirname "$0")/deployer.yaml"

    # Check if deployer.yaml exists
    if [[ ! -f "${deployer_file}" ]]; then
        log_error "deployer.yaml not found at ${deployer_file}"
        exit 1
    fi

    # Copy files to temp directory
    cp "${deployer_file}" /tmp/

    # Check if deployment already exists
    if gcloud deployment-manager deployments describe "${DEPLOYMENT_NAME}" \
        --project="${PROJECT_ID}" &> /dev/null; then
        log_warn "Deployment ${DEPLOYMENT_NAME} already exists. Updating..."

        gcloud deployment-manager deployments update "${DEPLOYMENT_NAME}" \
            --config="${config_file}" \
            --project="${PROJECT_ID}" \
            --preview || true

        log_info "Previewing changes. Continue with update? (yes/no)"
        read -r response
        if [[ "${response}" == "yes" ]]; then
            gcloud deployment-manager deployments update "${DEPLOYMENT_NAME}" \
                --config="${config_file}" \
                --project="${PROJECT_ID}"
        else
            log_warn "Update cancelled by user"
            exit 0
        fi
    else
        log_info "Creating new deployment ${DEPLOYMENT_NAME}..."
        gcloud deployment-manager deployments create "${DEPLOYMENT_NAME}" \
            --config="${config_file}" \
            --project="${PROJECT_ID}"
    fi

    log_success "Deployment Manager deployment completed"
}

get_gke_credentials() {
    log_info "Getting GKE cluster credentials..."

    local cluster_name="${DEPLOYMENT_NAME}-cluster"

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    local max_attempts=60
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if gcloud container clusters describe "${cluster_name}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
            break
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for cluster... (${attempt}/${max_attempts})"
        sleep 10
    done

    if [[ ${attempt} -eq ${max_attempts} ]]; then
        log_error "Cluster did not become ready in time"
        exit 1
    fi

    gcloud container clusters get-credentials "${cluster_name}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}"

    log_success "GKE credentials configured"
}

verify_deployment() {
    log_info "Verifying deployment..."

    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=a2a-erl \
        -n "${NAMESPACE}" \
        --timeout=600s || log_warn "Some pods may not be ready yet"

    # Get deployment status
    log_info "Deployment status:"
    kubectl get deployments -n "${NAMESPACE}"

    # Get pod status
    log_info "Pod status:"
    kubectl get pods -n "${NAMESPACE}"

    # Get service status
    log_info "Service status:"
    kubectl get services -n "${NAMESPACE}"

    log_success "Deployment verified"
}

get_access_info() {
    log_info "Gathering access information..."

    echo ""
    echo "=========================================="
    echo "Deployment Information"
    echo "=========================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Deployment Name: ${DEPLOYMENT_NAME}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "Namespace: ${NAMESPACE}"
    echo ""

    # Get Load Balancer IP
    log_info "Getting Load Balancer IP..."
    local lb_ip
    lb_ip=$(kubectl get service a2a-service -n "${NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

    if [[ "${lb_ip}" != "pending" ]]; then
        echo "Service URL: http://${lb_ip}:8080"
        echo "Health Check: http://${lb_ip}:8080/health"
    else
        echo "Service IP is being provisioned. Please wait a few minutes."
        echo "Check with: kubectl get service a2a-service -n ${NAMESPACE}"
    fi

    echo ""
    echo "=========================================="
    echo "Useful Commands"
    echo "=========================================="
    echo "View pods:"
    echo "  kubectl get pods -n ${NAMESPACE}"
    echo ""
    echo "View logs:"
    echo "  kubectl logs -l app=a2a-erl -n ${NAMESPACE} --tail=100"
    echo ""
    echo "Scale deployment:"
    echo "  kubectl scale deployment/${APP_INSTANCE_NAME} --replicas=5 -n ${NAMESPACE}"
    echo ""
    echo "Delete deployment:"
    echo "  gcloud deployment-manager deployments delete ${DEPLOYMENT_NAME} --project=${PROJECT_ID}"
    echo ""
    echo "Get cluster credentials:"
    echo "  gcloud container clusters get-credentials ${DEPLOYMENT_NAME}-cluster --region=${REGION} --project=${PROJECT_ID}"
    echo ""
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up..."

    # Optionally clean up resources
    # gcloud deployment-manager deployments delete "${DEPLOYMENT_NAME}" \
    #     --project="${PROJECT_ID}" \
    #     --quiet || true

    exit 1
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting A2A GCP Deployment Manager One-Click Deployment"
    echo "=========================================="
    echo "Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Deployment Name: ${DEPLOYMENT_NAME}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  Image: ${IMAGE}"
    echo "  Replicas: ${REPLICAS}"
    echo "=========================================="
    echo ""

    # Set error trap
    trap cleanup_on_error ERR

    # Execute deployment steps
    check_prerequisites
    enable_apis

    # Ask if user wants to build and push image
    log_info "Do you want to build and push Docker image? (yes/no)"
    read -r build_response
    if [[ "${build_response}" == "yes" ]]; then
        build_and_push_image
    else
        log_warn "Skipping image build. Make sure image ${IMAGE} exists in the registry."
    fi

    create_deployment_config
    deploy_with_deployment_manager
    get_gke_credentials
    verify_deployment
    get_access_info

    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"
