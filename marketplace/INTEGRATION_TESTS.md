# GCP Marketplace Integration Tests

Comprehensive integration test suite for validating A2A Protocol deployment on Google Cloud Platform Marketplace.

## Overview

This test suite validates all components of the GCP Marketplace deployment including:

- **Network Infrastructure**: VPC, subnets, firewall rules
- **Identity & Access Management**: Service accounts, IAM bindings
- **GKE Cluster**: Cluster health, nodes, node pools
- **Cloud SQL**: Database instance, connectivity
- **Kubernetes Resources**: Namespaces, ConfigMaps, Secrets, Deployments, Services, HPA
- **Application Health**: Health endpoints, pod logs
- **Security & Compliance**: Pod security contexts, RBAC, resource limits, network policies
- **Storage**: Persistent volumes and claims
- **Load Balancing**: External access configuration

## Files

- `integration_test.py` - Main Python-based integration test suite
- `run_integration_tests.sh` - Shell script wrapper for running tests
- `test_runner_demo.sh` - Demo mode test runner (no GCP resources required)
- `requirements-integration.txt` - Python dependencies

## Prerequisites

### Required Tools

- `python3` (3.8 or higher)
- `gcloud` CLI (authenticated)
- `kubectl` (configured)
- `jq` (for JSON parsing)

### Python Dependencies

```bash
pip install -r requirements-integration.txt
```

### GCP Authentication

```bash
# Authenticate with GCP
gcloud auth login

# Set default project
gcloud config set project YOUR_PROJECT_ID
```

## Quick Start

### Demo Mode (No GCP Resources Required)

Run the demo test suite to see what the tests look like:

```bash
./test_runner_demo.sh
```

This demonstrates all 25 integration tests without requiring actual GCP infrastructure.

### Real Integration Tests

Run tests against actual GCP deployment:

```bash
./run_integration_tests.sh \
  --project-id my-gcp-project \
  --deployment-name a2a-prod \
  --region us-central1 \
  --zone us-central1-a \
  --namespace default
```

## Usage

### Using the Shell Wrapper

The `run_integration_tests.sh` script provides a convenient wrapper:

```bash
./run_integration_tests.sh [OPTIONS]

OPTIONS:
  --project-id PROJECT_ID         GCP Project ID (required)
  --deployment-name NAME          Deployment name (required)
  --region REGION                 GCP region (default: us-central1)
  --zone ZONE                     GCP zone (default: us-central1-a)
  --namespace NAMESPACE           Kubernetes namespace (default: default)
  --skip-prereqs                  Skip prerequisite checks
  --skip-install                  Skip dependency installation
  -h, --help                      Show help message
```

### Using Python Directly

Run the Python test suite directly:

```bash
python3 integration_test.py \
  --project-id my-gcp-project \
  --deployment-name a2a-prod \
  --region us-central1 \
  --zone us-central1-a \
  --namespace default
```

### Environment Variables

You can also set configuration via environment variables:

```bash
export GCP_PROJECT_ID=my-gcp-project
export DEPLOYMENT_NAME=a2a-prod
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a
export NAMESPACE=default

./run_integration_tests.sh
```

## Test Categories

### 1. Network Tests (3 tests)

- **VPC Network Existence**: Verifies VPC network is created
- **Subnet Configuration**: Validates subnet CIDR ranges
- **Firewall Rules**: Checks firewall rules for the network

### 2. IAM Tests (2 tests)

- **Service Account Existence**: Verifies service accounts are created
- **IAM Policy Bindings**: Validates IAM permissions

### 3. GKE Cluster Tests (3 tests)

- **GKE Cluster Existence**: Verifies cluster is created
- **GKE Cluster Health**: Checks node readiness
- **GKE Node Pools**: Validates node pool configuration

### 4. Cloud SQL Tests (2 tests)

- **Cloud SQL Instance Existence**: Verifies database instance
- **Cloud SQL Connectivity**: Checks database connection configuration

### 5. Kubernetes Resources Tests (7 tests)

- **Namespace**: Validates namespace exists
- **ConfigMaps**: Checks configuration data
- **Secrets**: Verifies secrets are created
- **Deployment**: Validates application deployment
- **Pods**: Checks pod health and readiness
- **Service**: Verifies service configuration
- **HorizontalPodAutoscaler**: Validates autoscaling setup

### 6. Application Health Tests (2 tests)

- **Application Health Check**: Tests health endpoint
- **Pod Logs**: Verifies log accessibility

### 7. Security & Compliance Tests (4 tests)

- **Pod Security Context**: Validates security settings
- **Network Policies**: Checks network isolation
- **RBAC Configuration**: Verifies role-based access control
- **Resource Limits**: Ensures resource constraints are set

### 8. Storage Tests (1 test)

- **Persistent Volumes**: Validates PVC binding

### 9. Load Balancer Tests (1 test)

- **Load Balancer**: Verifies external access configuration

## Test Results

### Exit Codes

- `0` - All critical tests passed
- `1` - One or more tests failed

### Result Types

- **PASS** ✓ - Test passed successfully
- **FAIL** ✗ - Critical failure (contributes to exit code)
- **WARN** ⚠ - Warning (does not fail the test suite)
- **SKIP** ○ - Test skipped (resource not available)

### Output Formats

#### Console Output

Real-time test results with colored output:

```
[INFO] Starting GCP Marketplace Integration Tests
==========================================================================
✓ [PASS] VPC Network Existence: VPC network 'a2a-demo-vpc' exists (0.45s)
✓ [PASS] Subnet Configuration: Found 1 subnet(s) (0.38s)
...
```

#### JSON Report

Detailed JSON report saved to `/tmp/gcp_marketplace_integration_test_report_<timestamp>.json`:

```json
{
  "timestamp": 1770442676,
  "project_id": "my-gcp-project",
  "deployment_name": "a2a-prod",
  "summary": {
    "total": 25,
    "passed": 24,
    "failed": 0,
    "warnings": 1,
    "pass_rate": 96.0
  },
  "results": [...]
}
```

#### Log File

Detailed log file: `/tmp/gcp_marketplace_integration_test.log`

## Example Output

```
================================================================================
                              TEST REPORT
================================================================================

Timestamp:       2026-02-07 05:37:56
Project:         my-gcp-project
Deployment:      a2a-prod

Test Summary:
  Total Tests:   25
  Passed:        24 (96%)
  Failed:        0
  Warnings:      1
  Skipped:       0

✓ ALL CRITICAL TESTS PASSED
================================================================================
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Run GCP Marketplace Integration Tests
  run: |
    cd marketplace
    ./run_integration_tests.sh \
      --project-id ${{ secrets.GCP_PROJECT_ID }} \
      --deployment-name ${{ env.DEPLOYMENT_NAME }} \
      --region us-central1 \
      --zone us-central1-a
```

### GitLab CI

```yaml
integration_tests:
  script:
    - cd marketplace
    - ./run_integration_tests.sh
        --project-id ${GCP_PROJECT_ID}
        --deployment-name ${DEPLOYMENT_NAME}
  artifacts:
    reports:
      junit: /tmp/gcp_marketplace_integration_test_report_*.json
```

### Jenkins

```groovy
stage('Integration Tests') {
  steps {
    sh '''
      cd marketplace
      ./run_integration_tests.sh \
        --project-id ${GCP_PROJECT_ID} \
        --deployment-name ${DEPLOYMENT_NAME}
    '''
  }
}
```

## Troubleshooting

### Common Issues

#### Authentication Errors

```bash
# Re-authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Verify active account
gcloud auth list
```

#### Kubectl Configuration

```bash
# Get cluster credentials
gcloud container clusters get-credentials CLUSTER_NAME \
  --zone ZONE \
  --project PROJECT_ID
```

#### Missing Dependencies

```bash
# Install Python dependencies
pip install -r requirements-integration.txt

# Install gcloud SDK
curl https://sdk.cloud.google.com | bash

# Install kubectl
gcloud components install kubectl
```

#### Permission Denied

```bash
# Make scripts executable
chmod +x run_integration_tests.sh
chmod +x test_runner_demo.sh
chmod +x integration_test.py
```

### Debug Mode

Enable verbose logging:

```bash
# Run with Python verbose mode
python3 -v integration_test.py --project-id ... --deployment-name ...

# Check logs
tail -f /tmp/gcp_marketplace_integration_test.log
```

## Customization

### Adding New Tests

1. Add test method to `GCPMarketplaceIntegrationTest` class:

```python
def test_my_custom_check(self) -> bool:
    """Test XX: Custom validation"""
    start_time = time.time()
    test_name = "My Custom Check"

    # Your test logic here
    cmd = ["gcloud", "..."]
    returncode, stdout, stderr = self.run_command(cmd, check=False)
    duration = time.time() - start_time

    if returncode == 0:
        self.record_result(test_name, "PASS", "Check passed", duration)
        return True
    else:
        self.record_result(test_name, "FAIL", f"Check failed: {stderr}", duration)
        return False
```

2. Add to test execution in `run_all_tests()`:

```python
def run_all_tests(self):
    # ... existing tests ...

    logger.info("\n--- My Custom Tests ---")
    self.test_my_custom_check()
```

### Modifying Test Thresholds

Edit test conditions in the Python file:

```python
# Example: Change node readiness threshold
if ready_nodes >= (node_count * 0.8):  # 80% threshold
    self.record_result(test_name, "PASS", ...)
```

## Best Practices

1. **Run tests after deployment**: Validate infrastructure immediately after creation
2. **Run tests before updates**: Ensure current state is healthy before changes
3. **Automate in CI/CD**: Include tests in deployment pipelines
4. **Monitor trends**: Track test results over time
5. **Fix warnings**: Address warnings before they become failures
6. **Review logs**: Check detailed logs for additional context

## Support

For issues or questions:

- GitHub Issues: https://github.com/a2aproject/A2A/issues
- Documentation: https://a2a-protocol.org
- Community: https://github.com/a2aproject/A2A/discussions

## License

Apache License 2.0 - See LICENSE file for details
