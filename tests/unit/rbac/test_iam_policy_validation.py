"""
IAM Policy Validation Tests

Tests for validating GCP IAM policies, role assignments, and permission boundaries.
Ensures compliance with security best practices and organizational policies.
"""

import pytest
import re
from pathlib import Path
from typing import Dict, List, Set


class TestIAMRoleAssignments:
    """Test IAM role assignments and permissions"""

    @pytest.fixture
    def service_accounts_tf(self) -> str:
        """Load service accounts Terraform configuration"""
        tf_path = Path("/home/user/A2A/terraform/service_accounts.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    @pytest.fixture
    def security_policies_tf(self) -> str:
        """Load security policies Terraform configuration"""
        tf_path = Path("/home/user/A2A/terraform/security_policies.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def extract_iam_bindings(self, terraform_content: str) -> List[Dict[str, str]]:
        """Extract IAM bindings from Terraform content"""
        bindings = []
        pattern = r'resource "google_project_iam_member" "(\w+)"[\s\S]*?role\s*=\s*"([^"]+)"[\s\S]*?member\s*=\s*"([^"]+)"'
        matches = re.finditer(pattern, terraform_content)
        for match in matches:
            bindings.append({
                "name": match.group(1),
                "role": match.group(2),
                "member": match.group(3)
            })
        return bindings

    def test_all_service_accounts_have_logging(self, service_accounts_tf):
        """Test that all service accounts have logging permissions"""
        # Extract service accounts
        sa_pattern = r'resource "google_service_account" "(\w+)"'
        service_accounts = re.findall(sa_pattern, service_accounts_tf)

        # Extract logging bindings
        logging_bindings = [b for b in self.extract_iam_bindings(service_accounts_tf)
                           if "logging" in b["role"]]

        # Should have at least one logging binding per service account
        # (excluding deployer which may not need logging)
        app_service_accounts = [sa for sa in service_accounts if sa != "marketplace_deployer"]
        assert len(logging_bindings) >= len(app_service_accounts)

    def test_all_service_accounts_have_monitoring(self, service_accounts_tf):
        """Test that all service accounts have monitoring permissions"""
        monitoring_bindings = [b for b in self.extract_iam_bindings(service_accounts_tf)
                              if "monitoring" in b["role"]]
        # Should have at least 3 monitoring bindings for app, api, and worker
        assert len(monitoring_bindings) >= 3

    def test_storage_permissions_are_scoped(self, service_accounts_tf):
        """Test that storage permissions are appropriately scoped"""
        storage_bindings = [b for b in self.extract_iam_bindings(service_accounts_tf)
                           if "storage" in b["role"]]

        # Check that app has read-only (viewer) access
        app_storage = [b for b in storage_bindings if "a2a_app" in b["name"]]
        for binding in app_storage:
            assert "objectViewer" in binding["role"] or "viewer" in binding["role"].lower()

        # API and worker should have admin access
        api_storage = [b for b in storage_bindings if "a2a_api" in b["name"]]
        for binding in api_storage:
            assert "objectAdmin" in binding["role"] or "admin" in binding["role"].lower()

    def test_database_access_restricted(self, service_accounts_tf):
        """Test that database access is restricted to API service account"""
        cloudsql_bindings = [b for b in self.extract_iam_bindings(service_accounts_tf)
                            if "cloudsql" in b["role"]]

        # Only API should have CloudSQL access
        for binding in cloudsql_bindings:
            assert "a2a_api" in binding["name"], \
                f"CloudSQL access should only be granted to API service account, found: {binding['name']}"

    def test_pubsub_access_restricted(self, service_accounts_tf):
        """Test that Pub/Sub access is restricted to worker service account"""
        pubsub_bindings = [b for b in self.extract_iam_bindings(service_accounts_tf)
                          if "pubsub" in b["role"]]

        # Only worker should have Pub/Sub access
        for binding in pubsub_bindings:
            assert "a2a_worker" in binding["name"], \
                f"Pub/Sub access should only be granted to worker service account, found: {binding['name']}"

    def test_no_owner_or_editor_roles(self, service_accounts_tf):
        """Test that no service accounts have owner or editor roles"""
        bindings = self.extract_iam_bindings(service_accounts_tf)
        for binding in bindings:
            assert "owner" not in binding["role"].lower(), \
                f"Service account should not have owner role: {binding}"
            assert binding["role"] != "roles/editor", \
                f"Service account should not have editor role: {binding}"

    def test_workload_identity_configured_for_all_sas(self, service_accounts_tf):
        """Test that workload identity is configured for all service accounts"""
        # Extract service accounts
        sa_pattern = r'resource "google_service_account" "(\w+)"'
        service_accounts = re.findall(sa_pattern, service_accounts_tf)

        # Extract workload identity bindings
        wi_pattern = r'resource "google_service_account_iam_member" "(\w+)_workload_identity"'
        wi_bindings = re.findall(wi_pattern, service_accounts_tf)

        # Each service account should have a workload identity binding
        assert len(wi_bindings) == len(service_accounts), \
            f"Expected {len(service_accounts)} workload identity bindings, found {len(wi_bindings)}"

    def test_service_account_naming_follows_convention(self, service_accounts_tf):
        """Test that service accounts follow naming conventions"""
        sa_pattern = r'account_id\s*=\s*"\$\{var\.deployment_name\}-([^"]+)"'
        account_ids = re.findall(sa_pattern, service_accounts_tf)

        # Should have consistent naming
        expected_patterns = ["a2a-app", "a2a-api", "a2a-worker", "deployer"]
        for account_id in account_ids:
            assert any(pattern in account_id for pattern in expected_patterns), \
                f"Service account ID should follow naming convention: {account_id}"


class TestOrganizationPolicies:
    """Test organization-level security policies"""

    @pytest.fixture
    def security_policies_tf(self) -> str:
        """Load security policies"""
        tf_path = Path("/home/user/A2A/terraform/security_policies.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def test_service_account_key_creation_disabled(self, security_policies_tf):
        """Test that service account key creation is disabled"""
        assert "iam.disableServiceAccountKeyCreation" in security_policies_tf

        # Find and verify it's enforced
        pattern = r'constraint = "iam\.disableServiceAccountKeyCreation"[\s\S]{0,100}enforced = true'
        assert re.search(pattern, security_policies_tf), \
            "Service account key creation should be enforced"

    def test_domain_restricted_sharing(self, security_policies_tf):
        """Test that domain restricted sharing is configured"""
        assert "iam.allowedPolicyMemberDomains" in security_policies_tf

    def test_os_login_required(self, security_policies_tf):
        """Test that OS Login is required"""
        assert "compute.requireOsLogin" in security_policies_tf
        pattern = r'constraint = "compute\.requireOsLogin"[\s\S]{0,100}enforced = true'
        assert re.search(pattern, security_policies_tf), "OS Login should be enforced"

    def test_serial_port_access_disabled(self, security_policies_tf):
        """Test that serial port access is disabled"""
        assert "compute.disableSerialPortAccess" in security_policies_tf

    def test_shielded_vms_required(self, security_policies_tf):
        """Test that shielded VMs are required"""
        assert "compute.requireShieldedVm" in security_policies_tf

    def test_external_ips_restricted(self, security_policies_tf):
        """Test that external IPs are restricted"""
        assert "compute.vmExternalIpAccess" in security_policies_tf

    def test_uniform_bucket_access_enforced(self, security_policies_tf):
        """Test that uniform bucket-level access is enforced"""
        assert "storage.uniformBucketLevelAccess" in security_policies_tf

    def test_cloudsql_public_ip_restricted(self, security_policies_tf):
        """Test that CloudSQL public IP is restricted"""
        assert "sql.restrictPublicIp" in security_policies_tf

    def test_binary_authorization_configured(self, security_policies_tf):
        """Test that Binary Authorization is configured"""
        assert "google_binary_authorization_policy" in security_policies_tf
        assert "REQUIRE_ATTESTATION" in security_policies_tf
        assert "ENFORCED_BLOCK_AND_AUDIT_LOG" in security_policies_tf

    def test_audit_logging_enabled(self, security_policies_tf):
        """Test that audit logging is enabled"""
        assert "google_project_iam_audit_config" in security_policies_tf
        assert "ADMIN_READ" in security_policies_tf
        assert "DATA_READ" in security_policies_tf
        assert "DATA_WRITE" in security_policies_tf


class TestSecretManagement:
    """Test secret management and access controls"""

    @pytest.fixture
    def security_policies_tf(self) -> str:
        """Load security policies"""
        tf_path = Path("/home/user/A2A/terraform/security_policies.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    @pytest.fixture
    def values_yaml(self) -> str:
        """Load Helm values"""
        values_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/values.yaml")
        with open(values_path, 'r') as f:
            return f.read()

    def test_secret_manager_configured(self, security_policies_tf):
        """Test that Secret Manager is configured"""
        assert "google_secret_manager_secret" in security_policies_tf

    def test_secret_access_controlled(self, security_policies_tf):
        """Test that secret access is controlled via IAM"""
        assert "google_secret_manager_secret_iam_member" in security_policies_tf
        assert "roles/secretmanager.secretAccessor" in security_policies_tf

    def test_secrets_not_hardcoded(self, values_yaml):
        """Test that secrets are not hardcoded in values"""
        # All secret values should be empty or reference external secret management
        assert 'password: ""' in values_yaml or 'password:' not in values_yaml
        assert 'secretKey: ""' in values_yaml or 'secretKey:' not in values_yaml

        # Check for external secret management comments
        assert "external secret management" in values_yaml.lower()

    def test_secret_replication_configured(self, security_policies_tf):
        """Test that secret replication is configured"""
        if "google_secret_manager_secret" in security_policies_tf:
            assert "replication" in security_policies_tf


class TestPermissionBoundaries:
    """Test permission boundaries and least privilege"""

    @pytest.fixture
    def service_accounts_tf(self) -> str:
        """Load service accounts configuration"""
        tf_path = Path("/home/user/A2A/terraform/service_accounts.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def get_service_account_roles(self, sa_name: str, terraform_content: str) -> Set[str]:
        """Get all roles assigned to a service account"""
        roles = set()
        pattern = f'resource "google_project_iam_member" "{sa_name}_\\w+"[\\s\\S]*?role\\s*=\\s*"([^"]+)"'
        matches = re.finditer(pattern, terraform_content)
        for match in matches:
            roles.add(match.group(1))
        return roles

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

    def test_api_service_account_has_necessary_permissions(self, service_accounts_tf):
        """Test that API service account has necessary permissions"""
        api_roles = self.get_service_account_roles("a2a_api", service_accounts_tf)

        required_roles = [
            "roles/logging.logWriter",
            "roles/monitoring.metricWriter",
            "roles/cloudsql.client",
            "roles/storage.objectAdmin"
        ]

        for role in required_roles:
            assert role in api_roles, f"API service account should have {role}"

    def test_worker_service_account_has_queue_access(self, service_accounts_tf):
        """Test that worker service account has queue access"""
        worker_roles = self.get_service_account_roles("a2a_worker", service_accounts_tf)

        # Should have Pub/Sub access for queue processing
        pubsub_roles = [r for r in worker_roles if "pubsub" in r]
        assert len(pubsub_roles) > 0, "Worker should have Pub/Sub access"

    def test_no_redundant_permissions(self, service_accounts_tf):
        """Test that there are no redundant permission grants"""
        # Extract all IAM bindings
        pattern = r'resource "google_project_iam_member" "(\w+)"'
        bindings = re.findall(pattern, service_accounts_tf)

        # Check for duplicates
        unique_bindings = set(bindings)
        assert len(bindings) == len(unique_bindings), \
            f"Found redundant IAM bindings: {set(b for b in bindings if bindings.count(b) > 1)}"


class TestWorkloadIdentity:
    """Test Workload Identity configuration"""

    @pytest.fixture
    def service_accounts_tf(self) -> str:
        """Load service accounts configuration"""
        tf_path = Path("/home/user/A2A/terraform/service_accounts.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def test_workload_identity_format(self, service_accounts_tf):
        """Test that workload identity bindings use correct format"""
        wi_pattern = r'serviceAccount:\$\{var\.project_id\}\.svc\.id\.goog\[\$\{var\.k8s_namespace\}/([^\]]+)\]'
        matches = re.findall(wi_pattern, service_accounts_tf)

        # Should have workload identity for each service account
        assert len(matches) >= 3

        # Check naming
        expected_names = ["a2a-app", "a2a-api", "a2a-worker", "marketplace-deployer"]
        for match in matches:
            assert any(name in match for name in expected_names), \
                f"Unexpected workload identity binding: {match}"

    def test_workload_identity_role(self, service_accounts_tf):
        """Test that workload identity uses correct role"""
        assert "roles/iam.workloadIdentityUser" in service_accounts_tf

        # Each workload identity binding should use this role
        wi_binding_count = service_accounts_tf.count("google_service_account_iam_member")
        role_count = service_accounts_tf.count("roles/iam.workloadIdentityUser")

        # Should have at least 4 workload identity role assignments
        assert role_count >= 4

    def test_workload_identity_namespace_scoped(self, service_accounts_tf):
        """Test that workload identity is namespace-scoped"""
        assert "var.k8s_namespace" in service_accounts_tf

        # Each workload identity should reference the namespace variable
        wi_pattern = r'resource "google_service_account_iam_member" "\w+_workload_identity"'
        wi_count = len(re.findall(wi_pattern, service_accounts_tf))

        namespace_refs = service_accounts_tf.count("var.k8s_namespace")
        assert namespace_refs >= wi_count


class TestComplianceValidation:
    """Test compliance with security standards"""

    @pytest.fixture
    def security_policies_tf(self) -> str:
        """Load security policies"""
        tf_path = Path("/home/user/A2A/terraform/security_policies.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def test_network_security_configured(self, security_policies_tf):
        """Test that network security is configured"""
        # Should have network policies
        assert "NetworkPolicy" in security_policies_tf or "network_policy" in security_policies_tf

    def test_container_scanning_enabled(self, security_policies_tf):
        """Test that container scanning is enabled"""
        assert "containerscanning.googleapis.com" in security_policies_tf or \
               "containeranalysis.googleapis.com" in security_policies_tf

    def test_security_posture_enabled(self, security_policies_tf):
        """Test that GKE security posture is enabled"""
        if "security_posture_config" in security_policies_tf:
            assert "vulnerability_mode" in security_policies_tf

    def test_workload_identity_enabled_in_cluster(self, security_policies_tf):
        """Test that workload identity is enabled in the cluster"""
        assert "workload_identity_config" in security_policies_tf
        assert "workload_pool" in security_policies_tf

    def test_shielded_nodes_enabled(self, security_policies_tf):
        """Test that shielded nodes are enabled"""
        assert "enable_shielded_nodes = true" in security_policies_tf


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
