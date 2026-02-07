# Quick Start Guide - Infrastructure Security Tests

This guide will help you get started with running infrastructure security tests in under 5 minutes.

## Prerequisites

- Python 3.11 or higher
- Access to a GCP project with the infrastructure deployed
- kubectl configured for the GKE cluster

## Quick Setup

### 1. Install Dependencies (1 minute)

```bash
cd /home/user/A2A/tests/infrastructure
pip install -r requirements.txt
```

### 2. Configure GCP Authentication (2 minutes)

```bash
# Authenticate with GCP
gcloud auth application-default login

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Get cluster credentials
gcloud container clusters get-credentials a2a-gke \
  --region us-central1 \
  --project YOUR_PROJECT_ID
```

### 3. Set Environment Variables (30 seconds)

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="a2a-gke"
export VPC_NETWORK_NAME="a2a-vpc"
```

### 4. Run Tests (1 minute)

```bash
# Quick test run
./run_tests.sh

# Or using pytest directly
pytest -v
```

## What Gets Tested?

The test suite validates **44+ security controls** across three categories:

### Network Policies (11 tests)
- ✓ Default deny-all policies
- ✓ DNS egress configuration
- ✓ Pod selector validation
- ✓ Namespace coverage
- ✓ Policy documentation

### Firewall Rules (17 tests)
- ✓ Default deny ingress
- ✓ Health check configuration
- ✓ IAP access rules
- ✓ Cloud Armor DDoS protection
- ✓ Rate limiting
- ✓ OWASP Top 10 protections
- ✓ Geo-blocking
- ✓ IP blocking

### VPC Connectivity (16 tests)
- ✓ VPC configuration
- ✓ Subnet setup
- ✓ Private Google Access
- ✓ Cloud NAT
- ✓ GKE private clusters
- ✓ Workload Identity
- ✓ Network policy enablement
- ✓ Flow logs

## Expected Output

### Successful Run
```
============================= test session starts ==============================
platform linux -- Python 3.11.14, pytest-9.0.2, pluggy-1.6.0
collected 44 items

test_network_policies.py::TestNetworkPolicies::test_default_deny_all_policy_exists PASSED [  2%]
test_network_policies.py::TestNetworkPolicies::test_dns_egress_policy_exists PASSED [  4%]
...
test_vpc_connectivity.py::TestPrivateClusterConnectivity::test_network_policy_enabled PASSED [100%]

============================= 44 passed in 12.34s ===============================
```

### Failed Test Example
```
FAILED test_firewall_rules.py::TestCloudArmorPolicies::test_ddos_protection_enabled
  AssertionError: DDoS protection (Adaptive Protection) must be enabled
```

## Common Use Cases

### Test Specific Category
```bash
# Network policies only
pytest test_network_policies.py -v

# Firewall rules only
pytest test_firewall_rules.py -v

# VPC connectivity only
pytest test_vpc_connectivity.py -v
```

### Generate HTML Report
```bash
pytest -v --html=security_report.html --self-contained-html
```

### Run in CI/CD
```bash
# Add to your CI pipeline
export RUN_INTEGRATION_TESTS=true
./run_tests.sh --integration
```

## Troubleshooting

### Tests are skipped
**Cause:** GCP credentials not configured
**Fix:** Run `gcloud auth application-default login`

### Kubernetes tests fail
**Cause:** kubectl not configured
**Fix:** Run `gcloud container clusters get-credentials ...`

### Permission errors
**Cause:** Insufficient IAM roles
**Fix:** Ensure you have these roles:
- `roles/compute.networkViewer`
- `roles/container.viewer`
- `roles/compute.securityAdmin` (read-only)

## Next Steps

1. **Schedule regular runs** - Add to your CI/CD pipeline
2. **Review failures** - Fix any security gaps identified
3. **Customize tests** - Modify for your specific requirements
4. **Monitor trends** - Track security posture over time

## Need Help?

- Review the [full README](README.md) for detailed documentation
- Check test output for specific error messages
- Consult GCP and Kubernetes documentation

## Quick Commands Reference

```bash
# List all tests
pytest --collect-only

# Run with verbose output
pytest -v

# Run with coverage
pytest --cov=. --cov-report=html

# Run specific test
pytest test_network_policies.py::TestNetworkPolicies::test_default_deny_all_policy_exists -v

# Run tests by marker
pytest -m firewall -v
```
