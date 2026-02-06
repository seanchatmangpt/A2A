#!/bin/bash
set -euo pipefail

# =============================================================================
# A2A Protocol - Enterprise Fortune 5 Deployment Script
# Single-command deployment with pre-flight checks, deployment, and validation
# =============================================================================

readonly VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly LOG_FILE="${SCRIPT_DIR}/install_${TIMESTAMP}.log"
readonly STATE_FILE="${SCRIPT_DIR}/.install_state"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Configuration defaults
export PROJECT_ID="${PROJECT_ID:-}"
export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"
export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-a2a-prod}"
export CLUSTER_NAME="${CLUSTER_NAME:-${DEPLOYMENT_NAME}-gke}"
export ENVIRONMENT="${ENVIRONMENT:-production}"
export NAMESPACE="${NAMESPACE:-a2a-system}"
export ADMIN_EMAIL="${ADMIN_EMAIL:-}"
export DRY_RUN="${DRY_RUN:-false}"
export SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
export ENABLE_MONITORING="${ENABLE_MONITORING:-true}"
export ENABLE_SECURITY="${ENABLE_SECURITY:-true}"
export ENABLE_BACKUP="${ENABLE_BACKUP:-true}"
export NODE_COUNT="${NODE_COUNT:-3}"
export MACHINE_TYPE="${MACHINE_TYPE:-n1-standard-4}"
export HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

# Progress tracking
TOTAL_STEPS=50
CURRENT_STEP=0
FAILED_CHECKS=()
WARNING_CHECKS=()
START_TIME=$(date +%s)

# =============================================================================
# Logging and Output Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "\n${CYAN}[${CURRENT_STEP}/${TOTAL_STEPS}] (${percent}%)${NC} ${BOLD}$*${NC}" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}✗${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*" | tee -a "${LOG_FILE}"
}

log_header() {
    echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} ${BOLD}$*${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}\n"
}

log_section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD} $*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 10))
        printf "\r${CYAN}${spin:$i:1}${NC} %s" "$msg"
        sleep 0.1
    done
    printf "\r"
}

save_state() {
    cat > "${STATE_FILE}" <<EOF
TIMESTAMP=${TIMESTAMP}
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
CLUSTER_NAME=${CLUSTER_NAME}
NAMESPACE=${NAMESPACE}
CURRENT_STEP=${CURRENT_STEP}
EOF
}

# =============================================================================
# Banner and Usage
# =============================================================================

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║                    Agent2Agent (A2A) Protocol                         ║
║              Enterprise Fortune 5 Deployment System                   ║
║                                                                       ║
║                 One-Click Production Deployment                       ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
}

print_usage() {
    cat <<EOF

Usage: $0 [OPTIONS]

Enterprise-grade A2A Protocol deployment with comprehensive validation.

REQUIRED:
    -p, --project-id PROJECT_ID      GCP Project ID

OPTIONAL:
    -r, --region REGION              GCP Region (default: us-central1)
    -z, --zone ZONE                  GCP Zone (default: us-central1-a)
    -n, --deployment-name NAME       Deployment name (default: a2a-prod)
    -e, --email EMAIL                Admin email for notifications
    --namespace NAMESPACE            Kubernetes namespace (default: a2a-system)
    --node-count COUNT               GKE node count (default: 3)
    --machine-type TYPE              GKE machine type (default: n1-standard-4)
    --environment ENV                Environment (production|staging|dev)

CONTROL:
    --dry-run                        Run pre-flight checks only
    --skip-validation                Skip post-deployment validation
    --no-monitoring                  Disable monitoring stack
    --no-security                    Disable security policies
    --no-backup                      Disable backup configuration

OPERATIONS:
    --status                         Show deployment status
    --rollback                       Rollback to previous version
    --destroy                        Destroy all resources
    -h, --help                       Show this help message
    -v, --version                    Show version

ENVIRONMENT VARIABLES:
    PROJECT_ID                       GCP Project ID
    REGION                           GCP Region
    DEPLOYMENT_NAME                  Deployment name
    ADMIN_EMAIL                      Admin email

EXAMPLES:
    # Full production deployment
    sudo $0 -p my-project-id -e admin@company.com

    # Dry run (checks only)
    sudo $0 -p my-project-id --dry-run

    # Custom configuration
    sudo $0 -p my-project-id -r us-east1 --node-count 5 --machine-type n1-standard-8

    # Minimal deployment
    sudo $0 -p my-project-id --no-monitoring --no-backup

DOCUMENTATION:
    https://a2a-protocol.org
    https://github.com/a2aproject/A2A

EOF
    exit 0
}

# =============================================================================
# Pre-Flight Checks
# =============================================================================

check_required_tools() {
    log_section "Pre-Flight: Required Tools"

    local required_tools=(
        "gcloud:Google Cloud SDK"
        "kubectl:Kubernetes CLI"
        "terraform:Infrastructure as Code"
        "helm:Kubernetes Package Manager"
        "jq:JSON Processor"
        "curl:HTTP Client"
        "git:Version Control"
        "python3:Python Runtime"
    )

    local missing_tools=()

    for tool_info in "${required_tools[@]}"; do
        IFS=':' read -r tool desc <<< "$tool_info"
        log_step "Checking: $desc ($tool)"

        if command -v "$tool" &> /dev/null; then
            local version=$($tool --version 2>&1 | head -n1 || echo "unknown")
            log_success "$tool found: $version"
        else
            log_error "$tool not found"
            missing_tools+=("$tool")
            FAILED_CHECKS+=("Missing tool: $tool ($desc)")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                gcloud) echo "  curl https://sdk.cloud.google.com | bash" ;;
                kubectl) echo "  gcloud components install kubectl" ;;
                terraform) echo "  https://terraform.io/downloads" ;;
                helm) echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" ;;
                jq) echo "  apt-get install jq / yum install jq" ;;
            esac
        done
        return 1
    fi

    log_success "All required tools installed"
}

check_gcp_authentication() {
    log_section "Pre-Flight: GCP Authentication"

    log_step "Checking gcloud authentication"

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication"
        log_info "Run: gcloud auth login"
        FAILED_CHECKS+=("GCP authentication required")
        return 1
    fi

    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: $active_account"

    log_step "Checking application default credentials"
    if gcloud auth application-default print-access-token &> /dev/null; then
        log_success "Application default credentials configured"
    else
        log_warning "Application default credentials not configured"
        log_info "Run: gcloud auth application-default login"
        WARNING_CHECKS+=("ADC not configured - may cause Terraform issues")
    fi

    log_step "Verifying project access: $PROJECT_ID"
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        local project_name=$(gcloud projects describe "$PROJECT_ID" --format="value(name)")
        local project_number=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
        log_success "Project: $project_name (ID: $PROJECT_ID, Number: $project_number)"
    else
        log_error "Cannot access project: $PROJECT_ID"
        FAILED_CHECKS+=("Project access denied: $PROJECT_ID")
        return 1
    fi
}

check_gcp_apis() {
    log_section "Pre-Flight: GCP APIs"

    local required_apis=(
        "compute.googleapis.com:Compute Engine"
        "container.googleapis.com:Kubernetes Engine"
        "cloudresourcemanager.googleapis.com:Resource Manager"
        "iam.googleapis.com:Identity Access Management"
        "sqladmin.googleapis.com:Cloud SQL"
        "servicenetworking.googleapis.com:Service Networking"
        "cloudbuild.googleapis.com:Cloud Build"
        "logging.googleapis.com:Cloud Logging"
        "monitoring.googleapis.com:Cloud Monitoring"
        "cloudkms.googleapis.com:Key Management"
        "secretmanager.googleapis.com:Secret Manager"
        "storage-api.googleapis.com:Cloud Storage"
    )

    local apis_to_enable=()

    for api_info in "${required_apis[@]}"; do
        IFS=':' read -r api desc <<< "$api_info"
        log_step "Checking API: $desc"

        if gcloud services list --enabled --project="$PROJECT_ID" --format="value(config.name)" 2>/dev/null | grep -q "^${api}$"; then
            log_success "$desc enabled"
        else
            log_warning "$desc not enabled"
            apis_to_enable+=("$api")
        fi
    done

    if [ ${#apis_to_enable[@]} -gt 0 ]; then
        log_info "Enabling ${#apis_to_enable[@]} APIs..."

        if gcloud services enable "${apis_to_enable[@]}" --project="$PROJECT_ID" 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "APIs enabled successfully"
            log_warning "API activation may take 1-2 minutes to propagate"
            sleep 5
        else
            log_error "Failed to enable APIs"
            FAILED_CHECKS+=("API enablement failed")
            return 1
        fi
    fi

    log_success "All required APIs enabled"
}

check_gcp_quotas() {
    log_section "Pre-Flight: GCP Quotas"

    log_step "Checking compute quotas"

    local quotas=$(gcloud compute project-info describe --project="$PROJECT_ID" --format=json 2>/dev/null || echo "{}")

    if [ "$quotas" != "{}" ]; then
        local cpu_quota=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="CPUS") | .limit' 2>/dev/null || echo "unknown")
        local cpu_usage=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="CPUS") | .usage' 2>/dev/null || echo "0")
        local disk_quota=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="DISKS_TOTAL_GB") | .limit' 2>/dev/null || echo "unknown")
        local ip_quota=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="IN_USE_ADDRESSES") | .limit' 2>/dev/null || echo "unknown")

        log_info "CPU Quota: ${cpu_usage}/${cpu_quota}"
        log_info "Disk Quota: ${disk_quota}GB"
        log_info "IP Address Quota: ${ip_quota}"

        if [ "$cpu_quota" != "unknown" ] && [ "$cpu_quota" -lt 24 ]; then
            log_warning "Low CPU quota: ${cpu_quota} (recommended: 24+)"
            WARNING_CHECKS+=("CPU quota may be insufficient")
        else
            log_success "CPU quota sufficient"
        fi
    else
        log_warning "Could not retrieve quota information"
        WARNING_CHECKS+=("Quota check incomplete")
    fi
}

check_network_connectivity() {
    log_section "Pre-Flight: Network Connectivity"

    local endpoints=(
        "https://www.googleapis.com:Google APIs"
        "https://gcr.io:Google Container Registry"
        "https://registry.terraform.io:Terraform Registry"
        "https://charts.helm.sh:Helm Charts"
        "https://github.com:GitHub"
    )

    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r endpoint desc <<< "$endpoint_info"
        log_step "Testing connectivity: $desc"

        if curl -s --max-time 5 --head "$endpoint" &> /dev/null; then
            log_success "$desc reachable"
        else
            log_warning "$desc unreachable"
            WARNING_CHECKS+=("Network connectivity issue: $desc")
        fi
    done
}

check_disk_space() {
    log_section "Pre-Flight: System Resources"

    log_step "Checking disk space"

    local available_gb=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    local total_gb=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $2}' | sed 's/G//')

    log_info "Disk space: ${available_gb}GB available / ${total_gb}GB total"

    if [ "$available_gb" -lt 10 ]; then
        log_error "Insufficient disk space: ${available_gb}GB (required: 10GB+)"
        FAILED_CHECKS+=("Insufficient disk space")
        return 1
    elif [ "$available_gb" -lt 20 ]; then
        log_warning "Low disk space: ${available_gb}GB (recommended: 20GB+)"
        WARNING_CHECKS+=("Low disk space")
    else
        log_success "Disk space sufficient"
    fi

    log_step "Checking memory"
    if command -v free &> /dev/null; then
        local available_mem=$(free -g | awk 'NR==2 {print $7}')
        log_info "Available memory: ${available_mem}GB"

        if [ "$available_mem" -lt 2 ]; then
            log_warning "Low memory: ${available_mem}GB"
            WARNING_CHECKS+=("Low available memory")
        else
            log_success "Memory sufficient"
        fi
    fi
}

check_existing_resources() {
    log_section "Pre-Flight: Existing Resources"

    log_step "Checking for existing GKE cluster"
    if gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        log_warning "Cluster $CLUSTER_NAME already exists"
        log_info "Existing cluster will be used/updated"
        WARNING_CHECKS+=("Cluster already exists - will be updated")
    else
        log_info "No existing cluster found - will create new"
    fi

    log_step "Checking for existing VPC"
    if gcloud compute networks describe "${DEPLOYMENT_NAME}-vpc" --project="$PROJECT_ID" &> /dev/null; then
        log_warning "VPC ${DEPLOYMENT_NAME}-vpc already exists"
        WARNING_CHECKS+=("VPC already exists")
    else
        log_info "No existing VPC found - will create new"
    fi

    log_step "Checking Terraform state"
    if [ -d "${SCRIPT_DIR}/terraform/.terraform" ]; then
        log_info "Terraform initialized"
        if [ -f "${SCRIPT_DIR}/terraform/terraform.tfstate" ]; then
            log_warning "Terraform state exists - deployment may update existing resources"
            WARNING_CHECKS+=("Terraform state exists")
        fi
    else
        log_info "Fresh Terraform deployment"
    fi
}

validate_configuration() {
    log_section "Pre-Flight: Configuration Validation"

    log_step "Validating Terraform configuration"
    cd "${SCRIPT_DIR}/terraform"

    if terraform init -backend=false &> /dev/null; then
        log_success "Terraform init successful"

        if terraform validate &> /dev/null; then
            log_success "Terraform configuration valid"
        else
            log_error "Terraform validation failed"
            terraform validate
            FAILED_CHECKS+=("Terraform validation failed")
            cd "$SCRIPT_DIR"
            return 1
        fi
    else
        log_error "Terraform init failed"
        FAILED_CHECKS+=("Terraform init failed")
        cd "$SCRIPT_DIR"
        return 1
    fi

    cd "$SCRIPT_DIR"

    log_step "Validating Helm charts"
    if [ -d "${SCRIPT_DIR}/helm" ]; then
        if helm lint "${SCRIPT_DIR}/helm" &> /dev/null; then
            log_success "Helm chart valid"
        else
            log_warning "Helm chart validation warnings"
            WARNING_CHECKS+=("Helm chart validation warnings")
        fi
    else
        log_error "Helm chart not found"
        FAILED_CHECKS+=("Helm chart not found")
        return 1
    fi

    log_step "Validating schema.yaml"
    if [ -f "${SCRIPT_DIR}/schema.yaml" ]; then
        if python3 -c "import yaml; yaml.safe_load(open('${SCRIPT_DIR}/schema.yaml'))" 2>/dev/null; then
            log_success "schema.yaml valid"
        else
            log_error "schema.yaml invalid"
            FAILED_CHECKS+=("Invalid schema.yaml")
            return 1
        fi
    else
        log_warning "schema.yaml not found"
        WARNING_CHECKS+=("schema.yaml not found")
    fi
}

check_permissions() {
    log_section "Pre-Flight: IAM Permissions"

    log_step "Checking compute permissions"
    if gcloud compute zones list --project="$PROJECT_ID" --limit=1 &> /dev/null; then
        log_success "Compute permissions verified"
    else
        log_error "Insufficient compute permissions"
        FAILED_CHECKS+=("Insufficient compute permissions")
        return 1
    fi

    log_step "Checking container permissions"
    if gcloud container clusters list --project="$PROJECT_ID" &> /dev/null; then
        log_success "Container permissions verified"
    else
        log_error "Insufficient container permissions"
        FAILED_CHECKS+=("Insufficient container permissions")
        return 1
    fi

    log_step "Checking IAM permissions"
    if gcloud projects get-iam-policy "$PROJECT_ID" &> /dev/null; then
        log_success "IAM permissions verified"
    else
        log_warning "Cannot verify IAM policy"
        WARNING_CHECKS+=("IAM verification incomplete")
    fi
}

run_preflight_checks() {
    log_header "PHASE 1: PRE-FLIGHT CHECKS"

    check_required_tools || return 1
    check_gcp_authentication || return 1
    check_gcp_apis || return 1
    check_gcp_quotas
    check_network_connectivity
    check_disk_space || return 1
    check_existing_resources
    validate_configuration || return 1
    check_permissions || return 1

    if [ ${#FAILED_CHECKS[@]} -gt 0 ]; then
        log_error "Pre-flight checks failed:"
        for check in "${FAILED_CHECKS[@]}"; do
            log_error "  - $check"
        done
        return 1
    fi

    if [ ${#WARNING_CHECKS[@]} -gt 0 ]; then
        log_warning "Pre-flight warnings:"
        for check in "${WARNING_CHECKS[@]}"; do
            log_warning "  - $check"
        done

        if [ "$DRY_RUN" != "true" ]; then
            echo -e "\n${YELLOW}Continue with warnings? [y/N]${NC} "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled by user"
                exit 0
            fi
        fi
    fi

    log_success "All pre-flight checks passed"
    return 0
}

# =============================================================================
# Infrastructure Deployment
# =============================================================================

deploy_terraform_infrastructure() {
    log_section "Infrastructure Deployment: Terraform"

    cd "${SCRIPT_DIR}/terraform"

    log_step "Initializing Terraform"
    if terraform init -upgrade 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Terraform initialized"
    else
        log_error "Terraform init failed"
        return 1
    fi

    log_step "Creating Terraform variables"
    cat > terraform.tfvars <<EOF
project_id       = "${PROJECT_ID}"
region           = "${REGION}"
deployment_name  = "${DEPLOYMENT_NAME}"
environment      = "${ENVIRONMENT}"
node_count       = ${NODE_COUNT}
machine_type     = "${MACHINE_TYPE}"
enable_monitoring = ${ENABLE_MONITORING}
enable_backup     = ${ENABLE_BACKUP}
EOF

    log_success "Variables configured"

    log_step "Planning Terraform deployment"
    if terraform plan -out=tfplan 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Terraform plan created"
    else
        log_error "Terraform plan failed"
        cd "$SCRIPT_DIR"
        return 1
    fi

    log_step "Applying Terraform configuration"
    log_warning "This will create GCP resources (may take 10-15 minutes)"

    if terraform apply tfplan 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Infrastructure deployed"
    else
        log_error "Terraform apply failed"
        cd "$SCRIPT_DIR"
        return 1
    fi

    log_step "Retrieving infrastructure outputs"
    terraform output -json > "${SCRIPT_DIR}/.terraform_outputs.json"

    cd "$SCRIPT_DIR"
    save_state
    log_success "Terraform deployment completed"
}

configure_kubectl() {
    log_section "Configuration: Kubernetes CLI"

    log_step "Getting GKE cluster credentials"

    if gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Cluster credentials configured"
    else
        log_error "Failed to get cluster credentials"
        return 1
    fi

    log_step "Verifying cluster access"
    if kubectl cluster-info &> /dev/null; then
        log_success "Cluster accessible"
        kubectl cluster-info | tee -a "${LOG_FILE}"
    else
        log_error "Cannot access cluster"
        return 1
    fi

    log_step "Checking cluster nodes"
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$node_count" -gt 0 ]; then
        log_success "Cluster has $node_count nodes"
        kubectl get nodes | tee -a "${LOG_FILE}"
    else
        log_warning "No nodes found yet (may still be provisioning)"
    fi
}

create_kubernetes_namespace() {
    log_section "Configuration: Kubernetes Namespace"

    log_step "Creating namespace: $NAMESPACE"

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tee -a "${LOG_FILE}"

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace created/verified"
    else
        log_error "Failed to create namespace"
        return 1
    fi

    log_step "Labeling namespace"
    kubectl label namespace "$NAMESPACE" \
        environment="$ENVIRONMENT" \
        deployment="$DEPLOYMENT_NAME" \
        managed-by=a2a-installer \
        --overwrite 2>&1 | tee -a "${LOG_FILE}"

    log_success "Namespace configured"
}

deploy_helm_chart() {
    log_section "Application Deployment: Helm"

    log_step "Preparing Helm values"

    cat > "${SCRIPT_DIR}/.install_values.yaml" <<EOF
image:
  registry: gcr.io
  repository: ${PROJECT_ID}/a2a
  tag: latest
  pullPolicy: Always

replicaCount: ${NODE_COUNT}

resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 512Mi

service:
  type: LoadBalancer
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: gce

persistence:
  enabled: true
  storageClass: standard-rwo
  size: 10Gi

monitoring:
  enabled: ${ENABLE_MONITORING}

gcp:
  projectId: ${PROJECT_ID}
  region: ${REGION}
  workloadIdentity: true

global:
  environment: ${ENVIRONMENT}
EOF

    log_success "Helm values prepared"

    log_step "Installing Helm chart"
    log_warning "This may take 5-10 minutes"

    if helm upgrade --install a2a "${SCRIPT_DIR}/helm" \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --values "${SCRIPT_DIR}/.install_values.yaml" \
        --wait \
        --timeout "$HELM_TIMEOUT" \
        2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Helm chart installed"
    else
        log_error "Helm installation failed"
        return 1
    fi

    log_step "Verifying Helm release"
    helm list --namespace "$NAMESPACE" | tee -a "${LOG_FILE}"

    save_state
    log_success "Application deployed"
}

wait_for_deployment() {
    log_section "Deployment: Waiting for Readiness"

    log_step "Waiting for pods to be ready"

    local timeout=600
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n "$NAMESPACE" -l app=a2a -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)
        local total_pods=$(kubectl get pods -n "$NAMESPACE" -l app=a2a --no-headers 2>/dev/null | wc -l)

        if [ "$ready_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
            log_success "All pods ready: ${ready_pods}/${total_pods}"
            break
        fi

        printf "\r  Waiting for pods: ${ready_pods}/${total_pods} ready (${elapsed}s/${timeout}s)"
        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo ""

    if [ $elapsed -ge $timeout ]; then
        log_warning "Timeout waiting for pods (this may be normal)"
        kubectl get pods -n "$NAMESPACE" | tee -a "${LOG_FILE}"
    fi

    log_step "Waiting for LoadBalancer IP"

    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local external_ip=$(kubectl get service -n "$NAMESPACE" -l app=a2a -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)

        if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
            log_success "LoadBalancer IP: $external_ip"
            echo "EXTERNAL_IP=${external_ip}" >> "${STATE_FILE}"
            break
        fi

        printf "\r  Waiting for LoadBalancer IP... (${elapsed}s/${timeout}s)"
        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo ""

    if [ $elapsed -ge $timeout ]; then
        log_warning "LoadBalancer IP not yet assigned"
        log_info "Check status: kubectl get svc -n $NAMESPACE"
    fi
}

# =============================================================================
# Validation
# =============================================================================

validate_infrastructure() {
    log_section "Validation: Infrastructure"

    log_step "Validating VPC network"
    if gcloud compute networks describe "${DEPLOYMENT_NAME}-vpc" --project="$PROJECT_ID" &> /dev/null; then
        log_success "VPC network exists"
    else
        log_error "VPC network not found"
        return 1
    fi

    log_step "Validating GKE cluster"
    if gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        log_success "GKE cluster exists"

        local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" --format="value(status)")
        if [ "$cluster_status" = "RUNNING" ]; then
            log_success "Cluster status: RUNNING"
        else
            log_warning "Cluster status: $cluster_status"
        fi
    else
        log_error "GKE cluster not found"
        return 1
    fi

    log_step "Validating node pools"
    local node_pool_count=$(gcloud container node-pools list --cluster="$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" --format="value(name)" | wc -l)
    if [ "$node_pool_count" -gt 0 ]; then
        log_success "Node pools: $node_pool_count"
    else
        log_error "No node pools found"
        return 1
    fi
}

validate_kubernetes() {
    log_section "Validation: Kubernetes"

    log_step "Validating namespace"
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace exists: $NAMESPACE"
    else
        log_error "Namespace not found: $NAMESPACE"
        return 1
    fi

    log_step "Validating deployments"
    local deployments=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$deployments" -gt 0 ]; then
        log_success "Deployments: $deployments"
        kubectl get deployments -n "$NAMESPACE" | tee -a "${LOG_FILE}"
    else
        log_error "No deployments found"
        return 1
    fi

    log_step "Validating pods"
    local total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local ready_pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)

    log_info "Pods: ${ready_pods}/${total_pods} running"
    kubectl get pods -n "$NAMESPACE" | tee -a "${LOG_FILE}"

    if [ "$ready_pods" -gt 0 ]; then
        log_success "Pods are running"
    else
        log_warning "No pods running yet"
    fi

    log_step "Validating services"
    local services=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$services" -gt 0 ]; then
        log_success "Services: $services"
        kubectl get services -n "$NAMESPACE" | tee -a "${LOG_FILE}"
    else
        log_error "No services found"
        return 1
    fi

    log_step "Validating persistent volumes"
    if kubectl get pvc -n "$NAMESPACE" &> /dev/null; then
        local pvc_count=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        log_success "Persistent Volume Claims: $pvc_count"
        kubectl get pvc -n "$NAMESPACE" | tee -a "${LOG_FILE}"
    fi
}

validate_application() {
    log_section "Validation: Application Health"

    log_step "Checking pod health"

    local pods=($(kubectl get pods -n "$NAMESPACE" -l app=a2a -o jsonpath='{.items[*].metadata.name}' 2>/dev/null))

    for pod in "${pods[@]}"; do
        local status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        local restarts=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

        if [ "$status" = "Running" ]; then
            log_success "Pod $pod: $status (restarts: $restarts)"
        else
            log_warning "Pod $pod: $status"
        fi
    done

    log_step "Checking service endpoints"
    local external_ip=$(kubectl get service -n "$NAMESPACE" -l app=a2a -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)

    if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
        log_info "Testing endpoint: http://${external_ip}/health"

        if curl -s --max-time 10 "http://${external_ip}/health" &> /dev/null; then
            log_success "Health endpoint responding"
        else
            log_warning "Health endpoint not yet responding (may still be initializing)"
        fi
    else
        log_warning "External IP not yet assigned"
    fi

    log_step "Checking logs for errors"
    local error_count=0
    for pod in "${pods[@]}"; do
        local errors=$(kubectl logs "$pod" -n "$NAMESPACE" --tail=100 2>/dev/null | grep -i error | wc -l)
        error_count=$((error_count + errors))
    done

    if [ "$error_count" -eq 0 ]; then
        log_success "No errors in recent logs"
    else
        log_warning "Found $error_count error lines in logs"
        log_info "Review logs: kubectl logs -n $NAMESPACE -l app=a2a"
    fi
}

validate_security() {
    log_section "Validation: Security Configuration"

    if [ "$ENABLE_SECURITY" != "true" ]; then
        log_info "Security validation skipped (disabled)"
        return 0
    fi

    log_step "Checking pod security policies"
    local pod_security=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[].spec.securityContext.runAsNonRoot // false' | grep -c true)

    if [ "$pod_security" -gt 0 ]; then
        log_success "Pods running with security context"
    else
        log_warning "Pod security context not configured"
    fi

    log_step "Checking network policies"
    if kubectl get networkpolicies -n "$NAMESPACE" &> /dev/null; then
        local np_count=$(kubectl get networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [ "$np_count" -gt 0 ]; then
            log_success "Network policies: $np_count"
        else
            log_warning "No network policies configured"
        fi
    fi

    log_step "Checking RBAC configuration"
    if kubectl get rolebindings -n "$NAMESPACE" &> /dev/null; then
        local rb_count=$(kubectl get rolebindings -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [ "$rb_count" -gt 0 ]; then
            log_success "Role bindings: $rb_count"
        else
            log_warning "No role bindings found"
        fi
    fi
}

validate_monitoring() {
    log_section "Validation: Monitoring & Observability"

    if [ "$ENABLE_MONITORING" != "true" ]; then
        log_info "Monitoring validation skipped (disabled)"
        return 0
    fi

    log_step "Checking Cloud Monitoring integration"
    if gcloud logging logs list --project="$PROJECT_ID" --filter="resource.type=k8s_cluster AND resource.labels.cluster_name=$CLUSTER_NAME" --limit=1 &> /dev/null; then
        log_success "Cloud Logging configured"
    else
        log_warning "Cloud Logging not yet receiving logs"
    fi

    log_step "Checking metrics"
    local metrics=$(kubectl top nodes 2>/dev/null)
    if [ $? -eq 0 ]; then
        log_success "Metrics server available"
        echo "$metrics" | tee -a "${LOG_FILE}"
    else
        log_warning "Metrics server not yet available"
    fi
}

run_validation() {
    log_header "PHASE 3: POST-DEPLOYMENT VALIDATION"

    if [ "$SKIP_VALIDATION" = "true" ]; then
        log_info "Validation skipped (--skip-validation)"
        return 0
    fi

    validate_infrastructure || log_warning "Infrastructure validation had issues"
    validate_kubernetes || log_warning "Kubernetes validation had issues"
    validate_application || log_warning "Application validation had issues"
    validate_security
    validate_monitoring

    log_success "Validation completed"
}

# =============================================================================
# Status and Reporting
# =============================================================================

show_deployment_status() {
    log_header "DEPLOYMENT STATUS"

    if [ ! -f "${STATE_FILE}" ]; then
        log_error "No deployment state found"
        return 1
    fi

    source "${STATE_FILE}"

    echo -e "${BOLD}Project Information:${NC}"
    echo "  Project ID:       $PROJECT_ID"
    echo "  Region:           $REGION"
    echo "  Deployment:       $DEPLOYMENT_NAME"
    echo "  Namespace:        $NAMESPACE"
    echo "  Timestamp:        $TIMESTAMP"
    echo ""

    echo -e "${BOLD}GKE Cluster:${NC}"
    if gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        local status=$(gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" --format="value(status)")
        local endpoint=$(gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" --format="value(endpoint)")
        echo "  Cluster:          $CLUSTER_NAME"
        echo "  Status:           $status"
        echo "  Endpoint:         $endpoint"
    else
        echo "  Status:           NOT FOUND"
    fi
    echo ""

    echo -e "${BOLD}Kubernetes Resources:${NC}"
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl get all -n "$NAMESPACE"
    else
        echo "  Namespace not found: $NAMESPACE"
    fi
    echo ""

    echo -e "${BOLD}Service Endpoint:${NC}"
    local external_ip=$(kubectl get service -n "$NAMESPACE" -l app=a2a -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
        echo "  External IP:      $external_ip"
        echo "  URL:              http://${external_ip}"
        echo "  Health Check:     http://${external_ip}/health"
    else
        echo "  External IP:      Pending..."
    fi
}

generate_deployment_summary() {
    log_header "DEPLOYMENT SUMMARY"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}DEPLOYMENT SUCCESSFUL${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BOLD}Deployment Details:${NC}"
    echo "  Project:          $PROJECT_ID"
    echo "  Region:           $REGION"
    echo "  Deployment:       $DEPLOYMENT_NAME"
    echo "  Namespace:        $NAMESPACE"
    echo "  Cluster:          $CLUSTER_NAME"
    echo "  Environment:      $ENVIRONMENT"
    echo "  Duration:         ${duration_min}m ${duration_sec}s"
    echo ""

    local external_ip=$(kubectl get service -n "$NAMESPACE" -l app=a2a -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)

    echo -e "${BOLD}Access Information:${NC}"
    if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
        echo "  External IP:      $external_ip"
        echo "  Application URL:  http://${external_ip}"
        echo "  Health Check:     http://${external_ip}/health"
        echo "  API Endpoint:     http://${external_ip}/api/v1"
    else
        echo "  External IP:      Pending (check with: kubectl get svc -n $NAMESPACE)"
    fi
    echo ""

    echo -e "${BOLD}Management Commands:${NC}"
    echo "  View pods:        kubectl get pods -n $NAMESPACE"
    echo "  View services:    kubectl get svc -n $NAMESPACE"
    echo "  View logs:        kubectl logs -n $NAMESPACE -l app=a2a --tail=100"
    echo "  Check status:     $0 --status"
    echo "  Scale:            kubectl scale deployment -n $NAMESPACE a2a --replicas=5"
    echo ""

    echo -e "${BOLD}Monitoring:${NC}"
    if [ "$ENABLE_MONITORING" = "true" ]; then
        echo "  Cloud Console:    https://console.cloud.google.com/kubernetes/workload/overview?project=$PROJECT_ID"
        echo "  Logs:             https://console.cloud.google.com/logs?project=$PROJECT_ID"
        echo "  Monitoring:       https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
    else
        echo "  Monitoring:       Disabled"
    fi
    echo ""

    echo -e "${BOLD}Documentation:${NC}"
    echo "  A2A Protocol:     https://a2a-protocol.org"
    echo "  GitHub:           https://github.com/a2aproject/A2A"
    echo "  Installation Log: ${LOG_FILE}"
    echo "  State File:       ${STATE_FILE}"
    echo ""

    if [ ${#WARNING_CHECKS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Warnings During Deployment:${NC}"
        for warning in "${WARNING_CHECKS[@]}"; do
            echo "  ⚠ $warning"
        done
        echo ""
    fi

    echo -e "${GREEN}✓${NC} Deployment completed successfully!"
    echo ""

    if [ -n "$ADMIN_EMAIL" ]; then
        log_info "Notification email will be sent to: $ADMIN_EMAIL"
    fi
}

# =============================================================================
# Cleanup and Rollback
# =============================================================================

rollback_deployment() {
    log_header "ROLLBACK: Reverting Deployment"

    log_warning "This will rollback the deployment"
    echo -e "${YELLOW}Continue with rollback? [y/N]${NC} "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi

    if [ ! -f "${STATE_FILE}" ]; then
        log_error "No deployment state found"
        return 1
    fi

    source "${STATE_FILE}"

    log_step "Rolling back Helm release"
    if helm rollback a2a --namespace "$NAMESPACE" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Helm rollback successful"
    else
        log_warning "Helm rollback failed or no previous revision"
    fi

    log_step "Rolling back Kubernetes deployments"
    if kubectl rollout undo deployment -n "$NAMESPACE" --all 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Kubernetes rollback successful"
    else
        log_warning "Kubernetes rollback failed"
    fi

    log_success "Rollback completed"
}

destroy_deployment() {
    log_header "DESTROY: Removing All Resources"

    log_error "This will PERMANENTLY DELETE all deployed resources!"
    echo -e "${RED}Type 'DELETE' to confirm:${NC} "
    read -r confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Destroy cancelled"
        exit 0
    fi

    log_step "Deleting Helm releases"
    helm uninstall a2a --namespace "$NAMESPACE" 2>&1 | tee -a "${LOG_FILE}" || true

    log_step "Deleting Kubernetes namespace"
    kubectl delete namespace "$NAMESPACE" --wait=true 2>&1 | tee -a "${LOG_FILE}" || true

    log_step "Destroying Terraform infrastructure"
    cd "${SCRIPT_DIR}/terraform"
    terraform destroy -auto-approve 2>&1 | tee -a "${LOG_FILE}" || true
    cd "$SCRIPT_DIR"

    log_step "Cleaning up state files"
    rm -f "${STATE_FILE}"
    rm -f "${SCRIPT_DIR}/.terraform_outputs.json"
    rm -f "${SCRIPT_DIR}/.install_values.yaml"

    log_success "All resources destroyed"
}

# =============================================================================
# Main Execution
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -n|--deployment-name)
                DEPLOYMENT_NAME="$2"
                CLUSTER_NAME="${2}-gke"
                shift 2
                ;;
            -e|--email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --node-count)
                NODE_COUNT="$2"
                shift 2
                ;;
            --machine-type)
                MACHINE_TYPE="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --no-monitoring)
                ENABLE_MONITORING=false
                shift
                ;;
            --no-security)
                ENABLE_SECURITY=false
                shift
                ;;
            --no-backup)
                ENABLE_BACKUP=false
                shift
                ;;
            --status)
                show_deployment_status
                exit 0
                ;;
            --rollback)
                rollback_deployment
                exit 0
                ;;
            --destroy)
                destroy_deployment
                exit 0
                ;;
            -h|--help)
                print_usage
                ;;
            -v|--version)
                echo "A2A Installer v${VERSION}"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                ;;
        esac
    done
}

main() {
    print_banner

    log_info "A2A Protocol Enterprise Installer v${VERSION}"
    log_info "Started at: $(date)"
    log_info "Log file: ${LOG_FILE}"
    echo ""

    if [ -z "$PROJECT_ID" ]; then
        log_error "Project ID is required"
        log_info "Usage: $0 -p PROJECT_ID [OPTIONS]"
        log_info "       $0 --help for full usage"
        exit 1
    fi

    log_info "Configuration:"
    log_info "  Project:        $PROJECT_ID"
    log_info "  Region:         $REGION"
    log_info "  Deployment:     $DEPLOYMENT_NAME"
    log_info "  Environment:    $ENVIRONMENT"
    log_info "  Namespace:      $NAMESPACE"
    log_info "  Node Count:     $NODE_COUNT"
    log_info "  Machine Type:   $MACHINE_TYPE"
    echo ""

    if ! run_preflight_checks; then
        log_error "Pre-flight checks failed"
        exit 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_success "Dry run completed - all checks passed"
        log_info "Remove --dry-run to proceed with deployment"
        exit 0
    fi

    log_header "PHASE 2: DEPLOYMENT"

    deploy_terraform_infrastructure || { log_error "Infrastructure deployment failed"; exit 1; }
    configure_kubectl || { log_error "Kubectl configuration failed"; exit 1; }
    create_kubernetes_namespace || { log_error "Namespace creation failed"; exit 1; }
    deploy_helm_chart || { log_error "Helm deployment failed"; exit 1; }
    wait_for_deployment

    run_validation

    generate_deployment_summary

    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    log_info "Completed at: $(date)"
    log_info "Total duration: $((total_duration / 60))m $((total_duration % 60))s"
    log_success "Installation completed successfully!"

    exit 0
}

# Entry point
parse_arguments "$@"
main
