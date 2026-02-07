# Test Execution Demonstration

This document shows what happens when you run the infrastructure security tests.

## Test Collection

When you run `pytest --collect-only`, you'll see all 44 tests organized by category:

```
$ pytest --collect-only -q

collected 44 items

Network Policies: 11 tests
  - Default deny-all policy validation
  - DNS egress configuration
  - Pod selector validation
  - Namespace coverage checks
  - Policy documentation

Firewall Rules: 17 tests
  - GCP firewall rules (8 tests)
  - Cloud Armor policies (7 tests)
  - VPC Service Controls (2 tests)

VPC Connectivity: 16 tests
  - VPC configuration (6 tests)
  - Cloud NAT (4 tests)
  - Private cluster (4 tests)
  - DNS configuration (1 test)
  - Service connectivity (1 test)
```

## Sample Test Run

### Scenario: All Tests Pass

```bash
$ pytest -v

============================= test session starts ==============================
platform linux -- Python 3.11.14, pytest-9.0.2
collected 44 items

test_network_policies.py::TestNetworkPolicies::test_default_deny_all_policy_exists PASSED [  2%]
test_network_policies.py::TestNetworkPolicies::test_dns_egress_policy_exists PASSED [  4%]
test_network_policies.py::TestNetworkPolicies::test_no_pods_without_network_policies PASSED [  6%]
...
test_vpc_connectivity.py::TestPrivateClusterConnectivity::test_network_policy_enabled PASSED [100%]

============================= 44 passed in 18.45s ===============================
```

### Scenario: Some Tests Fail

```bash
$ pytest -v

test_firewall_rules.py::TestCloudArmorPolicies::test_ddos_protection_enabled FAILED [ 20%]

=================================== FAILURES ===================================
_________________ TestCloudArmorPolicies.test_ddos_protection_enabled __________

    def test_ddos_protection_enabled(self):
        """Test that DDoS protection is enabled in Cloud Armor."""
        try:
            policies = self.security_policy_client.list(project=self.project_id)
            
            ddos_enabled = False
            for policy in policies:
                if policy.adaptive_protection_config:
                    if policy.adaptive_protection_config.layer7_ddos_defense_config:
                        if policy.adaptive_protection_config.layer7_ddos_defense_config.enable:
                            ddos_enabled = True
                            break
            
>           assert ddos_enabled, \
                "DDoS protection (Adaptive Protection) must be enabled"
E           AssertionError: DDoS protection (Adaptive Protection) must be enabled

test_firewall_rules.py:78: AssertionError

============================= 21 passed, 1 failed in 15.32s =====================
```

## Test Categories Detail

### 1. Network Policies - Kubernetes Pod Security

**Purpose**: Validate that Kubernetes Network Policies properly control pod-to-pod communication

**What's Tested**:
```
✓ Default deny-all policy exists
✓ DNS egress is allowed (for name resolution)
✓ All namespaces have policies
✓ Pod selectors are valid
✓ Critical services are accessible
✓ Policies are documented
✓ Policies are not overly permissive
```

**Why It Matters**: Network policies are the first line of defense for pod-to-pod communication. Without them, any compromised pod can communicate with any other pod in the cluster.

### 2. Firewall Rules - GCP Network Security

**Purpose**: Validate GCP VPC firewall rules and Cloud Armor policies

**What's Tested**:
```
Firewall Rules:
✓ Default deny-all ingress
✓ Health check access from GCP ranges
✓ IAP access for secure SSH/RDP
✓ Internal VPC traffic rules
✓ Rule priorities are correct
✓ Logging is enabled
✓ No overly permissive rules

Cloud Armor:
✓ DDoS protection enabled
✓ Rate limiting configured
✓ SQL injection protection
✓ XSS protection
✓ RCE protection
✓ Geographic blocking
✓ IP-based blocking
```

**Why It Matters**: Firewall rules control network access at the infrastructure level. Misconfigured rules can expose your infrastructure to attacks.

### 3. VPC Connectivity - Network Infrastructure

**Purpose**: Validate VPC configuration, routing, and connectivity

**What's Tested**:
```
VPC Configuration:
✓ VPC exists and is properly configured
✓ Subnets have correct IP ranges
✓ No IP range overlaps
✓ Private Google Access enabled
✓ VPC Flow Logs enabled
✓ RFC 1918 private IP ranges used

Cloud NAT:
✓ Cloud Router configured
✓ NAT gateway configured
✓ NAT logging enabled
✓ Port allocation configured

Private Cluster:
✓ GKE cluster uses private nodes
✓ Master authorized networks configured
✓ Workload Identity enabled
✓ Network policy enabled
```

**Why It Matters**: Proper VPC configuration ensures secure, reliable connectivity while maintaining isolation and monitoring capabilities.

## Using the Test Runner Script

```bash
$ ./run_tests.sh

=== Infrastructure Security Tests ===

Using GCP Project: my-project-123
Using GCP Region: us-central1

✓ kubectl is configured
✓ GCP authenticated as: user@example.com

Installing dependencies...
Done.

Running tests...

============================= test session starts ==============================
collected 44 items

test_network_policies.py ........... [ 25%]
test_firewall_rules.py ................. [ 63%]
test_vpc_connectivity.py ................ [100%]

============================= 44 passed in 18.45s ===============================

=== All tests passed! ===
```

## HTML Report Example

When you run with `--html=report.html`, you get a beautiful HTML report:

```
Environment Information:
  Platform: Linux
  Python: 3.11.14
  Pytest: 9.0.2
  GCP Project: my-project-123
  GCP Region: us-central1

Test Results:
  Total: 44
  Passed: 43
  Failed: 1
  Skipped: 0
  Duration: 18.45s

Failed Tests:
  test_firewall_rules.py::TestCloudArmorPolicies::test_ddos_protection_enabled
    Reason: DDoS protection (Adaptive Protection) must be enabled
    Fix: Enable Adaptive Protection in Cloud Armor policy
```

## Integration with CI/CD

The tests integrate seamlessly with CI/CD pipelines:

```yaml
# .github/workflows/security-tests.yml
name: Infrastructure Security Tests

on: [push, pull_request]

jobs:
  security-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Run tests
        env:
          GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
        run: |
          cd tests/infrastructure
          pip install -r requirements.txt
          pytest -v --integration --html=report.html
      
      - name: Upload report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: security-report
          path: tests/infrastructure/report.html
```

## Command Reference

```bash
# Basic run
pytest -v

# Run specific category
pytest test_network_policies.py -v
pytest test_firewall_rules.py -v
pytest test_vpc_connectivity.py -v

# Generate HTML report
pytest -v --html=report.html --self-contained-html

# Run in parallel (faster)
pytest -v -n auto

# Run with coverage
pytest --cov=. --cov-report=html

# Run only failed tests
pytest -v --lf

# Stop on first failure
pytest -v -x

# Show slowest tests
pytest -v --durations=10
```

## Exit Codes

- **0**: All tests passed
- **1**: Some tests failed
- **2**: Test execution was interrupted
- **3**: Internal error occurred
- **4**: pytest command line usage error
- **5**: No tests collected

## Next Steps After Running Tests

1. **If all tests pass**: Your infrastructure security posture is good!
2. **If tests fail**: Review the failure details and fix the issues
3. **Schedule regular runs**: Add to your CI/CD pipeline
4. **Monitor trends**: Track pass/fail rates over time
5. **Update tests**: Keep tests current as infrastructure evolves
