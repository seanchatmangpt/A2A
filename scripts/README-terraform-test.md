# Terraform Plan Test Script - Usage Guide

## Overview

This directory contains scripts to test Terraform plan execution with mock GCP credentials and generate detailed cost estimations for the A2A infrastructure.

## Scripts

### 1. `terraform_plan_test_v2.sh` (Recommended)
**Status:** ✅ Working
**Description:** Creates a clean test environment to validate Terraform configurations and generate cost estimates.

### 2. `terraform_plan_test.sh`
**Status:** ⚠️ Has issues with duplicate resources
**Description:** Original version (use v2 instead)

## Quick Start

```bash
# Run the test script
cd /home/user/A2A/scripts
./terraform_plan_test_v2.sh
```

## What the Script Does

1. **Checks/Installs Terraform** - Verifies Terraform is available (v1.7.0+)
2. **Creates Clean Test Environment** - Sets up `/home/user/A2A/terraform-test` with:
   - Clean `main.tf` without duplicate resources
   - `variables.tf` with all required variables
   - `outputs.tf` for resource outputs
   - `terraform.tfvars` with mock values
3. **Sets Up Mock Credentials** - Creates fake GCP service account for testing
4. **Validates Configuration** - Runs `terraform validate` to check syntax
5. **Generates Cost Estimation** - Creates detailed cost breakdown

## Generated Files

### Test Environment (`/home/user/A2A/terraform-test/`)
```
terraform-test/
├── main.tf                    # Clean Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── terraform.tfvars           # Mock variable values
├── mock-credentials.json      # Fake GCP credentials (safe to delete)
└── reports/
    ├── cost-estimation.txt    # Detailed cost analysis
    └── test-summary.txt       # Test execution summary
```

## Resources Defined

The test configuration includes:

### Networking (4 resources)
- `google_compute_network.vpc` - VPC network
- `google_compute_subnetwork.gke_subnet` - Subnet with secondary ranges
- `google_compute_router.router` - Cloud Router
- `google_compute_router_nat.nat` - Cloud NAT gateway

### Firewall (2 resources)
- `google_compute_firewall.allow_internal` - Internal communication
- `google_compute_firewall.allow_health_check` - Health check access

### Kubernetes (2 resources)
- `google_container_cluster.primary` - GKE cluster
- `google_container_node_pool.primary_nodes` - Node pool with autoscaling

**Total: 8 resources**

## Cost Summary

| Configuration | Monthly Cost | Use Case |
|--------------|--------------|----------|
| Regional Cluster (Production) | $1,407.60 | High availability production |
| Zonal Cluster (Dev/Test) | $551.40 | Development and testing |
| Optimized (Preemptible) | $262.71 | Cost-sensitive dev/test |

### Cost Breakdown (Zonal Cluster)

| Component | Monthly Cost |
|-----------|--------------|
| Cloud Router | $10.95 |
| Cloud NAT (gateway + 100GB) | $37.35 |
| GKE Cluster Management | $73.00 |
| Compute (3x n1-standard-4) | $416.10 |
| Storage (3x 100GB pd-standard) | $12.00 |
| Logging & Monitoring | $2.00 |
| **TOTAL** | **$551.40** |

## Cost Optimization Tips

1. **Use Preemptible Nodes** - Save ~80% ($288/month savings)
2. **Committed Use Discounts** - Save ~57% with 3-year commitment
3. **Right-size Machine Types** - Use e2-standard-4 instead of n1-standard-4
4. **Enable Autoscaling** - Scale to 1 node during off-hours
5. **Use Zonal Instead of Regional** - Save 67% for non-production
6. **Disable Cloud NAT for Dev** - Save $37/month if not needed
7. **Consider GKE Autopilot** - Pay only for pod resources

## Optimized Cost Scenarios

### Scenario 1: Maximum Savings (Dev/Test)
```
Configuration:
- Zonal cluster in us-central1-a
- Preemptible nodes (e2-standard-2)
- Scale to 1 node off-hours
- Public endpoints (no NAT)

Estimated Cost: $125-175/month (75% savings)
```

### Scenario 2: Balanced (Staging)
```
Configuration:
- Zonal cluster
- Standard nodes (e2-standard-4)
- Autoscaling enabled
- Cloud NAT for private access

Estimated Cost: $350-450/month (35% savings)
```

### Scenario 3: Production (High Availability)
```
Configuration:
- Regional cluster
- Standard nodes (n1-standard-4)
- 1-year committed use discount
- Full monitoring & backup

Estimated Cost: $800-900/month (with CUD)
```

## Next Steps

### View Detailed Cost Estimation
```bash
cat /home/user/A2A/terraform-test/reports/cost-estimation.txt
```

### View Test Summary
```bash
cat /home/user/A2A/terraform-test/reports/test-summary.txt
```

### Validate Terraform Configuration
```bash
cd /home/user/A2A/terraform-test
terraform fmt
terraform validate
```

### Run with Real GCP Credentials

1. Set up real GCP credentials:
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/real-service-account.json"
```

2. Update terraform.tfvars with real project ID:
```bash
cd /home/user/A2A/terraform-test
vim terraform.tfvars  # Update project_id
```

3. Run terraform plan:
```bash
terraform init
terraform plan
```

4. Apply infrastructure (if plan looks good):
```bash
terraform apply
```

### Cleanup Test Environment
```bash
rm -rf /home/user/A2A/terraform-test
```

## Troubleshooting

### Issue: Terraform not found
**Solution:** The script automatically installs Terraform v1.7.4

### Issue: Duplicate resource errors
**Solution:** Use `terraform_plan_test_v2.sh` which creates a clean environment

### Issue: Permission denied
**Solution:** Make script executable
```bash
chmod +x /home/user/A2A/scripts/terraform_plan_test_v2.sh
```

### Issue: Mock credentials causing errors
**Solution:** This is expected - the script validates configuration syntax only. Use real credentials for actual `terraform plan`

## Additional Resources

- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)
- [GKE Pricing Documentation](https://cloud.google.com/kubernetes-engine/pricing)
- [Terraform GCP Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)

## Script Features

- ✅ Automatic Terraform installation
- ✅ Mock GCP credentials generation
- ✅ Clean test environment creation
- ✅ Terraform validation
- ✅ Detailed cost estimation
- ✅ Cost optimization recommendations
- ✅ Multiple deployment scenarios
- ✅ Colored console output
- ✅ Comprehensive error handling
- ✅ Automatic cleanup

## Security Notes

- Mock credentials are fake and cannot access real GCP resources
- Mock credentials file is created in test directory only
- Script cleans up environment variables on exit
- Safe to run in any environment
- No real infrastructure is created or modified

## Performance

- Execution time: ~5-10 seconds
- Terraform installation (if needed): ~30-60 seconds
- No API calls to GCP (uses mock credentials)
- Lightweight validation only

## Support

For issues or questions:
1. Check the test-summary.txt for execution details
2. Review Terraform validation output
3. Ensure Terraform version is 1.0+
4. Verify script has execute permissions

---

**Last Updated:** 2026-02-07
**Script Version:** 2.0
**Terraform Version:** 1.7.0+
**GCP Provider Version:** ~> 5.0
