"""
Tests for configuration management
"""

import pytest
from unittest.mock import Mock, patch
import os
import json
import tempfile
from pathlib import Path

from elrmcp_bridge.src.config import (
    BridgeConfig,
    SecurityConfig,
    TransportConfig,
    AgentConfig,
    WorkflowConfig,
    MetricsConfig,
    LoggingConfig,
    ConfigValidator,
    ConfigLoader,
    ConfigManager
)


class TestBridgeConfig:
    """Test BridgeConfig class"""

    def test_bridge_config_initialization(self):
        """Test BridgeConfig initialization with defaults"""
        config = BridgeConfig()

        assert config.host == "localhost"
        assert config.port == 8001
        assert config.debug is False
        assert config.development is False
        assert config.api_enabled is True
        assert config.metrics_enabled is True
        assert config.transport_type == "websocket"
        assert config.security is not None
        assert config.transport is not None
        assert config.agent is not None
        assert config.workflow is not None
        assert config.metrics is not None
        assert config.logging is not None

    def test_bridge_config_with_values(self):
        """Test BridgeConfig with custom values"""
        security = SecurityConfig(api_key="test-key")
        transport = TransportConfig(transport_type="sse", sse_url="http://localhost:8081")
        agent = AgentConfig(discovery_interval=30)
        workflow = WorkflowConfig(max_concurrent_workflows=10)
        metrics = MetricsConfig(enabled=True, port=8000)
        logging_config = LoggingConfig(level="DEBUG")

        config = BridgeConfig(
            host="0.0.0.0",
            port=9000,
            debug=True,
            development=True,
            security=security,
            transport=transport,
            agent=agent,
            workflow=workflow,
            metrics=metrics,
            logging=logging_config
        )

        assert config.host == "0.0.0.0"
        assert config.port == 9000
        assert config.debug is True
        assert config.development is True
        assert config.security.api_key == "test-key"
        assert config.transport.transport_type == "sse"
        assert config.transport.sse_url == "http://localhost:8081"
        assert config.agent.discovery_interval == 30
        assert config.workflow.max_concurrent_workflows == 10
        assert config.metrics.port == 8000
        assert config.logging.level == "DEBUG"

    def test_bridge_config_validation(self):
        """Test BridgeConfig validation"""
        # Valid config
        config = BridgeConfig(
            host="localhost",
            port=8001,
            debug=True,
            development=True
        )

        assert config.validate() is True

        # Invalid port
        config.port = -1
        with pytest.raises(ValueError, match="Invalid port"):
            config.validate()

        # Invalid host
        config.port = 8001
        config.host = ""
        with pytest.raises(ValueError, match="Host cannot be empty"):
            config.validate()

    def test_bridge_config_to_dict(self):
        """Test BridgeConfig to dictionary conversion"""
        config = BridgeConfig(
            host="localhost",
            port=8001,
            debug=True
        )

        config_dict = config.to_dict()

        assert config_dict["host"] == "localhost"
        assert config_dict["port"] == 8001
        assert config_dict["debug"] is True
        assert "security" in config_dict
        assert "transport" in config_dict

    def test_bridge_config_from_dict(self):
        """Test BridgeConfig from dictionary creation"""
        config_dict = {
            "host": "localhost",
            "port": 8001,
            "debug": True,
            "security": {
                "api_key": "test-key"
            }
        }

        config = BridgeConfig.from_dict(config_dict)

        assert config.host == "localhost"
        assert config.port == 8001
        assert config.debug is True
        assert config.security.api_key == "test-key"


class TestSecurityConfig:
    """Test SecurityConfig class"""

    def test_security_config_initialization(self):
        """Test SecurityConfig initialization"""
        config = SecurityConfig()

        assert config.api_key is None
        assert config.auth_required is False
        assert config.allowed_origins == ["*"]
        assert config.rate_limit == 100

    def test_security_config_with_values(self):
        """Test SecurityConfig with custom values"""
        config = SecurityConfig(
            api_key="test-key",
            auth_required=True,
            allowed_origins=["http://localhost:3000"],
            rate_limit=50
        )

        assert config.api_key == "test-key"
        assert config.auth_required is True
        assert config.allowed_origins == ["http://localhost:3000"]
        assert config.rate_limit == 50

    def test_security_config_validation(self):
        """Test SecurityConfig validation"""
        # Valid config
        config = SecurityConfig(api_key="test-key")
        assert config.validate() is True

        # Empty API key when auth required
        config.auth_required = True
        config.api_key = None
        with pytest.raises(ValueError, match="API key required when auth is enabled"):
            config.validate()


class TestTransportConfig:
    """Test TransportConfig class"""

    def test_transport_config_initialization(self):
        """Test TransportConfig initialization"""
        config = TransportConfig()

        assert config.transport_type == "websocket"
        assert config.websocket_url is None
        assert config.sse_url is None
        assert config.connection_timeout == 30
        assert config.max_connections == 100

    def test_transport_config_with_values(self):
        """Test TransportConfig with custom values"""
        config = TransportConfig(
            transport_type="sse",
            websocket_url="ws://localhost:8080",
            sse_url="http://localhost:8081",
            connection_timeout=60,
            max_connections=200
        )

        assert config.transport_type == "sse"
        assert config.websocket_url == "ws://localhost:8080"
        assert config.sse_url == "http://localhost:8081"
        assert config.connection_timeout == 60
        assert config.max_connections == 200

    def test_transport_config_validation(self):
        """Test TransportConfig validation"""
        # Valid config
        config = TransportConfig(
            transport_type="websocket",
            websocket_url="ws://localhost:8080"
        )
        assert config.validate() is True

        # Invalid transport type
        config.transport_type = "invalid"
        with pytest.raises(ValueError, match="Invalid transport type"):
            config.validate()

        # Invalid URL
        config.transport_type = "websocket"
        config.websocket_url = "invalid-url"
        with pytest.raises(ValueError, match="Invalid WebSocket URL"):
            config.validate()


class TestAgentConfig:
    """Test AgentConfig class"""

    def test_agent_config_initialization(self):
        """Test AgentConfig initialization"""
        config = AgentConfig()

        assert config.discovery_interval == 60
        assert config.discovery_timeout == 30
        assert config.max_agents == 50
        assert config.agent_timeout == 300

    def test_agent_config_with_values(self):
        """Test AgentConfig with custom values"""
        config = AgentConfig(
            discovery_interval=30,
            discovery_timeout=15,
            max_agents=100,
            agent_timeout=600
        )

        assert config.discovery_interval == 30
        assert config.discovery_timeout == 15
        assert config.max_agents == 100
        assert config.agent_timeout == 600


class TestWorkflowConfig:
    """Test WorkflowConfig class"""

    def test_workflow_config_initialization(self):
        """Test WorkflowConfig initialization"""
        config = WorkflowConfig()

        assert config.max_concurrent_workflows == 5
        assert config.workflow_timeout == 600
        assert config.task_timeout == 120
        assert config.max_retries == 3

    def test_workflow_config_with_values(self):
        """Test WorkflowConfig with custom values"""
        config = WorkflowConfig(
            max_concurrent_workflows=10,
            workflow_timeout=1200,
            task_timeout=240,
            max_retries=5
        )

        assert config.max_concurrent_workflows == 10
        assert config.workflow_timeout == 1200
        assert config.task_timeout == 240
        assert config.max_retries == 5


class TestMetricsConfig:
    """Test MetricsConfig class"""

    def test_metrics_config_initialization(self):
        """Test MetricsConfig initialization"""
        config = MetricsConfig()

        assert config.enabled is False
        assert config.port == 8000
        assert config.prefix == "elrmcp_bridge"
        assert config.interval == 60

    def test_metrics_config_with_values(self):
        """Test MetricsConfig with custom values"""
        config = MetricsConfig(
            enabled=True,
            port=9000,
            prefix="custom",
            interval=30
        )

        assert config.enabled is True
        assert config.port == 9000
        assert config.prefix == "custom"
        assert config.interval == 30


class TestLoggingConfig:
    """Test LoggingConfig class"""

    def test_logging_config_initialization(self):
        """Test LoggingConfig initialization"""
        config = LoggingConfig()

        assert config.level == "INFO"
        assert config.enable_console is True
        assert config.enable_file is False
        assert config.file_path is None
        assert config.max_file_size == 10 * 1024 * 1024  # 10MB
        assert config.backup_count == 5

    def test_logging_config_with_values(self):
        """Test LoggingConfig with custom values"""
        config = LoggingConfig(
            level="DEBUG",
            enable_console=False,
            enable_file=True,
            file_path="/var/log/elrmcp_bridge.log",
            max_file_size=20 * 1024 * 1024,
            backup_count=10
        )

        assert config.level == "DEBUG"
        assert config.enable_console is False
        assert config.enable_file is True
        assert config.file_path == "/var/log/elrmcp_bridge.log"
        assert config.max_file_size == 20 * 1024 * 1024
        assert config.backup_count == 10


class TestConfigValidator:
    """Test ConfigValidator class"""

    def test_validate_required_fields(self):
        """Test validation of required fields"""
        validator = ConfigValidator()

        # Valid config
        config = BridgeConfig(host="localhost", port=8001)
        assert validator.validate_required_fields(config) is True

        # Missing required field
        config.host = None
        with pytest.raises(ValueError, match="Host is required"):
            validator.validate_required_fields(config)

    def test_validate_port_range(self):
        """Test port range validation"""
        validator = ConfigValidator()

        # Valid port
        assert validator.validate_port(8001) is True

        # Invalid port
        with pytest.raises(ValueError, match="Port must be between 1 and 65535"):
            validator.validate_port(0)

        with pytest.raises(ValueError, match="Port must be between 1 and 65535"):
            validator.validate_port(65536)

    def test_validate_url(self):
        """Test URL validation"""
        validator = ConfigValidator()

        # Valid URL
        assert validator.validate_url("http://localhost:8001") is True
        assert validator.validate_url("ws://localhost:8080") is True

        # Invalid URL
        with pytest.raises(ValueError, match="Invalid URL"):
            validator.validate_url("invalid-url")

    def test_validate_interval(self):
        """Test interval validation"""
        validator = ConfigValidator()

        # Valid interval
        assert validator.validate_interval(60) is True

        # Invalid interval
        with pytest.raises(ValueError, match="Interval must be positive"):
            validator.validate_interval(-1)


class TestConfigLoader:
    """Test ConfigLoader class"""

    def test_load_from_dict(self):
        """Test loading configuration from dictionary"""
        config_dict = {
            "host": "localhost",
            "port": 8001,
            "debug": True,
            "security": {
                "api_key": "test-key"
            },
            "transport": {
                "transport_type": "websocket"
            }
        }

        config = ConfigLoader.load_from_dict(config_dict)

        assert config.host == "localhost"
        assert config.port == 8001
        assert config.debug is True
        assert config.security.api_key == "test-key"
        assert config.transport.transport_type == "websocket"

    def test_load_from_file(self):
        """Test loading configuration from file"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            config_dict = {
                "host": "localhost",
                "port": 8001,
                "debug": True
            }
            json.dump(config_dict, f)
            f.flush()

            config = ConfigLoader.load_from_file(f.name)

            assert config.host == "localhost"
            assert config.port == 8001
            assert config.debug is True

        os.unlink(f.name)

    def test_load_from_file_not_found(self):
        """Test loading from non-existent file"""
        with pytest.raises(FileNotFoundError):
            ConfigLoader.load_from_file("/nonexistent/config.json")

    def test_load_from_env(self):
        """Test loading configuration from environment variables"""
        # Set environment variables
        os.environ["ELRMCP_HOST"] = "0.0.0.0"
        os.environ["ELRMCP_PORT"] = "9000"
        os.environ["ELRMCP_DEBUG"] = "true"

        config = ConfigLoader.load_from_env()

        assert config.host == "0.0.0.0"
        assert config.port == 9000
        assert config.debug is True

        # Clean up environment variables
        del os.environ["ELRMCP_HOST"]
        del os.environ["ELRMCP_PORT"]
        del os.environ["ELRMCP_DEBUG"]

    def test_load_with_defaults(self):
        """Test loading configuration with defaults"""
        # Empty config dict
        config_dict = {}
        config = ConfigLoader.load_from_dict(config_dict, use_defaults=True)

        # Should use default values
        assert config.host == "localhost"
        assert config.port == 8001
        assert config.debug is False

    def test_load_partial_config(self):
        """Test loading partial configuration"""
        config_dict = {
            "host": "custom-host",
            # Missing port - should use default
        }

        config = ConfigLoader.load_from_dict(config_dict, use_defaults=True)

        assert config.host == "custom-host"
        assert config.port == 8001  # Default value


class TestConfigManager:
    """Test ConfigManager class"""

    def test_config_manager_initialization(self):
        """Test ConfigManager initialization"""
        manager = ConfigManager()

        assert manager.config is None
        assert manager.validator is not None
        assert manager.loader is not None

    def test_load_config(self):
        """Test loading configuration"""
        manager = ConfigManager()

        config_dict = {
            "host": "localhost",
            "port": 8001
        }

        config = manager.load_config(config_dict)

        assert config.host == "localhost"
        assert config.port == 8001
        assert manager.config == config

    def test_save_config(self):
        """Test saving configuration"""
        manager = ConfigManager()

        config = BridgeConfig(host="localhost", port=8001)

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            manager.save_config(config, f.name)

            # Verify file content
            saved_config = json.load(f)
            assert saved_config["host"] == "localhost"
            assert saved_config["port"] == 8001

    def test_validate_config(self):
        """Test configuration validation"""
        manager = ConfigManager()

        config = BridgeConfig(host="localhost", port=8001)

        # Valid config
        assert manager.validate_config(config) is True

        # Invalid config
        config.port = -1
        with pytest.raises(ValueError, match="Invalid port"):
            manager.validate_config(config)

    def test_get_config_value(self):
        """Test getting configuration value"""
        manager = ConfigManager()

        config = BridgeConfig(host="localhost", port=8001)

        manager.config = config

        # Get existing value
        assert manager.get_config_value("host") == "localhost"

        # Get nested value
        assert manager.get_config_value("security.api_key") is None

        # Get non-existent value
        with pytest.raises(KeyError):
            manager.get_config_value("nonexistent")

    def test_set_config_value(self):
        """Test setting configuration value"""
        manager = ConfigManager()

        config = BridgeConfig(host="localhost", port=8001)

        manager.config = config

        # Set existing value
        manager.set_config_value("host", "new-host")
        assert config.host == "new-host"

        # Set nested value
        manager.set_config_value("security.api_key", "new-key")
        assert config.security.api_key == "new-key"

    def test_merge_configs(self):
        """Test merging configurations"""
        config1 = BridgeConfig(host="host1", port=8001)
        config2 = BridgeConfig(host="host2", port=9000)

        merged = ConfigManager.merge_configs(config1, config2)

        # Values from config2 should override config1
        assert merged.host == "host2"
        assert merged.port == 9000

    def test_config_hot_reload(self):
        """Test configuration hot reload"""
        manager = ConfigManager()

        config = BridgeConfig(host="localhost", port=8001)
        manager.config = config

        # Simulate config change
        config.port = 9000

        # Hot reload should detect changes
        updated = manager.hot_reload()
        assert updated is True
        assert config.port == 9000