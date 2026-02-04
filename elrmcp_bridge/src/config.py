"""Configuration Management

This module provides comprehensive configuration management for the A2A bridge,
including environment variables, file-based configuration, and validation.

Configuration Features:
    - Environment variable support
    - JSON/YAML configuration files
    - Validation and type checking
    - Configuration templates
    - Secure configuration handling
    - Hot configuration reload
"""

import os
import json
import yaml
import logging
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional, Type, Union
from enum import Enum
import hashlib
import secrets
from pathlib import Path
import copy


class ConfigFormat(Enum):
    """Supported configuration formats"""
    JSON = "json"
    YAML = "yaml"
    TOML = "toml"
    ENV = "env"


@dataclass
class SecurityConfig:
    """Security configuration"""
    api_key: Optional[str] = None
    jwt_secret: Optional[str] = None
    allowed_origins: List[str] = field(default_factory=lambda: ["*"])
    max_connections: int = 1000
    rate_limit: int = 100
    enable_cors: bool = True
    ssl_enabled: bool = False
    ssl_cert_path: Optional[str] = None
    ssl_key_path: Optional[str] = None
    auth_required: bool = False

    def __post_init__(self):
        if self.api_key is None:
            self.api_key = secrets.token_urlsafe(32)
        if self.jwt_secret is None:
            self.jwt_secret = secrets.token_urlsafe(32)


@dataclass
class TransportConfig:
    """Transport configuration"""
    type: str = "websocket"
    websocket_url: str = "ws://localhost:8080"
    sse_url: str = "http://localhost:8081"
    max_connections: int = 100
    connection_timeout: int = 30
    message_timeout: int = 60
    heartbeat_interval: int = 30
    reconnect_attempts: int = 5
    reconnect_delay: int = 5

    def __post_init__(self):
        if self.type not in ["websocket", "sse", "hybrid"]:
            raise ValueError(f"Invalid transport type: {self.type}")


@dataclass
class AgentConfig:
    """Agent configuration"""
    discovery_interval: int = 60
    heartbeat_interval: int = 30
    timeout: int = 30
    max_retries: int = 3
    retry_delay: int = 5
    load_balancer: str = "least_loaded"
    capabilities: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class WorkflowConfig:
    """Workflow configuration"""
    max_concurrent_workflows: int = 10
    workflow_timeout: int = 300
    task_timeout: int = 60
    max_retries: int = 3
    retry_delay: int = 5
    enable_monitoring: bool = True
    metrics_enabled: bool = True


@dataclass
class LoggingConfig:
    """Logging configuration"""
    level: str = "INFO"
    format: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    file_path: Optional[str] = None
    max_file_size: int = 10 * 1024 * 1024  # 10MB
    backup_count: int = 5
    enable_console: bool = True
    enable_file: bool = True
    enable_json: bool = False

    def __post_init__(self):
        if self.level not in ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]:
            raise ValueError(f"Invalid log level: {self.level}")


@dataclass
class MetricsConfig:
    """Metrics configuration"""
    enabled: bool = True
    port: int = 8000
    host: str = "0.0.0.0"
    export_format: str = "json"
    retention_days: int = 30
    collection_interval: int = 10
    prometheus_pushgateway_url: Optional[str] = None
    alert_enabled: bool = False
    alert_email: Optional[str] = None


@dataclass
class BridgeConfig:
    """Main bridge configuration"""
    # Server configuration
    host: str = "localhost"
    port: int = 8001
    debug: bool = False
    development: bool = False

    # Security configuration
    security: SecurityConfig = field(default_factory=SecurityConfig)

    # Transport configuration
    transport: TransportConfig = field(default_factory=TransportConfig)

    # Agent configuration
    agent: AgentConfig = field(default_factory=AgentConfig)

    # Workflow configuration
    workflow: WorkflowConfig = field(default_factory=WorkflowConfig)

    # Logging configuration
    logging: LoggingConfig = field(default_factory=LoggingConfig)

    # Metrics configuration
    metrics: MetricsConfig = field(default_factory=MetricsConfig)

    # Database configuration
    database_url: Optional[str] = None

    # Feature flags
    enable_websocket: bool = True
    enable_sse: bool = True
    enable_api: bool = True
    enable_metrics: bool = True
    enable_workflows: bool = True

    # Additional metadata
    environment: str = "production"
    version: str = "1.0.0"
    description: str = "A2A Bridge Integration Module"
    contact_email: Optional[str] = None

    def __post_init__(self):
        # Validate configuration
        self._validate_config()

    def _validate_config(self):
        """Validate configuration"""
        # Validate port ranges
        if not (1 <= self.port <= 65535):
            raise ValueError(f"Invalid port: {self.port}")
        if not (1 <= self.transport.port <= 65535):
            raise ValueError(f"Invalid transport port: {self.transport.port}")
        if not (1 <= self.metrics.port <= 65535):
            raise ValueError(f"Invalid metrics port: {self.metrics.port}")

        # Validate timeout values
        if self.transport.connection_timeout <= 0:
            raise ValueError("Connection timeout must be positive")
        if self.transport.message_timeout <= 0:
            raise ValueError("Message timeout must be positive")

        # Validate retry values
        if self.agent.max_retries < 0:
            raise ValueError("Max retries cannot be negative")
        if self.workflow.max_retries < 0:
            raise ValueError("Max retries cannot be negative")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        result = asdict(self)

        # Convert nested objects to dictionaries
        for key, value in result.items():
            if hasattr(value, 'to_dict'):
                result[key] = value.to_dict()

        return result

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'BridgeConfig':
        """Create from dictionary"""
        # Extract nested config objects
        security_data = data.get('security', {})
        transport_data = data.get('transport', {})
        agent_data = data.get('agent', {})
        workflow_data = data.get('workflow', {})
        logging_data = data.get('logging', {})
        metrics_data = data.get('metrics', {})

        # Create nested config objects
        security = SecurityConfig(**security_data)
        transport = TransportConfig(**transport_data)
        agent = AgentConfig(**agent_data)
        workflow = WorkflowConfig(**workflow_data)
        logging = LoggingConfig(**logging_data)
        metrics = MetricsConfig(**metrics_data)

        # Create main config object
        config = cls(
            host=data.get('host', 'localhost'),
            port=data.get('port', 8001),
            debug=data.get('debug', False),
            development=data.get('development', False),
            security=security,
            transport=transport,
            agent=agent,
            workflow=workflow,
            logging=logging,
            metrics=metrics,
            database_url=data.get('database_url'),
            enable_websocket=data.get('enable_websocket', True),
            enable_sse=data.get('enable_sse', True),
            enable_api=data.get('enable_api', True),
            enable_metrics=data.get('enable_metrics', True),
            enable_workflows=data.get('enable_workflows', True),
            environment=data.get('environment', 'production'),
            version=data.get('version', '1.0.0'),
            description=data.get('description', 'A2A Bridge Integration Module'),
            contact_email=data.get('contact_email')
        )

        return config


class ConfigManager:
    """Configuration manager"""

    def __init__(self, config_path: Optional[str] = None):
        self.logger = logging.getLogger(__name__)
        self.config_path = config_path
        self.config: Optional[BridgeConfig] = None
        self.config_hash = None
        self.watchers: List[callable] = []

        # Configuration templates
        self.templates = {
            "development": self._get_development_template(),
            "production": self._get_production_template(),
            "testing": self._get_testing_template()
        }

    def _get_development_template(self) -> BridgeConfig:
        """Get development template"""
        return BridgeConfig(
            environment="development",
            debug=True,
            development=True,
            security=SecurityConfig(
                api_key="dev-key",
                auth_required=False
            ),
            logging=LoggingConfig(
                level="DEBUG",
                enable_console=True,
                enable_file=False
            ),
            metrics=MetricsConfig(
                enabled=True,
                port=8000
            )
        )

    def _get_production_template(self) -> BridgeConfig:
        """Get production template"""
        return BridgeConfig(
            environment="production",
            debug=False,
            development=False,
            security=SecurityConfig(
                api_key=None,
                auth_required=True,
                max_connections=1000
            ),
            logging=LoggingConfig(
                level="INFO",
                enable_console=True,
                enable_file=True
            ),
            metrics=MetricsConfig(
                enabled=True,
                port=8000
            )
        )

    def _get_testing_template(self) -> BridgeConfig:
        """Get testing template"""
        return BridgeConfig(
            environment="testing",
            debug=True,
            development=True,
            security=SecurityConfig(
                api_key="test-key",
                auth_required=False
            ),
            logging=LoggingConfig(
                level="DEBUG",
                enable_console=True,
                enable_file=False
            ),
            metrics=MetricsConfig(
                enabled=False
            )
        )

    def load_config(self, config_path: Optional[str] = None) -> BridgeConfig:
        """Load configuration from file or use defaults"""
        if config_path:
            self.config_path = config_path

        if self.config_path and os.path.exists(self.config_path):
            self.config = self._load_from_file(self.config_path)
            self.logger.info(f"Loaded configuration from {self.config_path}")
        else:
            # Use environment variables or defaults
            self.config = self._load_from_environment()
            self.logger.info("Loaded configuration from environment and defaults")

        # Generate config hash for change detection
        self.config_hash = self._generate_config_hash(self.config)

        return self.config

    def _load_from_file(self, config_path: str) -> BridgeConfig:
        """Load configuration from file"""
        try:
            with open(config_path, 'r') as f:
                if config_path.endswith('.json'):
                    data = json.load(f)
                elif config_path.endswith('.yaml') or config_path.endswith('.yml'):
                    data = yaml.safe_load(f)
                else:
                    raise ValueError(f"Unsupported config file format: {config_path}")

            return BridgeConfig.from_dict(data)

        except Exception as e:
            self.logger.error(f"Failed to load config from {config_path}: {e}")
            raise

    def _load_from_environment(self) -> BridgeConfig:
        """Load configuration from environment variables"""
        data = {}

        # Basic config
        data['host'] = os.getenv('A2A_BRIDGE_HOST', 'localhost')
        data['port'] = int(os.getenv('A2A_BRIDGE_PORT', '8001'))
        data['debug'] = os.getenv('A2A_BRIDGE_DEBUG', 'false').lower() == 'true'
        data['development'] = os.getenv('A2A_BRIDGE_DEVELOPMENT', 'false').lower() == 'true'

        # Security config
        data['security'] = {
            'api_key': os.getenv('A2A_BRIDGE_API_KEY'),
            'jwt_secret': os.getenv('A2A_BRIDGE_JWT_SECRET'),
            'allowed_origins': os.getenv('A2A_BRIDGE_ALLOWED_ORIGINS', '*').split(','),
            'auth_required': os.getenv('A2A_BRIDGE_AUTH_REQUIRED', 'false').lower() == 'true'
        }

        # Transport config
        data['transport'] = {
            'type': os.getenv('A2A_BRIDGE_TRANSPORT_TYPE', 'websocket'),
            'websocket_url': os.getenv('A2A_BRIDGE_WEBSOCKET_URL', 'ws://localhost:8080'),
            'sse_url': os.getenv('A2A_BRIDGE_SSE_URL', 'http://localhost:8081'),
            'connection_timeout': int(os.getenv('A2A_BRIDGE_CONNECTION_TIMEOUT', '30')),
            'message_timeout': int(os.getenv('A2A_BRIDGE_MESSAGE_TIMEOUT', '60')),
            'heartbeat_interval': int(os.getenv('A2A_BRIDGE_HEARTBEAT_INTERVAL', '30'))
        }

        # Agent config
        data['agent'] = {
            'discovery_interval': int(os.getenv('A2A_BRIDGE_AGENT_DISCOVERY_INTERVAL', '60')),
            'heartbeat_interval': int(os.getenv('A2A_BRIDGE_AGENT_HEARTBEAT_INTERVAL', '30')),
            'timeout': int(os.getenv('A2A_BRIDGE_AGENT_TIMEOUT', '30')),
            'max_retries': int(os.getenv('A2A_BRIDGE_AGENT_MAX_RETRIES', '3')),
            'capabilities': os.getenv('A2A_BRIDGE_AGENT_CAPABILITIES', '').split(',')
        }

        # Workflow config
        data['workflow'] = {
            'max_concurrent_workflows': int(os.getenv('A2A_BRIDGE_WORKFLOW_MAX_CONCURRENT', '10')),
            'workflow_timeout': int(os.getenv('A2A_BRIDGE_WORKFLOW_TIMEOUT', '300')),
            'task_timeout': int(os.getenv('A2A_BRIDGE_TASK_TIMEOUT', '60')),
            'max_retries': int(os.getenv('A2A_BRIDGE_WORKFLOW_MAX_RETRIES', '3'))
        }

        # Logging config
        data['logging'] = {
            'level': os.getenv('A2A_BRIDGE_LOG_LEVEL', 'INFO'),
            'format': os.getenv('A2A_BRIDGE_LOG_FORMAT', '%(asctime)s - %(name)s - %(levelname)s - %(message)s'),
            'file_path': os.getenv('A2A_BRIDGE_LOG_FILE'),
            'enable_console': os.getenv('A2A_BRIDGE_LOG_CONSOLE', 'true').lower() == 'true',
            'enable_file': os.getenv('A2A_BRIDGE_LOG_FILE_ENABLED', 'false').lower() == 'true'
        }

        # Metrics config
        data['metrics'] = {
            'enabled': os.getenv('A2A_BRIDGE_METRICS_ENABLED', 'true').lower() == 'true',
            'port': int(os.getenv('A2A_BRIDGE_METRICS_PORT', '8000')),
            'host': os.getenv('A2A_BRIDGE_METRICS_HOST', '0.0.0.0')
        }

        return BridgeConfig.from_dict(data)

    def save_config(self, config_path: Optional[str] = None) -> None:
        """Save configuration to file"""
        if not self.config:
            raise ValueError("No configuration loaded")

        config_path = config_path or self.config_path
        if not config_path:
            raise ValueError("No configuration path specified")

        try:
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(config_path), exist_ok=True)

            # Convert to dictionary
            config_dict = self.config.to_dict()

            # Save to file
            with open(config_path, 'w') as f:
                if config_path.endswith('.json'):
                    json.dump(config_dict, f, indent=2)
                elif config_path.endswith('.yaml') or config_path.endswith('.yml'):
                    yaml.dump(config_dict, f, default_flow_style=False)
                else:
                    raise ValueError(f"Unsupported config file format: {config_path}")

            # Update config hash
            self.config_hash = self._generate_config_hash(self.config)

            self.logger.info(f"Configuration saved to {config_path}")

        except Exception as e:
            self.logger.error(f"Failed to save config to {config_path}: {e}")
            raise

    def _generate_config_hash(self, config: BridgeConfig) -> str:
        """Generate hash for configuration"""
        config_dict = config.to_dict()
        config_str = json.dumps(config_dict, sort_keys=True)
        return hashlib.sha256(config_str.encode()).hexdigest()

    def has_changed(self) -> bool:
        """Check if configuration has changed"""
        if not self.config:
            return False

        current_hash = self._generate_config_hash(self.config)
        return current_hash != self.config_hash

    def reload_config(self) -> bool:
        """Reload configuration from file"""
        if not self.config_path:
            return False

        try:
            old_config = self.config
            self.config = self._load_from_file(self.config_path)

            if old_config != self.config:
                self.logger.info("Configuration reloaded successfully")
                self._notify_config_changed(old_config, self.config)
                return True
            else:
                self.logger.debug("Configuration unchanged")
                return False

        except Exception as e:
            self.logger.error(f"Failed to reload configuration: {e}")
            return False

    def get_config(self) -> BridgeConfig:
        """Get current configuration"""
        if not self.config:
            raise ValueError("No configuration loaded")
        return self.config

    def update_config(self, updates: Dict[str, Any]) -> None:
        """Update configuration with new values"""
        if not self.config:
            raise ValueError("No configuration loaded")

        # Create a deep copy of the current config
        config_dict = self.config.to_dict()

        # Apply updates
        def apply_updates(d: Dict[str, Any], updates: Dict[str, Any], path: str = ""):
            for key, value in updates.items():
                current_path = f"{path}.{key}" if path else key

                if key in d and isinstance(d[key], dict) and isinstance(value, dict):
                    apply_updates(d[key], value, current_path)
                else:
                    d[key] = value

        apply_updates(config_dict, updates)

        # Create new config object
        try:
            new_config = BridgeConfig.from_dict(config_dict)

            # Validate new config
            if new_config != self.config:
                self.config = new_config
                self.config_hash = self._generate_config_hash(self.config)
                self.logger.info("Configuration updated successfully")
                self._notify_config_changed(self.config, self.config)
            else:
                self.logger.debug("No changes in configuration update")

        except Exception as e:
            self.logger.error(f"Failed to update configuration: {e}")
            raise

    def reset_config(self, environment: str = "production") -> None:
        """Reset configuration to template"""
        if environment not in self.templates:
            raise ValueError(f"Unknown environment: {environment}")

        self.config = self.templates[environment]
        self.config_hash = self._generate_config_hash(self.config)
        self.logger.info(f"Configuration reset to {environment} template")

    def add_config_watcher(self, callback: callable) -> None:
        """Add configuration change watcher"""
        self.watchers.append(callback)

    def remove_config_watcher(self, callback: callable) -> None:
        """Remove configuration change watcher"""
        if callback in self.watchers:
            self.watchers.remove(callback)

    def _notify_config_changed(self, old_config: BridgeConfig, new_config: BridgeConfig) -> None:
        """Notify watchers of configuration change"""
        for watcher in self.watchers:
            try:
                watcher(old_config, new_config)
            except Exception as e:
                self.logger.error(f"Error in config watcher: {e}")

    def create_template(self, template_path: str, environment: str = "production") -> None:
        """Create configuration template"""
        if environment not in self.templates:
            raise ValueError(f"Unknown environment: {environment}")

        template_config = self.templates[environment]
        template_dict = template_config.to_dict()

        try:
            with open(template_path, 'w') as f:
                if template_path.endswith('.json'):
                    json.dump(template_dict, f, indent=2)
                elif template_path.endswith('.yaml') or template_path.endswith('.yml'):
                    yaml.dump(template_dict, f, default_flow_style=False)
                else:
                    raise ValueError(f"Unsupported template format: {template_path}")

            self.logger.info(f"Template created at {template_path}")

        except Exception as e:
            self.logger.error(f"Failed to create template: {e}")
            raise

    def validate_config(self, config: BridgeConfig) -> List[str]:
        """Validate configuration and return list of errors"""
        errors = []

        # Validate basic config
        if not config.host:
            errors.append("Host is required")

        if not (1 <= config.port <= 65535):
            errors.append(f"Port must be between 1 and 65535, got {config.port}")

        # Validate security config
        if config.security.auth_required and not config.security.api_key:
            errors.append("API key is required when authentication is enabled")

        # Validate transport config
        if config.transport.type not in ["websocket", "sse", "hybrid"]:
            errors.append(f"Invalid transport type: {config.transport.type}")

        # Validate agent config
        if config.agent.max_retries < 0:
            errors.append("Max retries cannot be negative")

        # Validate workflow config
        if config.workflow.max_concurrent_workflows <= 0:
            errors.append("Max concurrent workflows must be positive")

        # Validate metrics config
        if not (1 <= config.metrics.port <= 65535):
            errors.append(f"Metrics port must be between 1 and 65535, got {config.metrics.port}")

        return errors

    def get_env_vars(self) -> Dict[str, str]:
        """Get environment variables for current config"""
        config_dict = self.config.to_dict()
        env_vars = {}

        def dict_to_env(d: Dict[str, Any], prefix: str = ""):
            for key, value in d.items():
                env_key = f"{prefix}_{key.upper()}" if prefix else key.upper()

                if isinstance(value, dict):
                    dict_to_env(value, env_key)
                elif isinstance(value, list):
                    env_vars[env_key] = ','.join(map(str, value))
                else:
                    env_vars[env_key] = str(value)

        dict_to_env(config_dict, 'A2A_BRIDGE')
        return env_vars

    def apply_to_system(self) -> None:
        """Apply configuration to system"""
        # Set up logging
        if self.config.logging:
            logging.basicConfig(
                level=getattr(logging, self.config.logging.level),
                format=self.config.logging.format,
                handlers=[]
            )

        # Apply environment variables
        env_vars = self.get_env_vars()
        for key, value in env_vars.items():
            os.environ[key] = value

        self.logger.info("Configuration applied to system")