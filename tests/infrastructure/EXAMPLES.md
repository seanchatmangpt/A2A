# Test Execution Examples

This document provides real-world examples of running the infrastructure security tests.

## Basic Usage Examples

### 1. Run All Tests
```bash
cd /home/user/A2A/tests/infrastructure
pytest -v
```

**Expected Output:**
```
============================= test session starts ==============================
collected 44 items

test_network_policies.py::test_default_deny_all_policy_exists PASSED    [  2%]
test_network_policies.py::test_dns_egress_policy_exists PASSED          [  4%]
...
============================= 44 passed in 15.23s ===============================
```

### 2. Run Specific Test File
```bash
# Network policies only
pytest test_network_policies.py -v

# Firewall rules only
pytest test_firewall_rules.py -v

# VPC connectivity only
pytest test_vpc_connectivity.py -v
```

### 3. Run Specific Test Class
```bash
# Cloud Armor tests only
pytest test_firewall_rules.py::TestCloudArmorPolicies -v

# Network policy tests only
pytest test_network_policies.py::TestNetworkPolicies -v
```

### 4. Run Single Test
```bash
pytest test_network_policies.py::TestNetworkPolicies::test_default_deny_all_policy_exists -v
```

## Advanced Usage Examples

### 1. Generate HTML Report
```bash
pytest -v --html=security_report.html --self-contained-html
open security_report.html  # or firefox security_report.html
```

### 2. Run with Coverage
```bash
pytest --cov=. --cov-report=html --cov-report=term
open htmlcov/index.html
```

### 3. Run Tests in Parallel (Faster)
```bash
# Auto-detect number of CPUs
pytest -v -n auto

# Specify number of workers
pytest -v -n 4
```

### 4. Run Tests with Markers
```bash
# Network policy tests
pytest -m network_policy -v

# Firewall tests
pytest -m firewall -v

# VPC tests
pytest -m vpc -v

# Integration tests only
pytest -m integration -v --integration
```

### 5. Run with Detailed Output
```bash
# Show all output including passed tests
pytest -v -s

# Show local variables on failure
pytest -v -l

# Show full traceback
pytest -v --tb=long
```

## CI/CD Integration Examples

### GitHub Actions
```yaml
- name: Run Infrastructure Tests
  env:
    GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
    GCP_REGION: us-central1
  run: |
    cd tests/infrastructure
    pip install -r requirements.txt
    pytest -v --integration \
      --html=report.html \
      --json-report --json-report-file=report.json
```

### GitLab CI
```yaml
infrastructure_tests:
  stage: test
  script:
    - cd tests/infrastructure
    - pip install -r requirements.txt
    - pytest -v --integration
  artifacts:
    reports:
      junit: tests/infrastructure/report.xml
    paths:
      - tests/infrastructure/report.html
```

### Jenkins
```groovy
stage('Infrastructure Tests') {
    steps {
        sh '''
            cd tests/infrastructure
            pip install -r requirements.txt
            pytest -v --integration --html=report.html
        '''
    }
    post {
        always {
            publishHTML([
                reportDir: 'tests/infrastructure',
                reportFiles: 'report.html',
                reportName: 'Infrastructure Security Report'
            ])
        }
    }
}
```

## Filtering and Selection Examples

### 1. Run Tests by Keyword
```bash
# All DDoS-related tests
pytest -k ddos -v

# All rate limiting tests
pytest -k rate_limit -v

# All Cloud Armor tests
pytest -k cloud_armor -v
```

### 2. Exclude Tests
```bash
# Run all except slow tests
pytest -v -m "not slow"

# Skip VPC Service Control tests
pytest -v -k "not service_control"
```

### 3. Run Failed Tests Only
```bash
# First run
pytest -v

# Re-run only failed tests
pytest -v --lf

# Re-run failed tests first, then all
pytest -v --ff
```

## Output Format Examples

### 1. JSON Output
```bash
pytest -v --json-report --json-report-file=results.json
cat results.json | jq '.summary'
```

### 2. JUnit XML (for CI)
```bash
pytest -v --junit-xml=results.xml
```

### 3. Quiet Output
```bash
# Show only summary
pytest -q

# Show only failures
pytest -v --tb=no
```

## Debugging Examples

### 1. Enter Debugger on Failure
```bash
pytest -v --pdb
```

### 2. Stop on First Failure
```bash
pytest -v -x
```

### 3. Show Print Statements
```bash
pytest -v -s
```

### 4. Increase Verbosity
```bash
# More verbose
pytest -vv

# Maximum verbosity
pytest -vvv
```

## Performance Examples

### 1. Show Slowest Tests
```bash
pytest -v --durations=10
```

### 2. Set Timeout
```bash
pytest -v --timeout=30
```

### 3. Run Tests Continuously
```bash
# Re-run tests on file changes (requires pytest-watch)
pip install pytest-watch
ptw -- -v
```

## Environment-Specific Examples

### 1. Test Staging Environment
```bash
export GCP_PROJECT_ID="my-project-staging"
export GCP_REGION="us-central1"
pytest -v --integration
```

### 2. Test Production (Read-Only)
```bash
export GCP_PROJECT_ID="my-project-prod"
export GCP_REGION="us-east1"
pytest -v --integration
```

### 3. Multi-Region Testing
```bash
for region in us-central1 us-east1 europe-west1; do
    echo "Testing region: $region"
    export GCP_REGION=$region
    pytest -v --integration
done
```

## Reporting Examples

### 1. Email Report on Failure
```bash
pytest -v || mail -s "Infrastructure Tests Failed" team@example.com < report.html
```

### 2. Slack Notification
```bash
pytest -v --json-report
if [ $? -ne 0 ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"Infrastructure tests failed!"}' \
        $SLACK_WEBHOOK_URL
fi
```

### 3. Generate Custom Report
```bash
pytest -v --json-report --json-report-file=report.json
python3 << EOF
import json
with open('report.json') as f:
    data = json.load(f)
    print(f"Total: {data['summary']['total']}")
    print(f"Passed: {data['summary']['passed']}")
    print(f"Failed: {data['summary']['failed']}")
EOF
```

## Real-World Workflow Examples

### 1. Pre-Deployment Check
```bash
#!/bin/bash
# Run before deploying infrastructure changes

echo "Running pre-deployment security checks..."

cd tests/infrastructure
pytest -v --integration

if [ $? -eq 0 ]; then
    echo "✓ All security checks passed. Safe to deploy."
    exit 0
else
    echo "✗ Security checks failed. Fix issues before deploying."
    exit 1
fi
```

### 2. Post-Deployment Validation
```bash
#!/bin/bash
# Run after infrastructure deployment

echo "Validating deployed infrastructure..."

# Wait for infrastructure to stabilize
sleep 30

# Run tests
cd tests/infrastructure
pytest -v --integration --html=validation_report.html

# Archive report
mv validation_report.html /reports/$(date +%Y%m%d_%H%M%S)_validation.html
```

### 3. Scheduled Compliance Check
```bash
#!/bin/bash
# Run daily via cron: 0 2 * * * /path/to/script.sh

cd /home/user/A2A/tests/infrastructure

# Run tests
pytest -v --integration --html=daily_report.html

# If failures, send alert
if [ $? -ne 0 ]; then
    echo "Security compliance check failed" | \
    mail -s "ALERT: Infrastructure Security Issues" \
         -a daily_report.html \
         security-team@example.com
fi
```

## Troubleshooting Examples

### 1. Verbose Debugging
```bash
# Maximum debugging output
pytest -vvv -s -l --tb=long test_network_policies.py::test_default_deny_all_policy_exists
```

### 2. Check Test Discovery
```bash
# See which tests are found
pytest --collect-only

# See test setup/teardown
pytest --setup-show
```

### 3. Dry Run
```bash
# Don't actually run tests, just show what would run
pytest --collect-only -q
```

## Best Practices

1. **Always run before deploying**: Catch issues early
2. **Run in CI/CD**: Automate security validation
3. **Generate reports**: Track security posture over time
4. **Fix failures immediately**: Don't ignore test failures
5. **Update tests**: Keep tests current with infrastructure changes
6. **Use markers**: Organize tests by category
7. **Parallel execution**: Speed up test runs
8. **Archive results**: Maintain audit trail

## Quick Reference

```bash
# Complete test suite
pytest -v

# Single category
pytest test_network_policies.py -v

# With report
pytest -v --html=report.html

# In parallel
pytest -v -n auto

# Integration tests
pytest -v --integration

# Specific marker
pytest -m firewall -v

# Stop on first failure
pytest -v -x

# Re-run failures
pytest -v --lf
```
