"""
Test configuration management for Craftplan MCP + A2A Integration

This module provides configuration management for the test suite:
- Environment variable handling
- Test configuration loading
- Test environment setup
- Configuration validation
"""

import os
import json
from pathlib import Path
from typing import Dict, Any, Optional

import pytest
from pydantic import BaseSettings, Field
from pydantic_settings import BaseSettings


class TestSettings(BaseSettings):
    """Test environment settings"""

    # MCP Server configuration
    mcp_host: str = Field(default="localhost", env="MCP_HOST")
    mcp_port: int = Field(default=8090, env="MCP_PORT")
    mcp_url: str = Field(default="http://localhost:8090", env="MCP_URL")

    # A2A Agent configuration
    a2a_host: str = Field(default="localhost", env="A2A_HOST")
    a2a_port: int = Field(default=8080, env="A2A_PORT")
    a2a_url: str = Field(default="http://localhost:8080", env="A2A_URL")

    # elrmcp configuration
    elrmcp_host: str = Field(default="localhost", env="ELRMCP_HOST")
    elrmcp_port: int = Field(default=9090, env="ELRMCP_PORT")
    elrmcp_url: str = Field(default="http://localhost:9090", env="ELRMCP_URL")

    # Test configuration
    test_timeout: int = Field(default=30, env="TEST_TIMEOUT")
    retry_attempts: int = Field(default=3, env="RETRY_ATTEMPTS")
    debug_mode: bool = Field(default=False, env="DEBUG_MODE")
    parallel_tests: bool = Field(default=True, env="PARALLEL_TESTS")
    coverage_threshold: float = Field(default=0.8, env="COVERAGE_THRESHOLD")

    # Mock services
    mock_enabled: bool = Field(default=True, env="MOCK_ENABLED")
    mock_host: str = Field(default="localhost", env="MOCK_HOST")
    mock_port: int = Field(default=9876, env="MOCK_PORT")

    # Performance testing
    performance_enabled: bool = Field(default=False, env="PERFORMANCE_ENABLED")
    load_test_users: int = Field(default=10, env="LOAD_TEST_USERS")
    load_test_duration: int = Field(default=60, env="LOAD_TEST_DURATION")

    # Security testing
    security_enabled: bool = Field(default=True, env="SECURITY_ENABLED")
    security_scan_level: str = Field(default="normal", env="SECURITY_SCAN_LEVEL")

    # API authentication
    api_token: Optional[str] = Field(default=None, env="API_TOKEN")
    api_auth_header: str = Field(default="Authorization", env="API_AUTH_HEADER")

    class Config:
        env_file = ".env.test"
        env_file_encoding = "utf-8"

    @property
    def mcp_health_url(self) -> str:
        """Get MCP health check URL"""
        return f"{self.mcp_url}/health"

    @property
    def a2a_health_url(self) -> str:
        """Get A2A health check URL"""
        return f"{self.a2a_url}/health"

    @property
    def elrmcp_health_url(self) -> str:
        """Get elrmcp health check URL"""
        return f"{self.elrmcp_url}/health"

    @property
    def agent_card_url(self) -> str:
        """Get agent card URL"""
        return f"{self.a2a_url}/.well-known/agent-card"

    @property
    def mock_api_url(self) -> str:
        """Get mock API URL"""
        return f"http://{self.mock_host}:{self.mock_port}"

    def get_services_urls(self) -> Dict[str, str]:
        """Get all service URLs"""
        return {
            "mcp": self.mcp_url,
            "a2a": self.a2a_url,
            "elrmcp": self.elrmcp_url,
            "mock": self.mock_api_url,
            "health": {
                "mcp": self.mcp_health_url,
                "a2a": self.a2a_health_url,
                "elrmcp": self.elrmcp_health_url
            },
            "agent_card": self.agent_card_url
        }

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "mcp_host": self.mcp_host,
            "mcp_port": self.mcp_port,
            "mcp_url": self.mcp_url,
            "a2a_host": self.a2a_host,
            "a2a_port": self.a2a_port,
            "a2a_url": self.a2a_url,
            "elrmcp_host": self.elrmcp_host,
            "elrmcp_port": self.elrmcp_port,
            "elrmcp_url": self.elrmcp_url,
            "test_timeout": self.test_timeout,
            "retry_attempts": self.retry_attempts,
            "debug_mode": self.debug_mode,
            "parallel_tests": self.parallel_tests,
            "coverage_threshold": self.coverage_threshold,
            "mock_enabled": self.mock_enabled,
            "mock_host": self.mock_host,
            "mock_port": self.mock_port,
            "performance_enabled": self.performance_enabled,
            "load_test_users": self.load_test_users,
            "load_test_duration": self.load_test_duration,
            "security_enabled": self.security_enabled,
            "security_scan_level": self.security_scan_level,
            "api_token": self.api_token,
            "api_auth_header": self.api_auth_header
        }


class TestEnvironment:
    """Test environment management"""

    def __init__(self, settings: TestSettings):
        self.settings = settings
        self.services = {}
        self.mock_services = {}

    def setup(self):
        """Setup test environment"""
        print("Setting up test environment...")

        # Check if services are available
        self.check_service_availability()

        # Start mock services if enabled
        if self.settings.mock_enabled:
            self.start_mock_services()

        print("Test environment setup complete")

    def teardown(self):
        """Teardown test environment"""
        print("Tearing down test environment...")

        # Stop mock services
        self.stop_mock_services()

        print("Test environment teardown complete")

    def check_service_availability(self):
        """Check if required services are available"""
        import httpx
        import asyncio

        async def check_services():
            async with httpx.AsyncClient(timeout=10.0) as client:
                services_to_check = [
                    ("MCP", self.settings.mcp_health_url),
                    ("A2A", self.settings.a2a_health_url),
                    ("elrmcp", self.settings.elrmcp_health_url)
                ]

                for service_name, url in services_to_check:
                    try:
                        response = await client.get(url)
                        if response.status_code == 200:
                            print(f"✓ {service_name} service is available")
                        else:
                            print(f"✗ {service_name} service returned status {response.status_code}")
                    except Exception as e:
                        print(f"✗ {service_name} service is not available: {e}")

        # Run async check
        asyncio.run(check_services())

    def start_mock_services(self):
        """Start mock services"""
        from tests.utils.mock_servers import MockMCPServer, MockA2AServer

        # Start mock MCP server
        self.mock_services["mcp"] = MockMCPServer(
            host=self.settings.mock_host,
            port=self.settings.mock_port + 1
        )
        self.mock_services["mcp"].start()

        # Start mock A2A server
        self.mock_services["a2a"] = MockA2AServer(
            host=self.settings.mock_host,
            port=self.settings.mock_port + 2
        )
        self.mock_services["a2a"].start()

        print(f"Mock services started on {self.settings.mock_host}:{self.settings.mock_port + 1} (MCP) and {self.settings.mock_port + 2} (A2A)")

    def stop_mock_services(self):
        """Stop mock services"""
        for service_name, service in self.mock_services.items():
            service.stop()
            print(f"Stopped {service_name} mock service")


@pytest.fixture(scope="session")
def test_settings():
    """Test settings fixture"""
    return TestSettings()


@pytest.fixture(scope="session")
def test_environment(test_settings):
    """Test environment fixture"""
    env = TestEnvironment(test_settings)
    env.setup()
    yield env
    env.teardown()


@pytest.fixture(scope="function")
def mock_services(test_settings):
    """Mock services fixture"""
    # Setup mock services if enabled
    if test_settings.mock_enabled:
        from tests.utils.mock_servers import MockMCPServer, MockA2AServer

        mcp_server = MockMCPServer(
            host=test_settings.mock_host,
            port=test_settings.mock_port + 1
        )
        a2a_server = MockA2AServer(
            host=test_settings.mock_host,
            port=test_settings.mock_port + 2
        )

        mcp_server.start()
        a2a_server.start()

        yield {
            "mcp": mcp_server,
            "a2a": a2a_server
        }

        # Teardown
        mcp_server.stop()
        a2a_server.stop()
    else:
        yield {}


# Configuration validation
class TestConfigurationValidator:
    """Test configuration validation"""

    @staticmethod
    def validate_test_settings(settings: TestSettings) -> bool:
        """Validate test settings"""
        errors = []

        # Validate ports
        if settings.mcp_port < 1 or settings.mcp_port > 65535:
            errors.append("Invalid MCP port")

        if settings.a2a_port < 1 or settings.a2a_port > 65535:
            errors.append("Invalid A2A port")

        if settings.elrmcp_port < 1 or settings.elrmcp_port > 65535:
            errors.append("Invalid elrmcp port")

        # Validate coverage threshold
        if settings.coverage_threshold < 0 or settings.coverage_threshold > 1:
            errors.append("Coverage threshold must be between 0 and 1")

        # Validate load test parameters
        if settings.performance_enabled and settings.load_test_users < 1:
            errors.append("Load test users must be at least 1")

        if settings.performance_enabled and settings.load_test_duration < 1:
            errors.append("Load test duration must be at least 1 second")

        if errors:
            raise ValueError(f"Configuration validation failed: {', '.join(errors)}")

        return True

    @staticmethod
    def validate_service_urls(urls: Dict[str, str]) -> bool:
        """Validate service URLs"""
        required_urls = ["mcp", "a2a", "elrmcp"]

        for url_name in required_urls:
            if url_name not in urls:
                raise ValueError(f"Missing required URL: {url_name}")

            url = urls[url_name]
            if not url.startswith(("http://", "https://")):
                raise ValueError(f"Invalid URL format for {url_name}: {url}")

        return True


# Global configuration instance
test_config = TestSettings()