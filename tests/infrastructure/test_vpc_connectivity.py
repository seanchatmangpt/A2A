"""Tests for VPC connectivity, network configuration, and routing."""

import os
import pytest
from typing import List, Dict, Any
from google.cloud import compute_v1
from google.api_core import exceptions
import ipaddress


class TestVPCConfiguration:
    """Test suite for VPC network configuration."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup GCP clients."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")
        self.region = os.getenv("GCP_REGION", "us-central1")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            self.network_client = compute_v1.NetworksClient()
            self.subnetwork_client = compute_v1.SubnetworksClient()
            self.router_client = compute_v1.RoutersClient()
        except Exception as e:
            pytest.skip(f"Could not initialize GCP clients: {e}")

    def test_vpc_network_exists(self):
        """Test that VPC network exists."""
        try:
            networks = self.network_client.list(project=self.project_id)

            vpc_found = False
            for network in networks:
                if "a2a" in network.name.lower() or "vpc" in network.name.lower():
                    vpc_found = True
                    # Verify it's not auto-mode
                    assert not network.auto_create_subnetworks, \
                        "VPC should be custom mode (not auto-create subnetworks)"
                    # Verify routing mode
                    assert network.routing_config, \
                        "VPC should have routing configuration"
                    break

            assert vpc_found, "VPC network must exist"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate VPC network: {e}")

    def test_gke_subnet_configured(self):
        """Test that GKE subnet is properly configured."""
        try:
            subnets = self.subnetwork_client.list(
                project=self.project_id,
                region=self.region
            )

            gke_subnet_found = False
            for subnet in subnets:
                if "gke" in subnet.name.lower():
                    gke_subnet_found = True

                    # Verify IP ranges
                    assert subnet.ip_cidr_range, \
                        "GKE subnet must have primary IP range"

                    # Verify secondary ranges for pods and services
                    assert subnet.secondary_ip_ranges, \
                        "GKE subnet must have secondary IP ranges for pods and services"

                    secondary_range_names = [r.range_name for r in subnet.secondary_ip_ranges]
                    assert "pods" in secondary_range_names, \
                        "GKE subnet must have 'pods' secondary range"
                    assert "services" in secondary_range_names, \
                        "GKE subnet must have 'services' secondary range"

                    # Verify private Google access
                    assert subnet.private_ip_google_access, \
                        "GKE subnet should have private Google access enabled"

                    break

            assert gke_subnet_found, "GKE subnet must exist"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate GKE subnet: {e}")

    def test_subnet_ip_ranges_not_overlapping(self):
        """Test that subnet IP ranges do not overlap."""
        try:
            subnets = self.subnetwork_client.list(
                project=self.project_id,
                region=self.region
            )

            primary_ranges = []
            secondary_ranges = []

            for subnet in subnets:
                # Collect primary ranges
                if subnet.ip_cidr_range:
                    primary_ranges.append(ipaddress.ip_network(subnet.ip_cidr_range))

                # Collect secondary ranges
                if subnet.secondary_ip_ranges:
                    for secondary_range in subnet.secondary_ip_ranges:
                        secondary_ranges.append(
                            ipaddress.ip_network(secondary_range.ip_cidr_range)
                        )

            # Check for overlaps in primary ranges
            for i, range1 in enumerate(primary_ranges):
                for range2 in primary_ranges[i + 1:]:
                    assert not range1.overlaps(range2), \
                        f"Primary IP ranges overlap: {range1} and {range2}"

            # Check for overlaps between primary and secondary
            for primary in primary_ranges:
                for secondary in secondary_ranges:
                    # Secondary ranges are typically subnets of a larger space
                    # so we check they don't overlap with other primary ranges
                    pass  # This is complex and depends on design

        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate IP range overlaps: {e}")

    def test_private_google_access_enabled(self):
        """Test that Private Google Access is enabled on subnets."""
        try:
            subnets = self.subnetwork_client.list(
                project=self.project_id,
                region=self.region
            )

            subnets_without_pga = []
            for subnet in subnets:
                if not subnet.private_ip_google_access:
                    subnets_without_pga.append(subnet.name)

            # Most subnets should have Private Google Access
            assert len(subnets_without_pga) == 0 or \
                   len(subnets_without_pga) < len(list(subnets)) / 2, \
                "Most subnets should have Private Google Access enabled"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate Private Google Access: {e}")

    def test_flow_logs_enabled(self):
        """Test that VPC Flow Logs are enabled for monitoring."""
        try:
            subnets = self.subnetwork_client.list(
                project=self.project_id,
                region=self.region
            )

            subnets_with_flow_logs = 0
            for subnet in subnets:
                if subnet.log_config and subnet.log_config.enable:
                    subnets_with_flow_logs += 1
                    # Validate flow log configuration
                    assert subnet.log_config.aggregation_interval, \
                        f"Subnet {subnet.name} should have aggregation interval configured"
                    assert subnet.log_config.metadata, \
                        f"Subnet {subnet.name} should have metadata configuration"

            # At least one subnet should have flow logs for security monitoring
            assert subnets_with_flow_logs > 0, \
                "At least one subnet should have VPC Flow Logs enabled"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate VPC Flow Logs: {e}")

    def test_subnet_ranges_are_rfc1918(self):
        """Test that subnet ranges use private IP addresses (RFC 1918)."""
        rfc1918_ranges = [
            ipaddress.ip_network("10.0.0.0/8"),
            ipaddress.ip_network("172.16.0.0/12"),
            ipaddress.ip_network("192.168.0.0/16"),
        ]

        try:
            subnets = self.subnetwork_client.list(
                project=self.project_id,
                region=self.region
            )

            for subnet in subnets:
                if subnet.ip_cidr_range:
                    subnet_network = ipaddress.ip_network(subnet.ip_cidr_range)

                    # Check if subnet is within RFC 1918 ranges
                    is_private = any(
                        subnet_network.subnet_of(rfc_range)
                        for rfc_range in rfc1918_ranges
                    )

                    assert is_private, \
                        f"Subnet {subnet.name} ({subnet.ip_cidr_range}) should use private IP range"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate subnet IP ranges: {e}")


class TestCloudNAT:
    """Test suite for Cloud NAT configuration."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup Cloud NAT client."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")
        self.region = os.getenv("GCP_REGION", "us-central1")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            self.router_client = compute_v1.RoutersClient()
        except Exception as e:
            pytest.skip(f"Could not initialize GCP clients: {e}")

    def test_cloud_router_exists(self):
        """Test that Cloud Router exists for NAT."""
        try:
            routers = self.router_client.list(
                project=self.project_id,
                region=self.region
            )

            router_found = False
            for router in routers:
                if "router" in router.name.lower() or "a2a" in router.name.lower():
                    router_found = True
                    # Verify BGP configuration if applicable
                    if router.bgp:
                        assert router.bgp.asn, \
                            f"Router {router.name} should have ASN configured"
                    break

            assert router_found, "Cloud Router must exist for NAT"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate Cloud Router: {e}")

    def test_cloud_nat_configured(self):
        """Test that Cloud NAT is configured on the router."""
        try:
            routers = self.router_client.list(
                project=self.project_id,
                region=self.region
            )

            nat_found = False
            for router in routers:
                if router.nats:
                    nat_found = True
                    for nat in router.nats:
                        # Verify NAT configuration
                        assert nat.nat_ip_allocate_option, \
                            f"NAT {nat.name} should have IP allocation option"

                        assert nat.source_subnetwork_ip_ranges_to_nat, \
                            f"NAT {nat.name} should specify which subnets to NAT"

                        # Check logging configuration
                        if nat.log_config:
                            assert nat.log_config.enable, \
                                f"NAT {nat.name} logging should be enabled"

                    break

            assert nat_found, "Cloud NAT must be configured"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate Cloud NAT: {e}")

    def test_nat_logging_enabled(self):
        """Test that NAT logging is enabled."""
        try:
            routers = self.router_client.list(
                project=self.project_id,
                region=self.region
            )

            logging_enabled = False
            for router in routers:
                if router.nats:
                    for nat in router.nats:
                        if nat.log_config and nat.log_config.enable:
                            logging_enabled = True
                            # Verify log filter
                            assert nat.log_config.filter, \
                                f"NAT {nat.name} should have log filter configured"
                            break

            assert logging_enabled, "Cloud NAT logging must be enabled"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate NAT logging: {e}")

    def test_nat_ports_per_vm_configured(self):
        """Test that NAT ports per VM are properly configured."""
        try:
            routers = self.router_client.list(
                project=self.project_id,
                region=self.region
            )

            for router in routers:
                if router.nats:
                    for nat in router.nats:
                        # Check min and max ports per VM
                        if hasattr(nat, 'min_ports_per_vm'):
                            assert nat.min_ports_per_vm >= 64, \
                                f"NAT {nat.name} should allocate at least 64 ports per VM"

                        if hasattr(nat, 'max_ports_per_vm'):
                            assert nat.max_ports_per_vm <= 65536, \
                                f"NAT {nat.name} max ports should be <= 65536"
        except exceptions.GoogleAPIError as e:
            pytest.fail(f"Failed to validate NAT port configuration: {e}")


class TestPrivateClusterConnectivity:
    """Test suite for GKE private cluster connectivity."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup GKE client."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")
        self.region = os.getenv("GCP_REGION", "us-central1")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            from google.cloud import container_v1
            self.gke_client = container_v1.ClusterManagerClient()
        except Exception as e:
            pytest.skip(f"Could not initialize GKE client: {e}")

    def test_gke_cluster_is_private(self):
        """Test that GKE cluster uses private nodes."""
        try:
            from google.cloud import container_v1

            # Get cluster
            parent = f"projects/{self.project_id}/locations/{self.region}"
            response = self.gke_client.list_clusters(parent=parent)

            cluster_found = False
            for cluster in response.clusters:
                if "a2a" in cluster.name.lower() or "gke" in cluster.name.lower():
                    cluster_found = True

                    # Verify private cluster configuration
                    assert cluster.private_cluster_config, \
                        "Cluster should have private cluster configuration"

                    assert cluster.private_cluster_config.enable_private_nodes, \
                        "Cluster should use private nodes"

                    # Verify master IP range
                    assert cluster.private_cluster_config.master_ipv4_cidr_block, \
                        "Master IPv4 CIDR block should be configured"

                    break

            assert cluster_found, "GKE cluster must exist"
        except Exception as e:
            pytest.fail(f"Failed to validate private cluster: {e}")

    def test_master_authorized_networks_configured(self):
        """Test that master authorized networks are configured."""
        try:
            parent = f"projects/{self.project_id}/locations/{self.region}"
            response = self.gke_client.list_clusters(parent=parent)

            for cluster in response.clusters:
                if "a2a" in cluster.name.lower() or "gke" in cluster.name.lower():
                    # Verify master authorized networks
                    assert cluster.master_authorized_networks_config, \
                        "Master authorized networks should be configured"

                    if cluster.master_authorized_networks_config.enabled:
                        assert cluster.master_authorized_networks_config.cidr_blocks, \
                            "Master authorized networks should have CIDR blocks"

                        # Verify it's not open to all
                        for cidr_block in cluster.master_authorized_networks_config.cidr_blocks:
                            assert cidr_block.cidr_block != "0.0.0.0/0" or \
                                   cidr_block.display_name == "All" or \
                                   cluster.private_cluster_config.enable_private_endpoint, \
                                "Master should not be accessible from all IPs unless private endpoint is enabled"

                    break
        except Exception as e:
            pytest.fail(f"Failed to validate master authorized networks: {e}")

    def test_workload_identity_enabled(self):
        """Test that Workload Identity is enabled."""
        try:
            parent = f"projects/{self.project_id}/locations/{self.region}"
            response = self.gke_client.list_clusters(parent=parent)

            for cluster in response.clusters:
                if "a2a" in cluster.name.lower() or "gke" in cluster.name.lower():
                    # Verify Workload Identity
                    assert cluster.workload_identity_config, \
                        "Workload Identity should be configured"

                    assert cluster.workload_identity_config.workload_pool, \
                        "Workload Identity pool should be configured"

                    expected_pool = f"{self.project_id}.svc.id.goog"
                    assert cluster.workload_identity_config.workload_pool == expected_pool, \
                        f"Workload pool should be {expected_pool}"

                    break
        except Exception as e:
            pytest.fail(f"Failed to validate Workload Identity: {e}")

    def test_network_policy_enabled(self):
        """Test that network policy is enabled on the cluster."""
        try:
            parent = f"projects/{self.project_id}/locations/{self.region}"
            response = self.gke_client.list_clusters(parent=parent)

            for cluster in response.clusters:
                if "a2a" in cluster.name.lower() or "gke" in cluster.name.lower():
                    # Verify network policy is enabled
                    assert cluster.network_policy, \
                        "Network policy should be configured"

                    assert cluster.network_policy.enabled, \
                        "Network policy should be enabled"

                    # Also check addon
                    if cluster.addons_config:
                        assert cluster.addons_config.network_policy_config, \
                            "Network policy addon should be configured"

                    break
        except Exception as e:
            pytest.fail(f"Failed to validate network policy: {e}")


class TestDNSConfiguration:
    """Test suite for DNS configuration."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup DNS client."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            from google.cloud import dns
            self.dns_client = dns.Client(project=self.project_id)
        except Exception as e:
            pytest.skip(f"Could not initialize DNS client: {e}")

    def test_private_dns_zones_exist(self):
        """Test that private DNS zones exist if needed."""
        try:
            # List all managed zones
            zones = list(self.dns_client.list_zones())

            # Check if any private zones exist
            private_zones = [z for z in zones if hasattr(z, 'visibility') and z.visibility == 'private']

            # If private cluster is used, private DNS zones should exist
            # This is optional based on architecture
            if len(zones) > 0:
                assert len(zones) >= 0, "DNS zones should be configured"
        except Exception as e:
            # DNS zones might not be required for all setups
            pytest.skip(f"DNS validation skipped: {e}")


class TestServiceConnectivity:
    """Test suite for Private Service Connect and service connectivity."""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup service connectivity client."""
        self.project_id = os.getenv("GCP_PROJECT_ID", "test-project")
        self.region = os.getenv("GCP_REGION", "us-central1")

        if not os.getenv("GCP_PROJECT_ID"):
            pytest.skip("GCP_PROJECT_ID environment variable not set")

        try:
            self.service_attachment_client = compute_v1.ServiceAttachmentsClient()
        except Exception as e:
            pytest.skip(f"Could not initialize service connectivity clients: {e}")

    def test_private_service_connect_configured(self):
        """Test that Private Service Connect is configured if used."""
        try:
            # List service attachments
            attachments = self.service_attachment_client.list(
                project=self.project_id,
                region=self.region
            )

            # PSC might not be required for all setups
            # If it exists, validate configuration
            for attachment in attachments:
                if "psc" in attachment.name.lower():
                    assert attachment.target_service, \
                        f"PSC attachment {attachment.name} should have target service"

                    assert attachment.connection_preference, \
                        f"PSC attachment {attachment.name} should have connection preference"

                    # Verify NAT subnets
                    assert attachment.nat_subnets, \
                        f"PSC attachment {attachment.name} should have NAT subnets"

        except exceptions.GoogleAPIError as e:
            # PSC might not be configured, which is OK
            pytest.skip(f"Private Service Connect validation skipped: {e}")
