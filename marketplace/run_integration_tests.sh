#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging functions
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    command -v python3 >/dev/null 2>&1 || missing_tools+=("python3")
    command -v gcloud >/dev/null 2>&1 || missing_tools+=("gcloud")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Install Python dependencies
install_dependencies() {
    log_info "Installing Python dependencies..."

    if [ ! -f "${SCRIPT_DIR}/requirements-integration.txt" ]; then
        log_warning "requirements-integration.txt not found, creating..."
        cat > "${SCRIPT_DIR}/requirements-integration.txt" <<EOF
requests>=2.31.0
EOF
    fi

    if python3 -m pip install -q -r "${SCRIPT_DIR}/requirements-integration.txt"; then
        log_success "Python dependencies installed"
    else
        log_error "Failed to install Python dependencies"
        exit 1
    fi
}

# Usage information
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run GCP Marketplace integration tests for A2A deployment.

OPTIONS:
    --project-id PROJECT_ID         GCP Project ID (required)
    --deployment-name NAME          Deployment name (required)
    --region REGION                 GCP region (default: us-central1)
    --zone ZONE                     GCP zone (default: us-central1-a)
    --namespace NAMESPACE           Kubernetes namespace (default: default)
    --skip-prereqs                  Skip prerequisite checks
    --skip-install                  Skip dependency installation
    -h, --help                      Show this help message

EXAMPLES:
    # Run tests with minimal configuration
    $0 --project-id my-gcp-project --deployment-name a2a-prod

    # Run tests with custom region and zone
    $0 --project-id my-gcp-project --deployment-name a2a-prod \\
       --region us-east1 --zone us-east1-b

    # Run tests in custom namespace
    $0 --project-id my-gcp-project --deployment-name a2a-prod \\
       --namespace a2a-system

ENVIRONMENT VARIABLES:
    GCP_PROJECT_ID                  GCP Project ID (overridden by --project-id)
    DEPLOYMENT_NAME                 Deployment name (overridden by --deployment-name)
    GCP_REGION                      GCP region (overridden by --region)
    GCP_ZONE                        GCP zone (overridden by --zone)
    NAMESPACE                       Kubernetes namespace (overridden by --namespace)

EOF
}

# Parse command-line arguments
parse_args() {
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-}"
    REGION="${GCP_REGION:-us-central1}"
    ZONE="${GCP_ZONE:-us-central1-a}"
    NAMESPACE="${NAMESPACE:-default}"
    SKIP_PREREQS=false
    SKIP_INSTALL=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --deployment-name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --skip-prereqs)
                SKIP_PREREQS=true
                shift
                ;;
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$PROJECT_ID" ]; then
        log_error "Project ID is required. Use --project-id or set GCP_PROJECT_ID"
        show_usage
        exit 1
    fi

    if [ -z "$DEPLOYMENT_NAME" ]; then
        log_error "Deployment name is required. Use --deployment-name or set DEPLOYMENT_NAME"
        show_usage
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting GCP Marketplace Integration Tests"
    log_info "==========================================\n"

    # Parse arguments
    parse_args "$@"

    # Display configuration
    log_info "Configuration:"
    echo "  Project ID:       $PROJECT_ID"
    echo "  Deployment Name:  $DEPLOYMENT_NAME"
    echo "  Region:           $REGION"
    echo "  Zone:             $ZONE"
    echo "  Namespace:        $NAMESPACE"
    echo ""

    # Check prerequisites
    if [ "$SKIP_PREREQS" = false ]; then
        check_prerequisites
    fi

    # Install dependencies
    if [ "$SKIP_INSTALL" = false ]; then
        install_dependencies
    fi

    # Verify GCP credentials
    log_info "Verifying GCP credentials..."
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" > /dev/null 2>&1; then
        ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
        log_success "Authenticated as: $ACTIVE_ACCOUNT"
    else
        log_error "No active GCP credentials found. Run 'gcloud auth login'"
        exit 1
    fi

    # Set active project
    log_info "Setting active GCP project..."
    if gcloud config set project "$PROJECT_ID" > /dev/null 2>&1; then
        log_success "Active project set to: $PROJECT_ID"
    else
        log_error "Failed to set active project"
        exit 1
    fi

    # Run integration tests
    log_info "Running integration tests..."
    echo ""

    if python3 "${SCRIPT_DIR}/integration_test.py" \
        --project-id "$PROJECT_ID" \
        --deployment-name "$DEPLOYMENT_NAME" \
        --region "$REGION" \
        --zone "$ZONE" \
        --namespace "$NAMESPACE"; then
        echo ""
        log_success "Integration tests completed successfully!"
        exit 0
    else
        echo ""
        log_error "Integration tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"
