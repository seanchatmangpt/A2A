# RBAC Test Suite

Comprehensive test suite for validating Role-Based Access Control (RBAC), IAM policies, service accounts, and security permissions in the A2A application.

## Overview

This test suite validates:
- **Kubernetes RBAC**: Roles, RoleBindings, and ServiceAccounts
- **GCP IAM Policies**: Service account permissions and role assignments
- **Workload Identity**: Kubernetes-to-GCP service account bindings
- **Security Best Practices**: Least privilege, no wildcard permissions, security contexts
- **Compliance**: Organization policies, network policies, and security controls

## Test Files

### `test_rbac_permissions.py`
Primary test file covering Kubernetes RBAC and GCP IAM basics.

**Test Classes:**
- `TestKubernetesRBAC`: Validates Kubernetes RBAC configurations (17 tests)
- `TestGCPIAMPolicies`: Validates GCP service accounts and IAM bindings (21 tests)
- `TestPermissionValidation`: Validates least privilege and permission boundaries (4 tests)
- `TestServiceAccountSecurity`: Validates security contexts and pod security (8 tests)
- `TestIAMPolicyCompliance`: Validates IAM compliance with best practices (6 tests)
- `TestNetworkPolicies`: Validates network isolation policies (3 tests)

### `test_iam_policy_validation.py`
Advanced IAM policy validation and compliance testing.

**Test Classes:**
- `TestIAMRoleAssignments`: Validates role assignments and scoping (8 tests)
- `TestOrganizationPolicies`: Validates organization-level security policies (10 tests)
- `TestSecretManagement`: Validates secret management and access controls (4 tests)
- `TestPermissionBoundaries`: Validates least privilege principle (4 tests)
- `TestWorkloadIdentity`: Validates Workload Identity configuration (3 tests)
- `TestComplianceValidation`: Validates security compliance (5 tests)

## Running Tests

### Run All RBAC Tests
```bash
cd /home/user/A2A
pytest tests/unit/rbac/ -v
```

### Run Specific Test File
```bash
pytest tests/unit/rbac/test_rbac_permissions.py -v
pytest tests/unit/rbac/test_iam_policy_validation.py -v
```

### Run Specific Test Class
```bash
pytest tests/unit/rbac/test_rbac_permissions.py::TestKubernetesRBAC -v
pytest tests/unit/rbac/test_iam_policy_validation.py::TestOrganizationPolicies -v
```

### Run Specific Test
```bash
pytest tests/unit/rbac/test_rbac_permissions.py::TestKubernetesRBAC::test_role_has_required_permissions -v
```

### Run with Coverage
```bash
pytest tests/unit/rbac/ -v --cov=. --cov-report=html
```

### Run Tests Using Shell Script
```bash
./tests/run_rbac_tests.sh
```

## Test Coverage

Total: **95 tests** covering:

### Kubernetes RBAC (17 tests)
- ✓ Service account creation and metadata
- ✓ Role permissions (services, pods, configmaps, secrets)
- ✓ Deployment management permissions
- ✓ Pod logs and exec access
- ✓ Ingress and monitoring permissions
- ✓ Role bindings and API groups
- ✓ No cluster-admin privileges

### GCP IAM Policies (21 tests)
- ✓ Service account existence and descriptions
- ✓ Logging, monitoring, and tracing permissions
- ✓ Storage access (scoped by service account)
- ✓ CloudSQL client access
- ✓ Pub/Sub permissions for workers
- ✓ Workload Identity bindings
- ✓ Deployer permissions
- ✓ Binary authorization
- ✓ Security policies

### Permission Validation (4 tests)
- ✓ No wildcard permissions or verbs
- ✓ Least privilege principle
- ✓ Explicit resource definitions

### Service Account Security (8 tests)
- ✓ Pod security context (runAsNonRoot)
- ✓ Container security context
- ✓ Privilege escalation disabled
- ✓ Read-only root filesystem
- ✓ All capabilities dropped
- ✓ Network policies enabled

### IAM Policy Compliance (6 tests)
- ✓ No overly permissive roles (owner, editor)
- ✓ Specific roles (not generic)
- ✓ Project-scoped bindings
- ✓ Proper Workload Identity scoping
- ✓ Separate service accounts per component
- ✓ Naming conventions

### Organization Policies (10 tests)
- ✓ Service account key creation disabled
- ✓ Domain-restricted sharing
- ✓ OS Login required
- ✓ Serial port access disabled
- ✓ Shielded VMs required
- ✓ External IPs restricted
- ✓ Uniform bucket access
- ✓ CloudSQL public IP restricted
- ✓ Binary authorization
- ✓ Audit logging enabled

### Secret Management (4 tests)
- ✓ Secret Manager configured
- ✓ IAM-controlled secret access
- ✓ No hardcoded secrets
- ✓ Secret replication

### Workload Identity (3 tests)
- ✓ Correct format and namespace scoping
- ✓ Proper IAM role assignment
- ✓ Namespace-scoped bindings

## Security Validations

### What Gets Validated

1. **Least Privilege Principle**
   - Service accounts have minimal required permissions
   - No wildcard permissions (*) in roles
   - No cluster-admin or overly broad roles

2. **Separation of Concerns**
   - App service account: read-only storage access
   - API service account: database and storage admin
   - Worker service account: Pub/Sub and queue access
   - Deployer service account: deployment permissions only

3. **Workload Identity**
   - All service accounts have Workload Identity bindings
   - Bindings are namespace-scoped
   - Proper IAM role (workloadIdentityUser)

4. **Pod Security**
   - Pods run as non-root
   - Privilege escalation disabled
   - Read-only root filesystem
   - All Linux capabilities dropped

5. **Network Security**
   - Network policies enabled
   - Ingress and egress rules defined
   - Service isolation

6. **Secret Management**
   - Secrets stored in Secret Manager
   - Access controlled via IAM
   - No hardcoded secrets in configuration

7. **Compliance**
   - Binary authorization enabled
   - Container vulnerability scanning
   - Audit logging enabled
   - Organization policies enforced

## Test Examples

### Example: Testing Kubernetes Role Permissions
```python
def test_role_has_required_permissions(self, role_yaml):
    """Test role has required resource permissions"""
    assert "services" in role_yaml
    assert "endpoints" in role_yaml
    assert "pods" in role_yaml
    assert "configmaps" in role_yaml
    assert "secrets" in role_yaml
```

### Example: Testing IAM Least Privilege
```python
def test_app_service_account_least_privilege(self, service_accounts_tf):
    """Test that app service account has minimal permissions"""
    app_roles = self.get_service_account_roles("a2a_app", service_accounts_tf)

    # Should have basic observability permissions
    assert "roles/logging.logWriter" in app_roles
    assert "roles/monitoring.metricWriter" in app_roles

    # Should have read-only storage
    storage_roles = [r for r in app_roles if "storage" in r]
    for role in storage_roles:
        assert "viewer" in role.lower() or "reader" in role.lower()
```

### Example: Testing Workload Identity
```python
def test_workload_identity_configured_for_all_sas(self, service_accounts_tf):
    """Test that workload identity is configured for all service accounts"""
    sa_pattern = r'resource "google_service_account" "(\w+)"'
    service_accounts = re.findall(sa_pattern, service_accounts_tf)

    wi_pattern = r'resource "google_service_account_iam_member" "(\w+)_workload_identity"'
    wi_bindings = re.findall(wi_pattern, service_accounts_tf)

    # Each service account should have a workload identity binding
    assert len(wi_bindings) == len(service_accounts)
```

## Files Tested

### Kubernetes Resources
- `/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/service-account.yaml`
- `/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/role.yaml`
- `/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/role-binding.yaml`
- `/home/user/A2A/infrastructure/kubernetes/helm/craftplan/values.yaml`

### Terraform Configurations
- `/home/user/A2A/terraform/service_accounts.tf`
- `/home/user/A2A/terraform/security_policies.tf`

## CI/CD Integration

Add to your CI/CD pipeline:

```yaml
- name: Run RBAC Tests
  run: |
    pytest tests/unit/rbac/ -v --tb=short
```

## Troubleshooting

### All tests pass locally but fail in CI
- Ensure all required files are committed to version control
- Check that file paths are absolute in fixtures

### Tests fail after updating RBAC configs
- Review the test assertions to ensure they match your updated configuration
- Update test expectations if intentional changes were made

### Coverage warnings
- These tests validate configuration files, not application code
- Coverage metrics may not be applicable
- Use `--no-cov` flag to disable coverage reporting

## Best Practices

1. **Run tests before committing RBAC changes**
   ```bash
   pytest tests/unit/rbac/ -v
   ```

2. **Add tests for new service accounts**
   - Add to `test_a2a_*_service_account_exists` pattern
   - Validate permissions follow least privilege

3. **Validate security changes**
   - Run security-specific test classes
   - Ensure no regressions in security posture

4. **Document intentional permission changes**
   - Update test assertions if permissions are intentionally broadened
   - Add comments explaining why

## Contributing

When adding new RBAC configurations:

1. Add corresponding tests to validate the configuration
2. Follow existing test patterns and naming conventions
3. Ensure tests validate both positive and negative cases
4. Document any security implications

## Related Documentation

- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [GCP IAM Documentation](https://cloud.google.com/iam/docs)
- [Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

## Support

For questions or issues with the RBAC test suite:
1. Check test output for specific failures
2. Review the test documentation in this README
3. Examine the configuration files being tested
4. Consult the main project documentation
