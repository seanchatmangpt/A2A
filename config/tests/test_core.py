"""
Tests for configuration core classes.
"""

import pytest
from dataclasses import dataclass

from config.core import (
    BaseConfig,
    Config,
    ServerConfig,
    LogConfig,
    SecurityConfig,
    DatabaseConfig,
    MCPConfig,
    A2AConfig,
    BridgeConfig,
    Environment,
)


class TestBaseConfig:
    """Test BaseConfig functionality."""

    def test_from_dict(self):
        """Test creating config from dictionary."""
        @dataclass
        class TestConfig(BaseConfig):
            name: str
            value: int

        data = {"name": "test", "value": 42}
        config = TestConfig.from_dict(data)

        assert config.name == "test"
        assert config.value == 42
        assert config.config_version == "0.1.0"

    def test_to_dict(self):
        """Test converting config to dictionary."""
        @dataclass
        class TestConfig(BaseConfig):
            name: str
            value: int

        config = TestConfig(name="test", value=42)
        data = config.to_dict()

        assert data["name"] == "test"
        assert data["value"] == 42
        assert data["config_version"] == "0.1.0"

    def test_to_json(self):
        """Test converting config to JSON string."""
        @dataclass
        class TestConfig(BaseConfig):
            name: str

        config = TestConfig(name="test")
        json_str = config.to_json()

        assert "name" in json_str
        assert "test" in json_str
        assert "config_version" in json_str

    def test_validate_empty(self):
        """Test empty validation."""
        config = BaseConfig()
        errors = config.validate()

        assert isinstance(errors, list)


class TestConfig:
    """Test main Config class."""

    def test_config_creation(self):
        """Test creating a complete configuration."""
        config = Config()

        assert config.environment == Environment.DEVELOPMENT
        assert config.config_version == "0.1.0"
        assert isinstance(config.server, ServerConfig)
        assert isinstance(config.logging, LogConfig)
        assert isinstance(config.security, SecurityConfig)
        assert isinstance(config.database, DatabaseConfig)
        assert isinstance(config.mcp, MCPConfig)
        assert isinstance(config.a2a, A2AConfig)
        assert isinstance(config.bridge, BridgeConfig)

    def test_validate_valid_config(self):
        """Test validating a valid configuration."""
        config = Config()
        errors = config.validate()

        # Should have some warnings about missing credentials
        assert isinstance(errors, list)

    def test_validate_invalid_config(self):
        """Test validating an invalid configuration."""
        config = Config()
        # Remove required security credentials
        config.security.jwt_secret = None
        config.security.api_key = None

        errors = config.validate()

        # Should have security errors
        assert len(errors) > 0
        assert any("security" in error for error in errors)

    def test_custom_config(self):
        """Test custom configuration."""
        config = Config()
        config.custom_config["test_key"] = "test_value"

        assert config.custom_config["test_key"] == "test_value"


class TestServerConfig:
    """Test ServerConfig class."""

    def test_default_values(self):
        """Test default configuration values."""
        config = ServerConfig()

        assert config.host == "localhost"
        assert config.port == 8080
        assert config.max_connections == 100
        assert config.timeout == 30
        assert config.ssl_enabled is False

    def test_port_validation(self):
        """Test port validation."""
        config = ServerConfig(port=9001)
        errors = config.validate()

        assert isinstance(errors, list)

    def test_invalid_port(self):
        """Test invalid port validation."""
        config = ServerConfig(port=70000)
        errors = config.validate()

        assert len(errors) > 0


class TestLogConfig:
    """Test LogConfig class."""

    def test_default_values(self):
        """Test default log configuration."""
        config = LogConfig()

        assert config.level == "INFO"
        assert isinstance(config.format, str)
        assert config.file is None
        assert config.max_size == 10485760
        assert config.backup_count == 5
        assert config.json_format is False

    def test_level_validation(self):
        """Test log level validation."""
        config = LogConfig(level="DEBUG")
        errors = config.validate()

        # Should not have errors for DEBUG level
        assert len(errors) == 0

    def test_invalid_level(self):
        """Test invalid log level."""
        config = LogConfig(level="INVALID")
        errors = config.validate()

        assert len(errors) > 0
        assert "Invalid logging level" in errors[0]


class TestSecurityConfig:
    """Test SecurityConfig class."""

    def test_no_auth(self):
        """Test configuration without authentication."""
        config = SecurityConfig()
        errors = config.validate()

        # Should have error about missing authentication
        assert len(errors) > 0
        assert "Either JWT secret or API key must be configured" in errors[0]

    def test_jwt_auth(self):
        """Test JWT authentication."""
        config = SecurityConfig(jwt_secret="test-secret")
        errors = config.validate()

        # Should be valid with JWT secret
        assert len(errors) == 0

    def test_api_key_auth(self):
        """Test API key authentication."""
        config = SecurityConfig(api_key="test-api-key")
        errors = config.validate()

        # Should be valid with API key
        assert len(errors) == 0

    def test_both_auth(self):
        """Test both authentication methods."""
        config = SecurityConfig(
            jwt_secret="test-secret",
            api_key="test-api-key"
        )
        errors = config.validate()

        # Should be valid with both
        assert len(errors) == 0


class TestDatabaseConfig:
    """Test DatabaseConfig class."""

    def test_minimal_config(self):
        """Test minimal database configuration."""
        config = DatabaseConfig(name="test_db")
        errors = config.validate()

        # Should be valid with just name
        assert len(errors) == 0

    def test_full_config(self):
        """Test full database configuration."""
        config = DatabaseConfig(
            url="postgresql://user:pass@localhost/db",
            host="localhost",
            port=5432,
            name="test_db",
            username="user",
            password="pass"
        )
        errors = config.validate()

        # Should be valid
        assert len(errors) == 0

    def test_invalid_config(self):
        """Test invalid database configuration."""
        config = DatabaseConfig()
        errors = config.validate()

        # Should have error about missing configuration
        assert len(errors) > 0


class TestMCPConfig:
    """Test MCPConfig class."""

    def test_default_values(self):
        """Test default MCP configuration."""
        config = MCPConfig()

        assert config.server_name == "craftplan-mcp"
        assert config.host == "localhost"
        assert config.port == 9000
        assert config.protocol_version == "2024-11-05"

    def test_validation(self):
        """Test MCP configuration validation."""
        config = MCPConfig(
            server_name="test-server",
            host="example.com",
            port=9001
        )
        errors = config.validate()

        # Should be valid
        assert len(errors) == 0


class TestA2AConfig:
    """Test A2AConfig class."""

    def test_default_values(self):
        """Test default A2A configuration."""
        config = A2AConfig()

        assert config.agent_name == "a2a-agent"
        assert config.namespace == "default"
        assert config.service_url == "http://localhost:8081"
        assert config.event_bus_url == "http://localhost:8082"

    def test_validation(self):
        """Test A2A configuration validation."""
        config = A2AConfig(
            agent_name="test-agent",
            namespace="test-namespace",
            service_url="http://example.com/service"
        )
        errors = config.validate()

        # Should be valid
        assert len(errors) == 0


class TestBridgeConfig:
    """Test BridgeConfig class."""

    def test_default_values(self):
        """Test default bridge configuration."""
        config = BridgeConfig()

        assert config.auto_start is True
        assert config.heartbeat_interval == 30
        assert config.max_bridge_sessions == 10
        assert config.message_queue_size == 1000
        assert config.metrics_enabled is True

    def test_validation(self):
        """Test bridge configuration validation."""
        config = BridgeConfig()
        errors = config.validate()

        # Should be valid
        assert len(errors) == 0


if __name__ == "__main__":
    pytest.main([__file__])