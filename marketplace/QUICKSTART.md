# GCP Marketplace Integration Tests - Quick Start

## Files Location
All files are in: `/home/user/A2A/marketplace/`

## Quick Commands

### 1. Run Demo (No GCP Required)
```bash
cd /home/user/A2A/marketplace
./test_runner_demo.sh
```

### 2. Run Real Integration Tests
```bash
cd /home/user/A2A/marketplace
./run_integration_tests.sh \
  --project-id YOUR_GCP_PROJECT \
  --deployment-name YOUR_DEPLOYMENT_NAME
```

### 3. Get Help
```bash
./run_integration_tests.sh --help
python3 integration_test.py --help
```

### 4. View Documentation
```bash
cat INTEGRATION_TESTS.md
```

## What Gets Tested (25 Tests)
- ✓ Network (VPC, subnets, firewall)
- ✓ IAM (service accounts, policies)
- ✓ GKE (cluster, nodes, health)
- ✓ Cloud SQL (database, connectivity)
- ✓ Kubernetes (deployments, pods, services, configmaps, secrets, HPA)
- ✓ Application (health, logs)
- ✓ Security (contexts, RBAC, policies, limits)
- ✓ Storage (persistent volumes)
- ✓ Load Balancer (external access)

## Output
- Console: Real-time colored output
- JSON: `/tmp/gcp_marketplace_integration_test_report_*.json`
- Log: `/tmp/gcp_marketplace_integration_test.log`

## Exit Codes
- 0 = Success (all critical tests passed)
- 1 = Failure (one or more tests failed)

## Requirements
- python3, gcloud, kubectl, jq
- `pip install -r requirements-integration.txt`

## Files
1. `integration_test.py` - Main test suite (25 tests)
2. `run_integration_tests.sh` - Production runner
3. `test_runner_demo.sh` - Demo runner (no GCP needed)
4. `requirements-integration.txt` - Python deps
5. `INTEGRATION_TESTS.md` - Full documentation
6. `QUICKSTART.md` - This file

Created: 2026-02-07
Total: 1,944 lines of code
