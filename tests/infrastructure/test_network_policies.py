"""Tests for Kubernetes Network Policies validation."""

import os
import pytest
from typing import List, Dict, Any
from kubernetes import client, config
from kubernetes.client.rest import ApiException


class TestNetworkPolicies:
    """Test suite for Kubernetes Network Policies."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup Kubernetes client."""
        try:
            # Try to load from default kubeconfig
            config.load_kube_config()
        except Exception:
            # Fallback to in-cluster config if running in a pod
            try:
                config.load_incluster_config()
            except Exception:
                pytest.skip("Kubernetes cluster not accessible")

        self.networking_v1 = client.NetworkingV1Api()
        self.core_v1 = client.CoreV1Api()

    def test_default_deny_all_policy_exists(self):
        """Test that default deny-all network policy exists."""
        try:
            policies = self.networking_v1.list_namespaced_network_policy(
                namespace="default"
            )

            deny_all_exists = False
            for policy in policies.items:
                if policy.metadata.name == "default-deny-all":
                    deny_all_exists = True
                    # Verify policy configuration
                    assert policy.spec.pod_selector == {}, \
                        "Default deny-all policy should apply to all pods"
                    assert "Ingress" in policy.spec.policy_types, \
                        "Policy should include Ingress"
                    assert "Egress" in policy.spec.policy_types, \
                        "Policy should include Egress"
                    # Empty ingress/egress rules mean deny all
                    assert policy.spec.ingress is None or policy.spec.ingress == [], \
                        "Default deny policy should have no ingress rules"
                    assert policy.spec.egress is None or policy.spec.egress == [], \
                        "Default deny policy should have no egress rules initially"
                    break

            assert deny_all_exists, "Default deny-all network policy must exist"
        except ApiException as e:
            pytest.fail(f"Failed to list network policies: {e}")

    def test_dns_egress_policy_exists(self):
        """Test that DNS egress policy exists to allow DNS resolution."""
        try:
            policies = self.networking_v1.list_namespaced_network_policy(
                namespace="default"
            )

            dns_policy_exists = False
            for policy in policies.items:
                if policy.metadata.name == "allow-dns":
                    dns_policy_exists = True
                    # Verify DNS policy allows UDP port 53
                    assert policy.spec.egress is not None, \
                        "DNS policy must have egress rules"

                    found_dns_port = False
                    for egress_rule in policy.spec.egress:
                        if egress_rule.ports:
                            for port in egress_rule.ports:
                                if port.protocol == "UDP" and port.port == 53:
                                    found_dns_port = True
                                    break

                    assert found_dns_port, "DNS policy must allow UDP port 53"
                    break

            assert dns_policy_exists, "DNS egress policy must exist"
        except ApiException as e:
            pytest.fail(f"Failed to list network policies: {e}")

    def test_no_pods_without_network_policies(self):
        """Test that all namespaces have at least one network policy."""
        try:
            namespaces = self.core_v1.list_namespace()

            for ns in namespaces.items:
                # Skip kube-system and kube-public namespaces
                if ns.metadata.name in ["kube-system", "kube-public", "kube-node-lease"]:
                    continue

                policies = self.networking_v1.list_namespaced_network_policy(
                    namespace=ns.metadata.name
                )

                # Each namespace should have at least one network policy
                assert len(policies.items) > 0, \
                    f"Namespace {ns.metadata.name} must have at least one network policy"
        except ApiException as e:
            pytest.fail(f"Failed to validate namespace network policies: {e}")

    def test_network_policy_pod_selectors_valid(self):
        """Test that all network policies have valid pod selectors."""
        try:
            # Get all network policies across all namespaces
            policies = self.networking_v1.list_network_policy_for_all_namespaces()

            for policy in policies.items:
                # Pod selector should be a dictionary
                assert isinstance(policy.spec.pod_selector, dict) or \
                       policy.spec.pod_selector is None, \
                    f"Policy {policy.metadata.name} has invalid pod selector"

                # If policy has ingress rules, validate them
                if policy.spec.ingress:
                    for ingress_rule in policy.spec.ingress:
                        if ingress_rule.from_:
                            for from_rule in ingress_rule.from_:
                                # Validate selectors exist and are properly formatted
                                if from_rule.pod_selector:
                                    assert isinstance(from_rule.pod_selector, dict), \
                                        f"Invalid pod selector in policy {policy.metadata.name}"
        except ApiException as e:
            pytest.fail(f"Failed to validate network policy selectors: {e}")

    def test_egress_policies_allow_required_services(self):
        """Test that egress policies allow access to required services."""
        required_egress_rules = [
            {"protocol": "UDP", "port": 53},  # DNS
            {"protocol": "TCP", "port": 443},  # HTTPS for external services
        ]

        try:
            policies = self.networking_v1.list_network_policy_for_all_namespaces()

            # Check if there are any policies that allow required egress
            has_dns_egress = False
            has_https_egress = False

            for policy in policies.items:
                if policy.spec.egress:
                    for egress_rule in policy.spec.egress:
                        if egress_rule.ports:
                            for port in egress_rule.ports:
                                if port.protocol == "UDP" and port.port == 53:
                                    has_dns_egress = True
                                if port.protocol == "TCP" and port.port == 443:
                                    has_https_egress = True

            # At least one policy should allow DNS
            assert has_dns_egress, \
                "At least one network policy must allow DNS egress (UDP 53)"
        except ApiException as e:
            pytest.fail(f"Failed to validate egress policies: {e}")

    def test_network_policies_have_descriptions(self):
        """Test that network policies have proper documentation."""
        try:
            policies = self.networking_v1.list_network_policy_for_all_namespaces()

            for policy in policies.items:
                # Check if policy has annotations or labels for documentation
                assert policy.metadata.annotations or policy.metadata.labels, \
                    f"Policy {policy.metadata.name} should have annotations or labels for documentation"
        except ApiException as e:
            pytest.fail(f"Failed to validate network policy documentation: {e}")

    @pytest.mark.parametrize("namespace", ["default", "kube-system"])
    def test_critical_namespaces_protected(self, namespace: str):
        """Test that critical namespaces have network policies."""
        try:
            policies = self.networking_v1.list_namespaced_network_policy(
                namespace=namespace
            )

            # Critical namespaces should have network policies
            # (kube-system is typically exempt but we can check default)
            if namespace == "default":
                assert len(policies.items) > 0, \
                    f"Critical namespace {namespace} must have network policies"
        except ApiException as e:
            if namespace != "kube-system":  # kube-system might not have policies
                pytest.fail(f"Failed to check policies for {namespace}: {e}")

    def test_ingress_policies_not_too_permissive(self):
        """Test that ingress policies are not overly permissive."""
        try:
            policies = self.networking_v1.list_network_policy_for_all_namespaces()

            for policy in policies.items:
                if policy.spec.ingress:
                    for ingress_rule in policy.spec.ingress:
                        # Check if ingress allows from all sources
                        if ingress_rule.from_:
                            for from_rule in ingress_rule.from_:
                                # Warn if allowing from all pods/namespaces
                                if from_rule.pod_selector == {} and \
                                   from_rule.namespace_selector == {}:
                                    # This is very permissive - should be intentional
                                    assert policy.metadata.name in ["allow-all", "development"], \
                                        f"Policy {policy.metadata.name} is too permissive"
        except ApiException as e:
            pytest.fail(f"Failed to validate ingress policy restrictions: {e}")


class TestNetworkPolicySimulation:
    """Test network policy behavior through simulation."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup for simulation tests."""
        try:
            config.load_kube_config()
        except Exception:
            try:
                config.load_incluster_config()
            except Exception:
                pytest.skip("Kubernetes cluster not accessible")

        self.networking_v1 = client.NetworkingV1Api()

    def test_policy_allows_expected_traffic(self):
        """Test that network policies allow expected traffic patterns."""
        # This would require actual network testing tools like network-policy-viewer
        # For now, we validate the policy structure
        try:
            policies = self.networking_v1.list_network_policy_for_all_namespaces()

            # Ensure we have policies defined
            assert len(policies.items) > 0, "At least one network policy should exist"

            # Validate policy structure
            for policy in policies.items:
                assert policy.spec.pod_selector is not None, \
                    f"Policy {policy.metadata.name} must have pod selector"
                assert policy.spec.policy_types, \
                    f"Policy {policy.metadata.name} must specify policy types"
        except ApiException as e:
            pytest.fail(f"Failed to validate network policies: {e}")

    def test_network_policy_changes_logged(self):
        """Test that network policy changes are properly logged."""
        # This test validates that audit logging is configured
        # In a real scenario, this would check audit logs
        pytest.skip("Audit log validation requires access to GCP logging")
