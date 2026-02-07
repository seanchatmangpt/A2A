"""Pytest configuration for infrastructure tests."""

import os
import pytest
from typing import Generator


def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers",
        "network_policy: tests for Kubernetes network policies"
    )
    config.addinivalue_line(
        "markers",
        "firewall: tests for GCP firewall rules"
    )
    config.addinivalue_line(
        "markers",
        "vpc: tests for VPC connectivity"
    )
    config.addinivalue_line(
        "markers",
        "cloud_armor: tests for Cloud Armor security policies"
    )
    config.addinivalue_line(
        "markers",
        "integration: integration tests requiring live infrastructure"
    )
    config.addinivalue_line(
        "markers",
        "slow: slow running tests"
    )


@pytest.fixture(scope="session")
def gcp_project_id() -> str:
    """Get GCP project ID from environment."""
    project_id = os.getenv("GCP_PROJECT_ID")
    if not project_id:
        pytest.skip("GCP_PROJECT_ID environment variable not set")
    return project_id


@pytest.fixture(scope="session")
def gcp_region() -> str:
    """Get GCP region from environment."""
    return os.getenv("GCP_REGION", "us-central1")


@pytest.fixture(scope="session")
def cluster_name() -> str:
    """Get GKE cluster name from environment."""
    return os.getenv("GKE_CLUSTER_NAME", "a2a-gke")


@pytest.fixture(scope="session")
def vpc_network_name() -> str:
    """Get VPC network name from environment."""
    return os.getenv("VPC_NETWORK_NAME", "a2a-vpc")


@pytest.fixture(autouse=True)
def check_gcp_credentials():
    """Check if GCP credentials are available."""
    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS") and \
       not os.getenv("GCP_PROJECT_ID"):
        pytest.skip(
            "GCP credentials not found. Set GOOGLE_APPLICATION_CREDENTIALS "
            "or run 'gcloud auth application-default login'"
        )


def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers based on test names."""
    for item in items:
        # Add markers based on test file names
        if "network_policy" in item.nodeid:
            item.add_marker(pytest.mark.network_policy)
            item.add_marker(pytest.mark.integration)

        if "firewall" in item.nodeid:
            item.add_marker(pytest.mark.firewall)
            item.add_marker(pytest.mark.integration)

        if "vpc" in item.nodeid:
            item.add_marker(pytest.mark.vpc)
            item.add_marker(pytest.mark.integration)

        if "cloud_armor" in item.nodeid.lower():
            item.add_marker(pytest.mark.cloud_armor)
            item.add_marker(pytest.mark.integration)


@pytest.fixture(scope="session")
def test_config() -> dict:
    """Load test configuration."""
    return {
        "project_id": os.getenv("GCP_PROJECT_ID"),
        "region": os.getenv("GCP_REGION", "us-central1"),
        "cluster_name": os.getenv("GKE_CLUSTER_NAME", "a2a-gke"),
        "vpc_network": os.getenv("VPC_NETWORK_NAME", "a2a-vpc"),
        "run_integration_tests": os.getenv("RUN_INTEGRATION_TESTS", "false").lower() == "true",
    }


def pytest_addoption(parser):
    """Add custom command line options."""
    parser.addoption(
        "--integration",
        action="store_true",
        default=False,
        help="Run integration tests that require live infrastructure"
    )
    parser.addoption(
        "--gcp-project",
        action="store",
        default=None,
        help="GCP project ID to use for testing"
    )
    parser.addoption(
        "--gcp-region",
        action="store",
        default="us-central1",
        help="GCP region to use for testing"
    )


def pytest_runtest_setup(item):
    """Setup for each test run."""
    # Skip integration tests unless explicitly requested
    if "integration" in item.keywords:
        if not item.config.getoption("--integration"):
            pytest.skip("Integration tests skipped (use --integration to run)")
