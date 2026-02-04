"""
Core configuration classes and interfaces.
"""

import os
import json
import yaml
import toml
from pathlib import Path
from typing import Any, Dict, List, Optional, Union, Type, TypeVar, Generic
from abc import ABC, abstractmethod
from dataclasses import dataclass, field, asdict
from enum import Enum
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

T = TypeVar('T')


class ConfigFormat(Enum):
    """Supported configuration file formats."""
    JSON = "json"
    YAML = "yaml"
    TOML = "toml"


class Environment(Enum):
    """Supported deployment environments."""
    DEVELOPMENT = "development"
    TESTING = "testing"
    STAGING = "staging"
    PRODUCTION = "production"


@dataclass
class BaseConfig(ABC):
    """Base class for all configuration classes."""

    config_version: str = field(default="0.1.0", metadata={"description": "Configuration schema version"})

    @classmethod
    def from_dict(cls: Type[T], data: Dict[str, Any]) -> T:
        """Create configuration instance from dictionary."""
        return cls(**{k: v for k, v in data.items() if hasattr(cls, k)})

    def to_dict(self) -> Dict[str, Any]:
        """Convert configuration to dictionary."""
        return asdict(self)

    def to_json(self, indent: int = 2) -> str:
        """Convert configuration to JSON string."""
        return json.dumps(self.to_dict(), indent=indent, default=str)

    def validate(self) -> List[str]:
        """Validate configuration and return list of errors."""
        return []


@dataclass
class ServerConfig(BaseConfig):
    """Server configuration base class."""

    host: str = field(default="localhost", metadata={"description": "Server host"})
    port: int = field(default=8080, metadata={"description": "Server port"})
    max_connections: int = field(default=100, metadata={"description": "Maximum concurrent connections"})
    timeout: int = field(default=30, metadata={"description": "Connection timeout in seconds"})
    ssl_enabled: bool = field(default=False, metadata={"description": "Enable SSL/TLS"})


@dataclass
class LogConfig(BaseConfig):
    """Logging configuration."""

    level: str = field(default="INFO", metadata={"description": "Logging level"})
    format: str = field(default="%(asctime)s - %(name)s - %(levelname)s - %(message)s", metadata={"description": "Log format"})
    file: Optional[str] = field(default=None, metadata={"description": "Log file path"})
    max_size: int = field(default=10485760, metadata={"description": "Max log file size in bytes"})
    backup_count: int = field(default=5, metadata={"description": "Number of backup files to keep"})
    json_format: bool = field(default=False, metadata={"description": "Use JSON log format"})


@dataclass
class SecurityConfig(BaseConfig):
    """Security configuration."""

    jwt_secret: Optional[str] = field(default=None, metadata={"description": "JWT secret key"})
    jwt_algorithm: str = field(default="HS256", metadata={"description": "JWT algorithm"})
    jwt_expiration: int = field(default=3600, metadata={"description": "JWT expiration in seconds"})
    api_key: Optional[str] = field(default=None, metadata={"description": "API key for authentication"})
    ssl_cert_path: Optional[str] = field(default=None, metadata={"description": "SSL certificate path"})
    ssl_key_path: Optional[str] = field(default=None, metadata={"description": "SSL private key path"})
    allowed_origins: List[str] = field(default_factory=lambda: ["*"], metadata={"description": "CORS allowed origins"})


@dataclass
class DatabaseConfig(BaseConfig):
    """Database configuration."""

    url: Optional[str] = field(default=None, metadata={"description": "Database URL"})
    host: str = field(default="localhost", metadata={"description": "Database host"})
    port: int = field(default=5432, metadata={"description": "Database port"})
    name: str = field(default="a2a_db", metadata={"description": "Database name"})
    username: Optional[str] = field(default=None, metadata={"description": "Database username"})
    password: Optional[str] = field(default=None, metadata={"description": "Database password"})
    pool_size: int = field(default=10, metadata={"description": "Connection pool size"})
    max_overflow: int = field(default=20, metadata={"description": "Maximum overflow connections"})
    pool_timeout: int = field(default=30, metadata={"description": "Connection pool timeout"})


@dataclass
class MCPConfig(BaseConfig):
    """MCP server configuration."""

    server_name: str = field(default="craftplan-mcp", metadata={"description": "MCP server name"})
    host: str = field(default="localhost", metadata={"description": "MCP server host"})
    port: int = field(default=9000, metadata={"description": "MCP server port"})
    protocol_version: str = field(default="2024-11-05", metadata={"description": "MCP protocol version"})
    capabilities: Dict[str, Any] = field(
        default_factory=lambda: {
            "tools": {},
            "resources": {},
            "logging": {}
        },
        metadata={"description": "MCP server capabilities"}
    )
    max_request_size: int = field(default=1048576, metadata={"description": "Maximum request size in bytes"})
    request_timeout: int = field(default=300, metadata={"description": "Request timeout in seconds"})


@dataclass
class A2AConfig(BaseConfig):
    """A2A agent configuration."""

    agent_name: str = field(default="a2a-agent", metadata={"description": "A2A agent name"})
    namespace: str = field(default="default", metadata={"description": "A2A agent namespace"})
    service_url: str = field(default="http://localhost:8081", metadata={"description": "A2A service URL"})
    event_bus_url: str = field(default="http://localhost:8082", metadata={"description": "Event bus URL"})
    task_timeout: int = field(default=300, metadata={"description": "Task timeout in seconds"})
    max_retries: int = field(default=3, metadata={"description": "Maximum retry attempts"})
    retry_delay: int = field(default=5, metadata={"description": "Retry delay in seconds"})
    storage_backend: str = field(default="ets", metadata={"description": "Storage backend (ets, mnesia, redis)"})


@dataclass
class BridgeConfig(BaseConfig):
    """Bridge configuration for MCP-A2A integration."""

    mcp_server: MCPConfig = field(default_factory=MCPConfig, metadata={"description": "MCP server configuration"})
    a2a_agent: A2AConfig = field(default_factory=A2AConfig, metadata={"description": "A2A agent configuration"})
    auto_start: bool = field(default=True, metadata={"description": "Auto-start bridge on startup"})
    heartbeat_interval: int = field(default=30, metadata={"description": "Heartbeat interval in seconds"})
    max_bridge_sessions: int = field(default=10, metadata={"description": "Maximum bridge sessions"})
    message_queue_size: int = field(default=1000, metadata={"description": "Message queue size"})
    metrics_enabled: bool = field(default=True, metadata={"description": "Enable metrics collection"})


@dataclass
class Config(BaseConfig):
    """Main configuration container."""

    environment: Environment = field(default=Environment.DEVELOPMENT, metadata={"description": "Deployment environment"})
    server: ServerConfig = field(default_factory=ServerConfig, metadata={"description": "Server configuration"})
    logging: LogConfig = field(default_factory=LogConfig, metadata={"description": "Logging configuration"})
    security: SecurityConfig = field(default_factory=SecurityConfig, metadata={"description": "Security configuration"})
    database: DatabaseConfig = field(default_factory=DatabaseConfig, metadata={"description": "Database configuration"})
    mcp: MCPConfig = field(default_factory=MCPConfig, metadata={"description": "MCP configuration"})
    a2a: A2AConfig = field(default_factory=A2AConfig, metadata={"description": "A2A configuration"})
    bridge: BridgeConfig = field(default_factory=BridgeConfig, metadata={"description": "Bridge configuration"})
    custom_config: Dict[str, Any] = field(default_factory=dict, metadata={"description": "Custom configuration"})

    def validate(self) -> List[str]:
        """Validate all configuration sections."""
        errors = []

        # Validate server config
        errors.extend(self.server.validate())

        # Validate logging config
        if self.logging.level not in ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]:
            errors.append(f"Invalid logging level: {self.logging.level}")

        # Validate security config
        if self.security.jwt_secret is None and self.security.api_key is None:
            errors.append("Either JWT secret or API key must be configured")

        # Validate database config
        if not self.database.url and not (self.database.host and self.database.name):
            errors.append("Database URL or host and name must be configured")

        # Validate MCP config
        if not self.mcp.server_name:
            errors.append("MCP server name is required")

        # Validate bridge config
        errors.extend(self.bridge.validate())

        return errors