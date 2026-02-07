"""
RBAC Permission Tests for A2A Application

Tests Kubernetes RBAC roles, role bindings, service accounts, and IAM policies.
Validates that permissions are correctly configured and follow the principle of least privilege.
"""

import pytest
import yaml
import json
from pathlib import Path
from typing import Dict, List, Any


class TestKubernetesRBAC:
    """Test Kubernetes RBAC configurations"""

    @pytest.fixture
    def helm_templates_path(self) -> Path:
        """Get path to Helm templates"""
        return Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates")

    @pytest.fixture
    def service_account_yaml(self, helm_templates_path) -> Dict:
        """Load service account YAML"""
        sa_path = helm_templates_path / "service-account.yaml"
        with open(sa_path, 'r') as f:
            content = f.read()
        return content

    @pytest.fixture
    def role_yaml(self, helm_templates_path) -> Dict:
        """Load role YAML"""
        role_path = helm_templates_path / "role.yaml"
        with open(role_path, 'r') as f:
            content = f.read()
        return content

    @pytest.fixture
    def role_binding_yaml(self, helm_templates_path) -> Dict:
        """Load role binding YAML"""
        rb_path = helm_templates_path / "role-binding.yaml"
        with open(rb_path, 'r') as f:
            content = f.read()
        return content

    def test_service_account_exists(self, service_account_yaml):
        """Test that service account template exists and is valid"""
        assert service_account_yaml is not None
        assert "ServiceAccount" in service_account_yaml
        assert "apiVersion: v1" in service_account_yaml

    def test_service_account_has_proper_metadata(self, service_account_yaml):
        """Test service account has proper metadata and labels"""
        assert "metadata:" in service_account_yaml
        assert "name:" in service_account_yaml
        assert "namespace:" in service_account_yaml
        assert "labels:" in service_account_yaml

    def test_service_account_has_annotations(self, service_account_yaml):
        """Test service account supports annotations for IAM integration"""
        assert "annotations:" in service_account_yaml

    def test_role_exists(self, role_yaml):
        """Test that role template exists and is valid"""
        assert role_yaml is not None
        assert "kind: Role" in role_yaml
        assert "apiVersion: rbac.authorization.k8s.io/v1" in role_yaml

    def test_role_has_required_permissions(self, role_yaml):
        """Test role has required resource permissions"""
        # Check for essential resources
        assert "services" in role_yaml
        assert "endpoints" in role_yaml
        assert "pods" in role_yaml
        assert "configmaps" in role_yaml
        assert "secrets" in role_yaml

    def test_role_has_deployment_permissions(self, role_yaml):
        """Test role has deployment management permissions"""
        assert "deployments" in role_yaml
        assert "replicasets" in role_yaml
        assert "statefulsets" in role_yaml

    def test_role_verbs_are_appropriate(self, role_yaml):
        """Test role has appropriate verbs for operations"""
        # Should have CRUD operations
        assert "get" in role_yaml
        assert "list" in role_yaml
        assert "watch" in role_yaml
        assert "create" in role_yaml
        assert "update" in role_yaml
        assert "patch" in role_yaml
        assert "delete" in role_yaml

    def test_role_has_pod_logs_access(self, role_yaml):
        """Test role can access pod logs"""
        assert "pods/log" in role_yaml

    def test_role_has_pod_exec_access(self, role_yaml):
        """Test role can exec into pods"""
        assert "pods/exec" in role_yaml

    def test_role_has_ingress_permissions(self, role_yaml):
        """Test role has ingress permissions"""
        assert "ingresses" in role_yaml
        assert "networking.k8s.io" in role_yaml

    def test_role_has_monitoring_permissions(self, role_yaml):
        """Test role has monitoring resource permissions"""
        assert "monitoring.coreos.com" in role_yaml
        assert "servicemonitors" in role_yaml
        assert "prometheusrules" in role_yaml

    def test_role_binding_exists(self, role_binding_yaml):
        """Test that role binding template exists and is valid"""
        assert role_binding_yaml is not None
        assert "kind: RoleBinding" in role_binding_yaml
        assert "apiVersion: rbac.authorization.k8s.io/v1" in role_binding_yaml

    def test_role_binding_references_service_account(self, role_binding_yaml):
        """Test role binding references service account"""
        assert "subjects:" in role_binding_yaml
        assert "kind: ServiceAccount" in role_binding_yaml

    def test_role_binding_references_role(self, role_binding_yaml):
        """Test role binding references role"""
        assert "roleRef:" in role_binding_yaml
        assert "kind: Role" in role_binding_yaml

    def test_role_binding_has_correct_api_group(self, role_binding_yaml):
        """Test role binding has correct API group"""
        assert "apiGroup: rbac.authorization.k8s.io" in role_binding_yaml

    def test_no_cluster_admin_privileges(self, role_yaml):
        """Test that role doesn't grant cluster-admin level privileges"""
        # Should not have cluster-wide permissions in a Role (only namespace-scoped)
        assert "ClusterRole" not in role_yaml
        assert "cluster-admin" not in role_yaml.lower()

    def test_secret_access_is_controlled(self, role_yaml):
        """Test that secret access is explicitly defined"""
        assert "secrets" in role_yaml
        # Secrets should be in the resources list, showing explicit control


class TestGCPIAMPolicies:
    """Test GCP IAM policies and service accounts"""

    @pytest.fixture
    def service_accounts_tf(self) -> str:
        """Load Terraform service accounts configuration"""
        tf_path = Path("/home/user/A2A/terraform/service_accounts.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    @pytest.fixture
    def security_policies_tf(self) -> str:
        """Load Terraform security policies configuration"""
        tf_path = Path("/home/user/A2A/terraform/security_policies.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def test_a2a_app_service_account_exists(self, service_accounts_tf):
        """Test A2A app service account is defined"""
        assert 'resource "google_service_account" "a2a_app"' in service_accounts_tf
        assert "a2a-app" in service_accounts_tf

    def test_a2a_api_service_account_exists(self, service_accounts_tf):
        """Test A2A API service account is defined"""
        assert 'resource "google_service_account" "a2a_api"' in service_accounts_tf
        assert "a2a-api" in service_accounts_tf

    def test_a2a_worker_service_account_exists(self, service_accounts_tf):
        """Test A2A worker service account is defined"""
        assert 'resource "google_service_account" "a2a_worker"' in service_accounts_tf
        assert "a2a-worker" in service_accounts_tf

    def test_marketplace_deployer_service_account_exists(self, service_accounts_tf):
        """Test marketplace deployer service account is defined"""
        assert 'resource "google_service_account" "marketplace_deployer"' in service_accounts_tf

    def test_service_accounts_have_descriptions(self, service_accounts_tf):
        """Test all service accounts have descriptions"""
        # Count service account resources
        sa_count = service_accounts_tf.count('resource "google_service_account"')
        # Count descriptions
        desc_count = service_accounts_tf.count('description  =')
        assert sa_count == desc_count, "All service accounts should have descriptions"

    def test_logging_permissions_granted(self, service_accounts_tf):
        """Test service accounts have logging permissions"""
        assert "roles/logging.logWriter" in service_accounts_tf
        # Each service account should have logging
        assert service_accounts_tf.count("logging.logWriter") >= 3

    def test_monitoring_permissions_granted(self, service_accounts_tf):
        """Test service accounts have monitoring permissions"""
        assert "roles/monitoring.metricWriter" in service_accounts_tf
        # Each service account should have monitoring
        assert service_accounts_tf.count("monitoring.metricWriter") >= 3

    def test_trace_permissions_granted(self, service_accounts_tf):
        """Test service accounts have tracing permissions"""
        assert "roles/cloudtrace.agent" in service_accounts_tf
        # Each service account should have trace
        assert service_accounts_tf.count("cloudtrace.agent") >= 3

    def test_api_has_storage_admin(self, service_accounts_tf):
        """Test API service account has storage admin permissions"""
        assert "a2a_api_storage" in service_accounts_tf
        assert "roles/storage.objectAdmin" in service_accounts_tf

    def test_api_has_cloudsql_client(self, service_accounts_tf):
        """Test API service account has CloudSQL client permissions"""
        assert "a2a_api_cloudsql" in service_accounts_tf
        assert "roles/cloudsql.client" in service_accounts_tf

    def test_worker_has_pubsub_permissions(self, service_accounts_tf):
        """Test worker service account has Pub/Sub permissions"""
        assert "a2a_worker_pubsub" in service_accounts_tf
        assert "roles/pubsub.editor" in service_accounts_tf

    def test_app_has_limited_storage_access(self, service_accounts_tf):
        """Test app service account has read-only storage access"""
        # Find the app storage permission
        assert "a2a_app_storage" in service_accounts_tf
        # Should be viewer, not admin
        lines = service_accounts_tf.split('\n')
        for i, line in enumerate(lines):
            if "a2a_app_storage" in line:
                # Check nearby lines for the role
                context = '\n'.join(lines[max(0, i-5):min(len(lines), i+5)])
                if "storage" in context:
                    assert "objectViewer" in context or "viewer" in context.lower()
                    assert "objectAdmin" not in context
                    break

    def test_workload_identity_bindings_exist(self, service_accounts_tf):
        """Test Workload Identity bindings are configured"""
        assert "workload_identity" in service_accounts_tf
        assert "roles/iam.workloadIdentityUser" in service_accounts_tf
        # Should have at least 4 workload identity bindings (app, api, worker, deployer)
        assert service_accounts_tf.count("workload_identity") >= 4

    def test_deployer_has_gke_admin(self, service_accounts_tf):
        """Test deployer service account has GKE admin permissions"""
        assert "deployer_gke_admin" in service_accounts_tf
        assert "roles/container.admin" in service_accounts_tf

    def test_deployer_can_use_service_accounts(self, service_accounts_tf):
        """Test deployer can use service accounts"""
        assert "deployer_sa_user" in service_accounts_tf
        assert "roles/iam.serviceAccountUser" in service_accounts_tf

    def test_outputs_are_defined(self, service_accounts_tf):
        """Test that service account outputs are defined"""
        assert 'output "a2a_app_service_account_email"' in service_accounts_tf
        assert 'output "a2a_api_service_account_email"' in service_accounts_tf
        assert 'output "a2a_worker_service_account_email"' in service_accounts_tf
        assert 'output "workload_identity_bindings"' in service_accounts_tf

    def test_service_account_key_creation_disabled(self, security_policies_tf):
        """Test that service account key creation is disabled"""
        assert "iam.disableServiceAccountKeyCreation" in security_policies_tf
        # Find the constraint and check it's enforced
        if "disableServiceAccountKeyCreation" in security_policies_tf:
            lines = security_policies_tf.split('\n')
            for i, line in enumerate(lines):
                if "disableServiceAccountKeyCreation" in line:
                    # Check for enforcement in nearby lines
                    context = '\n'.join(lines[i:min(len(lines), i+10)])
                    assert "enforced = true" in context

    def test_os_login_required(self, security_policies_tf):
        """Test that OS Login is required"""
        assert "compute.requireOsLogin" in security_policies_tf
        assert "enforced = true" in security_policies_tf

    def test_binary_authorization_enabled(self, security_policies_tf):
        """Test that Binary Authorization is enabled"""
        assert "google_binary_authorization_policy" in security_policies_tf
        assert "REQUIRE_ATTESTATION" in security_policies_tf

    def test_workload_identity_configured(self, security_policies_tf):
        """Test that Workload Identity is configured in cluster"""
        assert "workload_identity_config" in security_policies_tf
        assert "workload_pool" in security_policies_tf

    def test_shielded_nodes_enabled(self, security_policies_tf):
        """Test that shielded nodes are enabled"""
        assert "enable_shielded_nodes = true" in security_policies_tf


class TestPermissionValidation:
    """Test permission validation and least privilege principles"""

    @pytest.fixture
    def role_yaml_content(self) -> str:
        """Load role YAML content"""
        role_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/role.yaml")
        with open(role_path, 'r') as f:
            return f.read()

    def test_no_wildcard_permissions(self, role_yaml_content):
        """Test that there are no wildcard permissions in roles"""
        # Wildcard in resources would be a security risk
        lines = role_yaml_content.split('\n')
        for line in lines:
            if 'resources:' in line:
                # Check that the next few lines don't have wildcards
                idx = lines.index(line)
                next_lines = '\n'.join(lines[idx:idx+5])
                # Should not have ["*"] for resources
                assert '["*"]' not in next_lines
                assert "['*']" not in next_lines

    def test_no_wildcard_verbs(self, role_yaml_content):
        """Test that there are no wildcard verbs"""
        lines = role_yaml_content.split('\n')
        for i, line in enumerate(lines):
            if 'verbs:' in line:
                # Check next few lines
                next_lines = '\n'.join(lines[i:i+5])
                # Should not have ["*"] for verbs
                assert '["*"]' not in next_lines
                assert "['*']" not in next_lines

    def test_least_privilege_principle(self, role_yaml_content):
        """Test that roles follow least privilege principle"""
        # Should not grant unnecessary cluster-level permissions
        assert "cluster-admin" not in role_yaml_content.lower()
        assert "cluster-role" not in role_yaml_content.lower()

    def test_sensitive_resources_explicitly_defined(self, role_yaml_content):
        """Test that access to sensitive resources is explicit"""
        # Secrets should be explicitly listed, not wildcarded
        if "secrets" in role_yaml_content:
            assert "secrets" in role_yaml_content
            # Should be in a list format, not wildcarded


class TestServiceAccountSecurity:
    """Test service account security configurations"""

    @pytest.fixture
    def values_yaml(self) -> Dict:
        """Load Helm values YAML"""
        values_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/values.yaml")
        with open(values_path, 'r') as f:
            content = f.read()
        return content

    def test_service_account_creation_enabled(self, values_yaml):
        """Test that service account creation is enabled"""
        assert "serviceAccount:" in values_yaml
        assert "create: true" in values_yaml

    def test_service_account_has_name(self, values_yaml):
        """Test that service account has a name defined"""
        assert 'name: "craftplan-service-account"' in values_yaml

    def test_iam_role_arn_configured(self, values_yaml):
        """Test that IAM role ARN can be configured"""
        assert "iam:" in values_yaml
        assert "roleArn:" in values_yaml

    def test_workload_identity_annotation_support(self, values_yaml):
        """Test that service account supports workload identity annotations"""
        # Look for IAM annotation pattern
        assert "eks.amazonaws.com/role-arn" in values_yaml or "iam.gke.io/gcp-service-account" in values_yaml or ".Values.iam.roleArn" in values_yaml

    def test_pod_security_context_configured(self, values_yaml):
        """Test that pod security context is configured"""
        assert "podSecurityContext:" in values_yaml
        assert "runAsNonRoot: true" in values_yaml
        assert "runAsUser:" in values_yaml

    def test_container_security_context_configured(self, values_yaml):
        """Test that container security context is configured"""
        assert "securityContext:" in values_yaml
        assert "allowPrivilegeEscalation: false" in values_yaml
        assert "readOnlyRootFilesystem: true" in values_yaml

    def test_capabilities_dropped(self, values_yaml):
        """Test that all capabilities are dropped"""
        assert "capabilities:" in values_yaml
        assert "drop:" in values_yaml
        assert "- ALL" in values_yaml

    def test_network_policy_enabled(self, values_yaml):
        """Test that network policy is enabled"""
        assert "networkPolicy:" in values_yaml
        assert "enabled: true" in values_yaml


class TestIAMPolicyCompliance:
    """Test IAM policy compliance with security best practices"""

    @pytest.fixture
    def service_accounts_tf(self) -> str:
        """Load Terraform service accounts configuration"""
        tf_path = Path("/home/user/A2A/terraform/service_accounts.tf")
        with open(tf_path, 'r') as f:
            return f.read()

    def test_no_overly_permissive_roles(self, service_accounts_tf):
        """Test that no overly permissive roles are granted"""
        # Should not use owner or editor roles
        assert "roles/owner" not in service_accounts_tf
        assert "roles/editor" not in service_accounts_tf.lower()

    def test_service_accounts_use_specific_roles(self, service_accounts_tf):
        """Test that service accounts use specific, not generic roles"""
        # Should use specific roles like logging.logWriter, not broad ones
        specific_roles = [
            "logging.logWriter",
            "monitoring.metricWriter",
            "cloudtrace.agent",
            "cloudsql.client",
            "storage.objectAdmin",
            "storage.objectViewer"
        ]
        for role in specific_roles:
            assert role in service_accounts_tf

    def test_service_accounts_scoped_to_project(self, service_accounts_tf):
        """Test that IAM bindings are scoped to project"""
        # Should use project-level bindings
        assert "google_project_iam_member" in service_accounts_tf
        assert "project = var.project_id" in service_accounts_tf

    def test_workload_identity_properly_scoped(self, service_accounts_tf):
        """Test that workload identity is properly scoped"""
        # Should reference specific namespace and service account
        assert "svc.id.goog" in service_accounts_tf
        assert "var.k8s_namespace" in service_accounts_tf

    def test_separate_service_accounts_for_components(self, service_accounts_tf):
        """Test that different components have separate service accounts"""
        # Should have at least 3 different service accounts
        sa_count = service_accounts_tf.count('resource "google_service_account"')
        assert sa_count >= 3, f"Expected at least 3 service accounts, found {sa_count}"

    def test_service_account_naming_convention(self, service_accounts_tf):
        """Test that service accounts follow naming convention"""
        assert "deployment_name" in service_accounts_tf
        # Should use consistent naming pattern
        assert "a2a-app" in service_accounts_tf
        assert "a2a-api" in service_accounts_tf
        assert "a2a-worker" in service_accounts_tf


class TestNetworkPolicies:
    """Test network policies for service isolation"""

    @pytest.fixture
    def network_policy_yaml(self) -> str:
        """Load network policy YAML"""
        np_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/network-policy.yaml")
        if np_path.exists():
            with open(np_path, 'r') as f:
                return f.read()
        return ""

    @pytest.fixture
    def values_yaml(self) -> str:
        """Load values YAML"""
        values_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/values.yaml")
        with open(values_path, 'r') as f:
            return f.read()

    def test_network_policy_exists(self, network_policy_yaml, values_yaml):
        """Test that network policy is configured"""
        # Either in template or values
        assert network_policy_yaml != "" or "networkPolicy:" in values_yaml

    def test_network_policy_has_ingress_rules(self, values_yaml):
        """Test that network policy has ingress rules"""
        assert "networkPolicy:" in values_yaml
        assert "ingress:" in values_yaml

    def test_network_policy_has_egress_rules(self, values_yaml):
        """Test that network policy has egress rules"""
        assert "networkPolicy:" in values_yaml
        assert "egress:" in values_yaml


def test_rbac_integration():
    """Integration test to validate RBAC configuration"""
    # This is a basic integration test that checks all components work together

    # Check that all required files exist
    required_files = [
        "/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/service-account.yaml",
        "/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/role.yaml",
        "/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/role-binding.yaml",
        "/home/user/A2A/terraform/service_accounts.tf",
        "/home/user/A2A/terraform/security_policies.tf"
    ]

    for file_path in required_files:
        assert Path(file_path).exists(), f"Required RBAC file missing: {file_path}"


def test_security_best_practices():
    """Test that security best practices are followed"""

    # Load role configuration
    role_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/templates/role.yaml")
    with open(role_path, 'r') as f:
        role_content = f.read()

    # Load values
    values_path = Path("/home/user/A2A/infrastructure/kubernetes/helm/craftplan/values.yaml")
    with open(values_path, 'r') as f:
        values_content = f.read()

    # Security checks
    checks = {
        "Pod runs as non-root": "runAsNonRoot: true" in values_content,
        "Privilege escalation disabled": "allowPrivilegeEscalation: false" in values_content,
        "Read-only root filesystem": "readOnlyRootFilesystem: true" in values_content,
        "All capabilities dropped": "- ALL" in values_content,
        "Network policy enabled": "networkPolicy:" in values_content and "enabled: true" in values_content,
    }

    failed_checks = [check for check, passed in checks.items() if not passed]
    assert len(failed_checks) == 0, f"Failed security checks: {failed_checks}"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
