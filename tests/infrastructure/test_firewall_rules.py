"""Tests for GCP Firewall Rules and Cloud Armor policies."""

import os
import pytest
from typing import List, Dict, Any
from google.cloud import compute_v1
from google.api_core import exceptions


class TestGCPFirewallRules:
    """Test suite for GCP VPC Firewall Rules."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup GCP clients."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")
        self.network_name = os.getenv("VPC_NETWORK_NAME", "a2a-vpc")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            self.firewall_client = compute_v1.FirewallsClient()
            self.network_client = compute_v1.NetworksClient()
        except Exception as e:
            pytest.skip(f"Could not initialize GCP clients: {e}")

    def test_default_deny_all_ingress_exists(self):
        """Test that default deny-all ingress firewall rule exists."""
        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            deny_all_found = False
            for firewall in firewalls:
                if "deny-all-ingress" in firewall.name.lower():
                    deny_all_found = True
                    # Verify it's a deny rule
                    assert firewall.denied, \
                        f"Firewall {firewall.name} should be a DENY rule"
                    # Verify direction is INGRESS
                    assert firewall.direction == "INGRESS", \
                        f"Firewall {firewall.name} should be INGRESS"
                    # Verify priority (should be low priority/high number for default deny)
                    assert firewall.priority >= 65534, \
                        f"Default deny rule should have low priority (high number)"
                    # Verify source range is all IPs
                    assert "0.0.0.0/0" in firewall.source_ranges, \
                        f"Default deny should apply to all source IPs"
                    break

            assert deny_all_found, \
                "Default deny-all ingress firewall rule must exist"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to list firewall rules: {e}")

    def test_health_check_firewall_allows_gcp_ranges(self):
        """Test that health check firewall allows Google Cloud health check ranges."""
        gcp_health_check_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            health_check_rule_found = False
            for firewall in firewalls:
                if "health-check" in firewall.name.lower():
                    health_check_rule_found = True
                    # Verify it allows traffic
                    assert firewall.allowed, \
                        f"Health check firewall {firewall.name} should ALLOW traffic"

                    # Verify source ranges include GCP health check IPs
                    for hc_range in gcp_health_check_ranges:
                        assert hc_range in firewall.source_ranges, \
                            f"Health check firewall must allow {hc_range}"

                    # Verify it allows required ports (80, 443)
                    allowed_ports = []
                    for allow_rule in firewall.allowed:
                        if allow_rule.ports:
                            allowed_ports.extend(allow_rule.ports)

                    assert "80" in allowed_ports or "443" in allowed_ports, \
                        "Health check firewall should allow port 80 or 443"
                    break

            assert health_check_rule_found, \
                "Health check firewall rule must exist"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate health check firewall: {e}")

    def test_iap_access_firewall_configured(self):
        """Test that IAP (Identity-Aware Proxy) firewall is configured."""
        iap_range = "35.235.240.0/20"

        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            iap_rule_found = False
            for firewall in firewalls:
                if "iap" in firewall.name.lower():
                    iap_rule_found = True
                    # Verify IAP source range
                    assert iap_range in firewall.source_ranges, \
                        f"IAP firewall must allow IAP range {iap_range}"

                    # Verify SSH/RDP ports
                    allowed_ports = []
                    for allow_rule in firewall.allowed:
                        if allow_rule.I_TCP:
                            allowed_ports.extend(allow_rule.ports or [])

                    assert "22" in allowed_ports or "3389" in allowed_ports, \
                        "IAP firewall should allow SSH (22) or RDP (3389)"
                    break

            assert iap_rule_found, "IAP firewall rule must exist for secure access"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate IAP firewall: {e}")

    def test_internal_traffic_allowed(self):
        """Test that internal VPC traffic is allowed between resources."""
        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            internal_rule_found = False
            for firewall in firewalls:
                if "allow-internal" in firewall.name.lower():
                    internal_rule_found = True
                    # Verify it allows internal traffic
                    assert firewall.allowed, \
                        f"Internal firewall {firewall.name} should ALLOW traffic"

                    # Verify source ranges are private IP ranges
                    has_private_range = False
                    for source_range in firewall.source_ranges:
                        if source_range.startswith("10.") or \
                           source_range.startswith("172.") or \
                           source_range.startswith("192.168."):
                            has_private_range = True
                            break

                    assert has_private_range, \
                        "Internal firewall should allow private IP ranges"
                    break

            assert internal_rule_found, "Internal traffic firewall rule must exist"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate internal firewall: {e}")

    def test_firewall_rules_have_descriptions(self):
        """Test that all firewall rules have descriptions."""
        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            for firewall in firewalls:
                assert firewall.description, \
                    f"Firewall rule {firewall.name} must have a description"
                assert len(firewall.description) > 10, \
                    f"Firewall rule {firewall.name} description should be meaningful"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate firewall descriptions: {e}")

    def test_no_overly_permissive_rules(self):
        """Test that there are no overly permissive firewall rules."""
        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            for firewall in firewalls:
                # Skip the default deny rule
                if "deny" in firewall.name.lower():
                    continue

                # Check for rules that allow all ports from all IPs
                if firewall.allowed:
                    for allow_rule in firewall.allowed:
                        if allow_rule.I_P_protocol == "all" or \
                           (allow_rule.ports and "0-65535" in allow_rule.ports):
                            # If allowing all protocols/ports, source should be restricted
                            if "0.0.0.0/0" in (firewall.source_ranges or []):
                                pytest.fail(
                                    f"Firewall {firewall.name} is too permissive: "
                                    f"allows all traffic from all sources"
                                )
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate firewall permissiveness: {e}")

    def test_firewall_logging_enabled(self):
        """Test that firewall logging is enabled for important rules."""
        try:
            firewalls = self.firewall_client.list(project=self.project_id)

            rules_without_logging = []
            for firewall in firewalls:
                # Skip internal allow rules
                if "allow-internal" in firewall.name.lower():
                    continue

                if not firewall.log_config or not firewall.log_config.enable:
                    rules_without_logging.append(firewall.name)

            # Some logging should be enabled
            assert len(rules_without_logging) < len(list(firewalls)), \
                "At least some firewall rules should have logging enabled"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate firewall logging: {e}")

    def test_priority_ordering_correct(self):
        """Test that firewall rule priorities are correctly ordered."""
        try:
            firewalls = list(self.firewall_client.list(project=self.project_id))

            # Deny rules should have lower priority (higher number) than allow rules
            deny_priorities = []
            allow_priorities = []

            for firewall in firewalls:
                if firewall.denied:
                    deny_priorities.append(firewall.priority)
                elif firewall.allowed:
                    allow_priorities.append(firewall.priority)

            # Default deny should be lowest priority
            if deny_priorities:
                assert max(deny_priorities) >= 65534, \
                    "Default deny rule should have priority >= 65534"

            # Specific allow rules should have higher priority (lower number)
            if allow_priorities:
                assert min(allow_priorities) < 65534, \
                    "Allow rules should have higher priority than default deny"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate firewall priorities: {e}")


class TestCloudArmorPolicies:
    """Test suite for Cloud Armor Security Policies."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup Cloud Armor client."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            self.security_policy_client = compute_v1.SecurityPoliciesClient()
        except Exception as e:
            pytest.skip(f"Could not initialize Cloud Armor client: {e}")

    def test_cloud_armor_policy_exists(self):
        """Test that Cloud Armor security policy exists."""
        try:
            policies = self.security_policy_client.list(project=self.project_id)

            policy_found = False
            for policy in policies:
                if "a2a" in policy.name.lower() or "security" in policy.name.lower():
                    policy_found = True
                    break

            assert policy_found, "Cloud Armor security policy must exist"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to list Cloud Armor policies: {e}")

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

            assert ddos_enabled, \
                "DDoS protection (Adaptive Protection) must be enabled"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate DDoS protection: {e}")

    def test_rate_limiting_configured(self):
        """Test that rate limiting rules are configured."""
        try:
            policies = self.security_policy_client.list(project=self.project_id)

            rate_limit_found = False
            for policy in policies:
                if policy.rules:
                    for rule in policy.rules:
                        if rule.rate_limit_options:
                            rate_limit_found = True
                            # Validate rate limit configuration
                            assert rule.rate_limit_options.rate_limit_threshold, \
                                "Rate limit threshold must be configured"
                            assert rule.rate_limit_options.conform_action, \
                                "Rate limit conform action must be configured"
                            assert rule.rate_limit_options.exceed_action, \
                                "Rate limit exceed action must be configured"
                            break

            assert rate_limit_found, "Rate limiting must be configured in Cloud Armor"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate rate limiting: {e}")

    def test_owasp_protections_enabled(self):
        """Test that OWASP top 10 protections are enabled."""
        owasp_protections = [
            "sqli",  # SQL Injection
            "xss",  # Cross-Site Scripting
            "lfi",  # Local File Inclusion
            "rce",  # Remote Code Execution
            "rfi",  # Remote File Inclusion
        ]

        try:
            policies = self.security_policy_client.list(project=self.project_id)

            found_protections = set()
            for policy in policies:
                if policy.rules:
                    for rule in policy.rules:
                        if rule.match and rule.match.expr:
                            expression = rule.match.expr.expression.lower()
                            for protection in owasp_protections:
                                if protection in expression:
                                    found_protections.add(protection)

            # At least SQL injection and XSS should be protected
            assert "sqli" in found_protections, "SQL injection protection must be enabled"
            assert "xss" in found_protections, "XSS protection must be enabled"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate OWASP protections: {e}")

    def test_geo_blocking_configured(self):
        """Test that geographic blocking is configured if required."""
        try:
            policies = self.security_policy_client.list(project=self.project_id)

            for policy in policies:
                if policy.rules:
                    for rule in policy.rules:
                        if rule.match and rule.match.expr:
                            expression = rule.match.expr.expression
                            # Check if geo-blocking is configured
                            if "region_code" in expression or "country" in expression:
                                # If geo-blocking exists, verify it's a deny rule
                                assert "deny" in rule.action.lower(), \
                                    "Geo-blocking rule should deny traffic"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate geo-blocking: {e}")

    def test_default_rule_exists(self):
        """Test that each policy has a default rule."""
        try:
            policies = self.security_policy_client.list(project=self.project_id)

            for policy in policies:
                if policy.rules:
                    # Find default rule (usually highest priority number)
                    priorities = [rule.priority for rule in policy.rules]
                    assert max(priorities) == 2147483647, \
                        f"Policy {policy.name} should have default rule with priority 2147483647"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate default rules: {e}")

    def test_blocked_ip_ranges_configured(self):
        """Test that known malicious IP ranges are blocked."""
        try:
            policies = self.security_policy_client.list(project=self.project_id)

            ip_blocking_found = False
            for policy in policies:
                if policy.rules:
                    for rule in policy.rules:
                        if "deny" in rule.action.lower():
                            if rule.match and rule.match.config:
                                if rule.match.config.src_ip_ranges:
                                    ip_blocking_found = True
                                    break

            assert ip_blocking_found, \
                "Cloud Armor should have IP blocking rules configured"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate IP blocking: {e}")


class TestVPCServiceControls:
    """Test suite for VPC Service Controls."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup VPC Service Controls client."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        # VPC Service Controls require Access Context Manager API
        # This is a placeholder for actual implementation
        pytest.skip("VPC Service Controls testing requires Access Context Manager API setup")

    def test_service_perimeter_exists(self):
        """Test that VPC Service Perimeter is configured."""
        # Implementation would check for service perimeter configuration
        pass

    def test_restricted_services_configured(self):
        """Test that critical services are within the perimeter."""
        # Services that should be restricted:
        # - storage.googleapis.com
        # - bigquery.googleapis.com
        # - sqladmin.googleapis.com
        pass
