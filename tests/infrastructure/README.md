# Infrastructure Security Tests

This directory contains comprehensive tests for validating network policies, firewall rules, and VPC connectivity for the A2A infrastructure.

## Test Coverage

### 1. Network Policies (`test_network_policies.py`)
Tests for Kubernetes Network Policies that control pod-to-pod communication:
- Default deny-all policies
- DNS egress policies
- Pod selector validation
- Namespace-level policy coverage
- Policy documentation and best practices

### 2. Firewall Rules (`test_firewall_rules.py`)
Tests for GCP VPC firewall rules and Cloud Armor security policies:
- Default deny-all ingress rules
- Health check firewall configuration
- IAP (Identity-Aware Proxy) access rules
- Internal VPC traffic rules
- Cloud Armor DDoS protection
- Rate limiting configuration
- OWASP Top 10 protections (SQL injection, XSS, etc.)
- Geographic blocking
- IP-based blocking

### 3. VPC Connectivity (`test_vpc_connectivity.py`)
Tests for VPC network configuration and connectivity:
- VPC network existence and configuration
- Subnet configuration and IP range validation
- Private Google Access
- VPC Flow Logs
- Cloud NAT configuration
- GKE private cluster setup
- Master authorized networks
- Workload Identity
- DNS configuration
- Private Service Connect

## Prerequisites

### 1. Install Dependencies
```bash
cd /home/user/A2A/tests/infrastructure
pip install -r requirements.txt
```

### 2. Set up GCP Authentication
```bash
# Option 1: Application Default Credentials
gcloud auth application-default login

# Option 2: Service Account Key
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

### 3. Set Environment Variables
```bash
# Required
export GCP_PROJECT_ID="your-gcp-project-id"

# Optional (with defaults)
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="a2a-gke"
export VPC_NETWORK_NAME="a2a-vpc"
```

### 4. Configure kubectl for Kubernetes Tests
```bash
# Get GKE cluster credentials
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --region ${GCP_REGION} \
  --project ${GCP_PROJECT_ID}

# Verify connection
kubectl cluster-info
```

## Running Tests

### Run All Tests
```bash
# Run all infrastructure tests
pytest tests/infrastructure/ -v

# Run with integration tests (requires live infrastructure)
pytest tests/infrastructure/ -v --integration
```

### Run Specific Test Categories
```bash
# Network Policy tests only
pytest tests/infrastructure/test_network_policies.py -v

# Firewall Rules tests only
pytest tests/infrastructure/test_firewall_rules.py -v

# VPC Connectivity tests only
pytest tests/infrastructure/test_vpc_connectivity.py -v
```

### Run Tests by Marker
```bash
# Run only network policy tests
pytest tests/infrastructure/ -v -m network_policy

# Run only firewall tests
pytest tests/infrastructure/ -v -m firewall

# Run only VPC tests
pytest tests/infrastructure/ -v -m vpc

# Run only Cloud Armor tests
pytest tests/infrastructure/ -v -m cloud_armor
```

### Run with Coverage Report
```bash
pytest tests/infrastructure/ -v --cov=. --cov-report=html --cov-report=term
```

### Run Parallel Tests (Faster)
```bash
pytest tests/infrastructure/ -v -n auto
```

## Test Output

### HTML Report
```bash
pytest tests/infrastructure/ -v --html=report.html --self-contained-html
```

### JSON Report
```bash
pytest tests/infrastructure/ -v --json-report --json-report-file=report.json
```

## Continuous Integration

### GitHub Actions Example
```yaml
name: Infrastructure Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -r tests/infrastructure/requirements.txt

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_CREDENTIALS }}

      - name: Set up kubectl
        run: |
          gcloud container clusters get-credentials ${{ secrets.GKE_CLUSTER_NAME }} \
            --region ${{ secrets.GCP_REGION }} \
            --project ${{ secrets.GCP_PROJECT_ID }}

      - name: Run tests
        env:
          GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
          GCP_REGION: ${{ secrets.GCP_REGION }}
          GKE_CLUSTER_NAME: ${{ secrets.GKE_CLUSTER_NAME }}
        run: |
          pytest tests/infrastructure/ -v --integration --html=report.html

      - name: Upload test report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-report
          path: report.html
```

## Troubleshooting

### Issue: "Kubernetes cluster not accessible"
**Solution:** Ensure kubectl is configured and you have cluster access:
```bash
kubectl cluster-info
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --region ${GCP_REGION}
```

### Issue: "GCP credentials not found"
**Solution:** Set up authentication:
```bash
gcloud auth application-default login
# OR
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
```

### Issue: "Permission denied" errors
**Solution:** Ensure your GCP account/service account has the following IAM roles:
- `roles/compute.networkViewer` - For firewall and VPC tests
- `roles/container.viewer` - For GKE tests
- `roles/compute.securityAdmin` - For Cloud Armor tests (read-only)

### Issue: Tests are slow
**Solution:** Run tests in parallel:
```bash
pytest tests/infrastructure/ -v -n auto
```

## Best Practices

1. **Run tests regularly**: Include these tests in your CI/CD pipeline
2. **Test before deployment**: Run tests before applying Terraform changes
3. **Monitor test results**: Set up alerts for test failures
4. **Keep tests updated**: Update tests when infrastructure changes
5. **Document exceptions**: If a test doesn't apply to your setup, document why

## Security Considerations

- These tests validate security controls but don't replace security audits
- Tests check configuration, not actual network behavior
- Combine with penetration testing for comprehensive security validation
- Review and update security policies regularly

## Contributing

When adding new tests:
1. Follow the existing test structure and naming conventions
2. Add appropriate markers (`@pytest.mark.network_policy`, etc.)
3. Include docstrings explaining what the test validates
4. Update this README with new test coverage
5. Ensure tests can run in CI/CD environments

## Support

For issues or questions:
- Check the troubleshooting section above
- Review test output for specific error messages
- Consult GCP and Kubernetes documentation
- Open an issue in the project repository
