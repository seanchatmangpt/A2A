#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Exit code tracking
EXIT_CODE=0

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    EXIT_CODE=1
}

log_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Terraform validation
validate_terraform() {
    log_section "Terraform Validation"

    if ! command_exists terraform; then
        log_warn "Terraform not found, skipping terraform validation"
        return
    fi

    # Find all terraform directories
    TERRAFORM_DIRS=$(find "$PROJECT_ROOT" -type f -name "*.tf" -exec dirname {} \; | sort -u)

    if [ -z "$TERRAFORM_DIRS" ]; then
        log_warn "No terraform files found"
        return
    fi

    for dir in $TERRAFORM_DIRS; do
        log_info "Validating terraform in: $dir"

        cd "$dir"

        # Initialize terraform
        if ! terraform init -backend=false >/dev/null 2>&1; then
            log_error "Terraform init failed in $dir"
            continue
        fi

        # Validate terraform
        if terraform validate; then
            log_info "Terraform validation passed: $dir"
        else
            log_error "Terraform validation failed: $dir"
        fi

        # Format check
        if ! terraform fmt -check -recursive; then
            log_error "Terraform formatting issues found in $dir"
        fi
    done

    cd "$PROJECT_ROOT"
}

# Helm validation
validate_helm() {
    log_section "Helm Chart Validation"

    if ! command_exists helm; then
        log_warn "Helm not found, skipping helm validation"
        return
    fi

    # Find all helm charts
    CHART_DIRS=$(find "$PROJECT_ROOT" -type f -name "Chart.yaml" -exec dirname {} \; | sort -u)

    if [ -z "$CHART_DIRS" ]; then
        log_warn "No helm charts found"
        return
    fi

    for chart_dir in $CHART_DIRS; do
        log_info "Linting helm chart: $chart_dir"

        if helm lint "$chart_dir" --strict; then
            log_info "Helm lint passed: $chart_dir"
        else
            log_error "Helm lint failed: $chart_dir"
        fi

        # Validate template rendering
        log_info "Validating template rendering: $chart_dir"
        if helm template "$chart_dir" >/dev/null 2>&1; then
            log_info "Helm template rendering passed: $chart_dir"
        else
            log_error "Helm template rendering failed: $chart_dir"
        fi
    done
}

# YAML validation
validate_yaml() {
    log_section "YAML Validation"

    # Check for yamllint
    if command_exists yamllint; then
        log_info "Running yamllint"

        if [ -f "$PROJECT_ROOT/.yamllint" ] || [ -f "$PROJECT_ROOT/.yamllint.yaml" ]; then
            if yamllint "$PROJECT_ROOT"; then
                log_info "YAML linting passed"
            else
                log_error "YAML linting failed"
            fi
        else
            # Run with relaxed config if no config file exists
            if yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" "$PROJECT_ROOT" 2>/dev/null; then
                log_info "YAML linting passed"
            else
                log_warn "YAML linting found issues"
            fi
        fi
    else
        log_info "yamllint not found, using python yaml validation"

        # Find all YAML files
        YAML_FILES=$(find "$PROJECT_ROOT" -type f \( -name "*.yaml" -o -name "*.yml" \) \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*" \
            -not -path "*/vendor/*" \
            -not -path "*/_build/*")

        if [ -z "$YAML_FILES" ]; then
            log_warn "No YAML files found"
            return
        fi

        # Validate with Python
        for yaml_file in $YAML_FILES; do
            if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                log_info "Valid YAML: $yaml_file"
            else
                log_error "Invalid YAML: $yaml_file"
            fi
        done
    fi
}

# Kubernetes manifest validation
validate_k8s_manifests() {
    log_section "Kubernetes Manifest Validation"

    if ! command_exists kubectl; then
        log_warn "kubectl not found, skipping k8s manifest validation"
        return
    fi

    # Find kubernetes manifest files
    K8S_DIRS="$PROJECT_ROOT/infrastructure/kubernetes $PROJECT_ROOT/k8s $PROJECT_ROOT/kubernetes"

    for k8s_dir in $K8S_DIRS; do
        if [ -d "$k8s_dir" ]; then
            log_info "Validating kubernetes manifests in: $k8s_dir"

            K8S_FILES=$(find "$k8s_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) \
                -not -path "*/helm/*" 2>/dev/null || true)

            for manifest in $K8S_FILES; do
                if kubectl apply --dry-run=client -f "$manifest" >/dev/null 2>&1; then
                    log_info "Valid k8s manifest: $manifest"
                else
                    log_error "Invalid k8s manifest: $manifest"
                fi
            done
        fi
    done
}

# Security checks
security_checks() {
    log_section "Security Checks"

    # Check for hardcoded secrets
    log_info "Checking for hardcoded secrets"

    SENSITIVE_PATTERNS=(
        "password.*=.*['\"].*['\"]"
        "api[_-]?key.*=.*['\"].*['\"]"
        "secret.*=.*['\"].*['\"]"
        "token.*=.*['\"].*['\"]"
        "BEGIN.*PRIVATE.*KEY"
        "aws_secret_access_key"
        "AKIA[0-9A-Z]{16}"
    )

    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        MATCHES=$(grep -r -i -E "$pattern" "$PROJECT_ROOT" \
            --exclude-dir=.git \
            --exclude-dir=node_modules \
            --exclude-dir=vendor \
            --exclude-dir=_build \
            --exclude-dir=.terraform \
            --exclude="*.log" \
            --exclude="validate.sh" \
            2>/dev/null || true)

        if [ -n "$MATCHES" ]; then
            log_warn "Potential hardcoded secret found (pattern: $pattern)"
            echo "$MATCHES" | head -5
        fi
    done

    # Check for tfsec if available
    if command_exists tfsec; then
        log_info "Running tfsec security scanner"

        TERRAFORM_DIRS=$(find "$PROJECT_ROOT" -type f -name "*.tf" -exec dirname {} \; | sort -u)

        for dir in $TERRAFORM_DIRS; do
            log_info "Scanning terraform security: $dir"
            if tfsec "$dir" --minimum-severity MEDIUM; then
                log_info "tfsec scan passed: $dir"
            else
                log_error "tfsec scan found issues: $dir"
            fi
        done
    else
        log_warn "tfsec not found, skipping terraform security scan"
    fi

    # Check for trivy if available
    if command_exists trivy; then
        log_info "Running trivy security scanner"

        if trivy fs --severity HIGH,CRITICAL "$PROJECT_ROOT"; then
            log_info "trivy scan passed"
        else
            log_error "trivy scan found issues"
        fi
    else
        log_warn "trivy not found, skipping container security scan"
    fi

    # Check for kubesec if available
    if command_exists kubesec; then
        log_info "Running kubesec security scanner"

        K8S_FILES=$(find "$PROJECT_ROOT" -type f \( -name "*.yaml" -o -name "*.yml" \) \
            -path "*/kubernetes/*" -o -path "*/k8s/*" 2>/dev/null || true)

        for manifest in $K8S_FILES; do
            SCORE=$(kubesec scan "$manifest" 2>/dev/null | jq -r '.[0].score' 2>/dev/null || echo "N/A")
            if [ "$SCORE" != "N/A" ] && [ "$SCORE" -lt 0 ]; then
                log_error "kubesec score negative for: $manifest (score: $SCORE)"
            else
                log_info "kubesec scan passed: $manifest (score: $SCORE)"
            fi
        done
    else
        log_warn "kubesec not found, skipping kubernetes security scan"
    fi
}

# GCP Marketplace specific checks
gcp_marketplace_checks() {
    log_section "GCP Marketplace Specific Checks"

    # Check for required files
    log_info "Checking for required GCP Marketplace files"

    REQUIRED_FILES=(
        "schema.yaml"
        "application.yaml"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            log_info "Found required file: $file"
        else
            log_warn "Missing GCP Marketplace file: $file"
        fi
    done

    # Validate schema.yaml structure
    if [ -f "$PROJECT_ROOT/schema.yaml" ]; then
        log_info "Validating schema.yaml structure"

        python3 << 'EOF'
import yaml
import sys

try:
    with open('schema.yaml', 'r') as f:
        schema = yaml.safe_load(f)

    required_fields = ['x-google-marketplace', 'properties']
    missing = [field for field in required_fields if field not in schema]

    if missing:
        print(f"Missing required fields in schema.yaml: {missing}")
        sys.exit(1)

    print("schema.yaml structure is valid")
except Exception as e:
    print(f"Error validating schema.yaml: {e}")
    sys.exit(1)
EOF

        if [ $? -eq 0 ]; then
            log_info "schema.yaml validation passed"
        else
            log_error "schema.yaml validation failed"
        fi
    fi
}

# Main execution
main() {
    log_section "Starting GCP Marketplace Validation"
    log_info "Project root: $PROJECT_ROOT"

    validate_terraform
    validate_helm
    validate_yaml
    validate_k8s_manifests
    security_checks
    gcp_marketplace_checks

    log_section "Validation Complete"

    if [ $EXIT_CODE -eq 0 ]; then
        log_info "All validations passed successfully!"
    else
        log_error "Some validations failed. Please review the errors above."
    fi

    exit $EXIT_CODE
}

# Run main function
main "$@"
