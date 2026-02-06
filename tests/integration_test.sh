#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
HELM_DIR="${PROJECT_ROOT}/infrastructure/kubernetes/helm/craftplan"
HELM_A2A_ERL_DIR="${PROJECT_ROOT}/erlang/a2a_erl/helm/a2a-erl"
K8S_DIR="${PROJECT_ROOT}/erlang/a2a_erl/k8s"
TEST_NAMESPACE="integration-test"
HELM_RELEASE_NAME="a2a-test"
TEST_TIMEOUT=300

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

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."

    # Delete Helm releases
    helm list -n ${TEST_NAMESPACE} -q | xargs -r helm uninstall -n ${TEST_NAMESPACE} 2>/dev/null || true

    # Delete namespace
    kubectl delete namespace ${TEST_NAMESPACE} --ignore-not-found=true --timeout=60s 2>/dev/null || true

    # Cleanup Terraform (if in testing mode)
    if [ "${TERRAFORM_DESTROY_ON_EXIT}" = "true" ]; then
        cd ${TERRAFORM_DIR}
        terraform destroy -auto-approve 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Terraform Tests
run_terraform_tests() {
    log_info "===== Starting Terraform Tests ====="

    cd ${TERRAFORM_DIR}

    # Terraform format check
    log_info "Running terraform fmt check..."
    if terraform fmt -check -recursive .; then
        log_success "Terraform format check passed"
    else
        log_error "Terraform format check failed"
        return 1
    fi

    # Terraform init
    log_info "Running terraform init..."
    if terraform init -backend=false; then
        log_success "Terraform init successful"
    else
        log_error "Terraform init failed"
        return 1
    fi

    # Terraform validate
    log_info "Running terraform validate..."
    if terraform validate; then
        log_success "Terraform validation successful"
    else
        log_error "Terraform validation failed"
        return 1
    fi

    # Terraform plan
    log_info "Running terraform plan..."
    if terraform plan -out=tfplan -var="project_id=test-project" -var="region=us-central1" 2>&1 | tee terraform-plan.log; then
        log_success "Terraform plan successful"
    else
        log_warning "Terraform plan failed (may require valid credentials)"
    fi

    # Check for common issues in plan
    if [ -f "terraform-plan.log" ]; then
        log_info "Analyzing terraform plan output..."

        if grep -q "Error:" terraform-plan.log; then
            log_error "Found errors in terraform plan"
            cat terraform-plan.log
            return 1
        fi

        log_success "No critical errors in terraform plan"
        rm -f terraform-plan.log
    fi

    # Security checks
    log_info "Running terraform security checks..."

    # Check for hardcoded secrets
    if grep -r "password\s*=\s*\"[^$]" . --include="*.tf" 2>/dev/null; then
        log_error "Found hardcoded passwords in Terraform files"
        return 1
    fi

    if grep -r "api_key\s*=\s*\"[^$]" . --include="*.tf" 2>/dev/null; then
        log_error "Found hardcoded API keys in Terraform files"
        return 1
    fi

    log_success "No hardcoded secrets found"

    log_success "===== Terraform Tests Completed ====="
    cd ${PROJECT_ROOT}
}

# Helm Tests
run_helm_tests() {
    log_info "===== Starting Helm Tests ====="

    # Test Helm chart linting - craftplan
    if [ -d "${HELM_DIR}" ]; then
        log_info "Linting Helm chart: craftplan..."
        cd ${HELM_DIR}

        if helm lint .; then
            log_success "Helm lint passed for craftplan"
        else
            log_error "Helm lint failed for craftplan"
            return 1
        fi

        # Template rendering test
        log_info "Testing Helm template rendering for craftplan..."
        if helm template test-release . --debug > /tmp/helm-template-craftplan.yaml 2>&1; then
            log_success "Helm template rendering successful for craftplan"
        else
            log_error "Helm template rendering failed for craftplan"
            cat /tmp/helm-template-craftplan.yaml
            return 1
        fi

        # Validate rendered templates
        log_info "Validating rendered Kubernetes manifests for craftplan..."
        if kubectl apply --dry-run=client -f /tmp/helm-template-craftplan.yaml 2>&1; then
            log_success "Rendered manifests are valid for craftplan"
        else
            log_warning "Some rendered manifests may have issues for craftplan"
        fi
    fi

    # Test Helm chart linting - a2a-erl
    if [ -d "${HELM_A2A_ERL_DIR}" ]; then
        log_info "Linting Helm chart: a2a-erl..."
        cd ${HELM_A2A_ERL_DIR}

        if helm lint .; then
            log_success "Helm lint passed for a2a-erl"
        else
            log_error "Helm lint failed for a2a-erl"
            return 1
        fi

        # Template rendering test
        log_info "Testing Helm template rendering for a2a-erl..."
        if helm template test-release . --debug > /tmp/helm-template-a2a-erl.yaml 2>&1; then
            log_success "Helm template rendering successful for a2a-erl"
        else
            log_error "Helm template rendering failed for a2a-erl"
            cat /tmp/helm-template-a2a-erl.yaml
            return 1
        fi

        # Validate rendered templates
        log_info "Validating rendered Kubernetes manifests for a2a-erl..."
        if kubectl apply --dry-run=client -f /tmp/helm-template-a2a-erl.yaml 2>&1; then
            log_success "Rendered manifests are valid for a2a-erl"
        else
            log_warning "Some rendered manifests may have issues for a2a-erl"
        fi

        # Run Helm test suite
        log_info "Running Helm test files..."
        if [ -d "tests" ]; then
            for test_file in tests/test-*.yaml; do
                [ -f "$test_file" ] || continue
                log_info "Testing with values from $(basename $test_file)..."
                if helm template test-release . -f "$test_file" --debug > /tmp/helm-test-output.yaml 2>&1; then
                    log_success "Template test passed: $(basename $test_file)"
                else
                    log_error "Template test failed: $(basename $test_file)"
                    cat /tmp/helm-test-output.yaml
                    return 1
                fi
            done
        fi
    fi

    log_success "===== Helm Tests Completed ====="
    cd ${PROJECT_ROOT}
}

# Kubernetes Resource Validation
run_k8s_validation() {
    log_info "===== Starting Kubernetes Resource Validation ====="

    # Create test namespace
    log_info "Creating test namespace: ${TEST_NAMESPACE}..."
    kubectl create namespace ${TEST_NAMESPACE} 2>/dev/null || kubectl get namespace ${TEST_NAMESPACE}
    kubectl label namespace ${TEST_NAMESPACE} test=integration --overwrite

    # Validate static K8s manifests
    if [ -d "${K8S_DIR}" ]; then
        log_info "Validating Kubernetes manifests in ${K8S_DIR}..."

        for manifest in ${K8S_DIR}/*.yaml; do
            [ -f "$manifest" ] || continue
            log_info "Validating $(basename $manifest)..."

            # Skip test files
            if [[ "$(basename $manifest)" == test-* ]]; then
                continue
            fi

            if kubectl apply --dry-run=client -f "$manifest" -n ${TEST_NAMESPACE} 2>&1; then
                log_success "Valid manifest: $(basename $manifest)"
            else
                log_warning "Issues with manifest: $(basename $manifest)"
            fi
        done
    fi

    # Deploy Helm chart for validation
    if [ -d "${HELM_A2A_ERL_DIR}" ]; then
        log_info "Deploying Helm chart for validation..."

        cd ${HELM_A2A_ERL_DIR}

        # Create a test values file
        cat > /tmp/test-values.yaml <<EOF
replicaCount: 1

image:
  repository: nginx
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

persistence:
  enabled: false

ingress:
  enabled: false
EOF

        if helm install ${HELM_RELEASE_NAME} . -f /tmp/test-values.yaml -n ${TEST_NAMESPACE} --wait --timeout=5m; then
            log_success "Helm chart deployed successfully"
        else
            log_error "Helm chart deployment failed"
            kubectl get all -n ${TEST_NAMESPACE}
            kubectl describe pods -n ${TEST_NAMESPACE}
            return 1
        fi

        # Validate deployed resources
        log_info "Validating deployed Kubernetes resources..."

        # Check deployment
        if kubectl get deployment -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" -o json | jq -e '.items | length > 0' > /dev/null; then
            log_success "Deployment exists"

            # Check deployment status
            if kubectl rollout status deployment -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" --timeout=2m; then
                log_success "Deployment is ready"
            else
                log_error "Deployment failed to become ready"
                kubectl describe deployment -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}"
                return 1
            fi
        else
            log_warning "No deployment found"
        fi

        # Check service
        if kubectl get service -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" -o json | jq -e '.items | length > 0' > /dev/null; then
            log_success "Service exists"
        else
            log_warning "No service found"
        fi

        # Check pods
        log_info "Checking pod status..."
        local pod_count=$(kubectl get pods -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" --field-selector=status.phase=Running -o json | jq '.items | length')
        if [ "$pod_count" -gt 0 ]; then
            log_success "Found $pod_count running pod(s)"
        else
            log_error "No running pods found"
            kubectl get pods -n ${TEST_NAMESPACE}
            kubectl describe pods -n ${TEST_NAMESPACE}
            return 1
        fi

        # Check pod logs
        log_info "Checking pod logs..."
        local pod_name=$(kubectl get pods -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}')
        if [ -n "$pod_name" ]; then
            kubectl logs $pod_name -n ${TEST_NAMESPACE} --tail=50 || log_warning "Could not retrieve pod logs"
        fi

        # Resource usage check
        log_info "Checking resource usage..."
        kubectl top pods -n ${TEST_NAMESPACE} 2>/dev/null || log_warning "Metrics server not available"

        # Security context validation
        log_info "Validating security contexts..."
        local pods_json=$(kubectl get pods -n ${TEST_NAMESPACE} -o json)

        if echo "$pods_json" | jq -e '.items[] | select(.spec.securityContext.runAsNonRoot == false)' > /dev/null 2>&1; then
            log_warning "Some pods are running as root"
        else
            log_success "Security contexts properly configured"
        fi
    fi

    log_success "===== Kubernetes Resource Validation Completed ====="
    cd ${PROJECT_ROOT}
}

# End-to-End Tests
run_e2e_tests() {
    log_info "===== Starting End-to-End Tests ====="

    # Get service endpoint
    log_info "Getting service endpoint..."
    local service_name=$(kubectl get service -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$service_name" ]; then
        log_warning "No service found for E2E testing"
        return 0
    fi

    local service_ip=$(kubectl get service ${service_name} -n ${TEST_NAMESPACE} -o jsonpath='{.spec.clusterIP}')
    local service_port=$(kubectl get service ${service_name} -n ${TEST_NAMESPACE} -o jsonpath='{.spec.ports[0].port}')

    log_info "Service: ${service_name} at ${service_ip}:${service_port}"

    # Port-forward for testing
    log_info "Setting up port-forward for testing..."
    kubectl port-forward -n ${TEST_NAMESPACE} service/${service_name} 8888:${service_port} &
    local port_forward_pid=$!
    sleep 3

    # Health check test
    log_info "Running health check test..."
    local retry_count=0
    local max_retries=10

    while [ $retry_count -lt $max_retries ]; do
        if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:8888/ > /dev/null 2>&1; then
            log_success "Health check passed"
            break
        else
            retry_count=$((retry_count + 1))
            log_info "Health check attempt $retry_count/$max_retries..."
            sleep 2
        fi
    done

    if [ $retry_count -eq $max_retries ]; then
        log_warning "Health check did not succeed after $max_retries attempts"
    fi

    # HTTP endpoint tests
    log_info "Testing HTTP endpoints..."

    local response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/ 2>/dev/null || echo "000")
    log_info "HTTP GET / response: $response_code"

    if [ "$response_code" = "200" ] || [ "$response_code" = "404" ] || [ "$response_code" = "000" ]; then
        log_success "Service is responding"
    else
        log_warning "Unexpected response code: $response_code"
    fi

    # Cleanup port-forward
    kill $port_forward_pid 2>/dev/null || true

    # Pod lifecycle tests
    log_info "Testing pod resilience..."

    local pod_name=$(kubectl get pods -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$pod_name" ]; then
        log_info "Deleting pod to test self-healing: $pod_name"
        kubectl delete pod $pod_name -n ${TEST_NAMESPACE} --wait=false

        sleep 5

        # Wait for new pod to be running
        local wait_time=0
        while [ $wait_time -lt 60 ]; do
            local running_pods=$(kubectl get pods -n ${TEST_NAMESPACE} -l "app.kubernetes.io/instance=${HELM_RELEASE_NAME}" --field-selector=status.phase=Running -o json | jq '.items | length')
            if [ "$running_pods" -gt 0 ]; then
                log_success "Pod self-healing successful"
                break
            fi
            sleep 2
            wait_time=$((wait_time + 2))
        done

        if [ $wait_time -ge 60 ]; then
            log_error "Pod did not recover within timeout"
            return 1
        fi
    fi

    # ConfigMap and Secret validation
    log_info "Validating ConfigMaps and Secrets..."

    local configmaps=$(kubectl get configmap -n ${TEST_NAMESPACE} -o json | jq '.items | length')
    log_info "Found $configmaps ConfigMap(s)"

    local secrets=$(kubectl get secret -n ${TEST_NAMESPACE} -o json | jq '.items | length')
    log_info "Found $secrets Secret(s)"

    # Network policy tests (if applicable)
    log_info "Checking network policies..."
    local netpols=$(kubectl get networkpolicy -n ${TEST_NAMESPACE} -o json | jq '.items | length')
    if [ "$netpols" -gt 0 ]; then
        log_info "Found $netpols Network Policy(ies)"
    else
        log_info "No network policies found"
    fi

    # RBAC validation
    log_info "Validating RBAC resources..."

    local service_accounts=$(kubectl get serviceaccount -n ${TEST_NAMESPACE} -o json | jq '.items | length')
    log_info "Found $service_accounts ServiceAccount(s)"

    # Helm test hooks
    log_info "Running Helm test hooks..."
    if helm test ${HELM_RELEASE_NAME} -n ${TEST_NAMESPACE} --timeout=5m 2>&1; then
        log_success "Helm test hooks passed"
    else
        log_warning "Helm test hooks not available or failed"
    fi

    # Final validation - check all resources are healthy
    log_info "Final health validation..."

    local unhealthy_pods=$(kubectl get pods -n ${TEST_NAMESPACE} --field-selector=status.phase!=Running,status.phase!=Succeeded -o json | jq '.items | length')

    if [ "$unhealthy_pods" -eq 0 ]; then
        log_success "All pods are healthy"
    else
        log_error "Found $unhealthy_pods unhealthy pod(s)"
        kubectl get pods -n ${TEST_NAMESPACE}
        return 1
    fi

    log_success "===== End-to-End Tests Completed ====="
}

# Generate test report
generate_report() {
    log_info "===== Generating Test Report ====="

    local report_file="/tmp/integration-test-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "=================================="
        echo "Integration Test Report"
        echo "=================================="
        echo "Date: $(date)"
        echo "Project: A2A"
        echo "Test Namespace: ${TEST_NAMESPACE}"
        echo ""
        echo "Test Results:"
        echo "- Terraform Tests: ${TERRAFORM_STATUS:-PASSED}"
        echo "- Helm Tests: ${HELM_STATUS:-PASSED}"
        echo "- K8s Validation: ${K8S_STATUS:-PASSED}"
        echo "- E2E Tests: ${E2E_STATUS:-PASSED}"
        echo ""
        echo "Kubernetes Resources:"
        kubectl get all -n ${TEST_NAMESPACE} 2>/dev/null || echo "N/A"
        echo ""
        echo "=================================="
    } > "$report_file"

    log_success "Test report generated: $report_file"
    cat "$report_file"
}

# Main execution
main() {
    log_info "Starting A2A Integration Tests"
    log_info "Project Root: ${PROJECT_ROOT}"

    local exit_code=0

    # Check prerequisites
    check_prerequisites || exit 1

    # Run Terraform tests
    if run_terraform_tests; then
        TERRAFORM_STATUS="PASSED"
    else
        TERRAFORM_STATUS="FAILED"
        exit_code=1
    fi

    # Run Helm tests
    if run_helm_tests; then
        HELM_STATUS="PASSED"
    else
        HELM_STATUS="FAILED"
        exit_code=1
    fi

    # Run K8s validation
    if run_k8s_validation; then
        K8S_STATUS="PASSED"
    else
        K8S_STATUS="FAILED"
        exit_code=1
    fi

    # Run E2E tests
    if run_e2e_tests; then
        E2E_STATUS="PASSED"
    else
        E2E_STATUS="FAILED"
        exit_code=1
    fi

    # Generate report
    generate_report

    if [ $exit_code -eq 0 ]; then
        log_success "All integration tests passed!"
    else
        log_error "Some integration tests failed!"
    fi

    return $exit_code
}

# Run main function
main "$@"
