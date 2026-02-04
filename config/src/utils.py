"""
Configuration utilities and helper functions.
"""

import os
import json
import yaml
import toml
from pathlib import Path
from typing import Any, Dict, List, Optional, Union
from dataclasses import asdict
from functools import wraps
import logging

from .core import Config, Environment, BaseConfig
from .loader import ConfigManager

logger = logging.getLogger(__name__)


def env_override(prefix: str, default: Any = None) -> Any:
    """Environment variable override decorator."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            env_value = os.environ.get(prefix)
            if env_value is not None:
                return env_value
            return func(*args, **kwargs)
        return wrapper
    return decorator


class ConfigHelpers:
    """Configuration helper utilities."""

    @staticmethod
    def merge_configs(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
        """Merge two configuration dictionaries with deep merging."""
        result = base.copy()

        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = ConfigHelpers.merge_configs(result[key], value)
            else:
                result[key] = value

        return result

    @staticmethod
    def flatten_config(config: Union[Config, Dict[str, Any]], prefix: str = "") -> Dict[str, str]:
        """Flatten configuration dictionary with dot notation."""
        if isinstance(config, Config):
            config = asdict(config)

        flattened = {}

        def flatten_dict(d: Dict[str, Any], current_prefix: str):
            for key, value in d.items():
                new_key = f"{current_prefix}.{key}" if current_prefix else key

                if isinstance(value, dict):
                    flatten_dict(value, new_key)
                elif isinstance(value, list):
                    flattened[new_key] = json.dumps(value)
                elif isinstance(value, (str, int, float, bool)):
                    flattened[new_key] = str(value)
                else:
                    flattened[new_key] = str(value)

        flatten_dict(config, prefix)
        return flattened

    @staticmethod
    def unflatten_config(flat_config: Dict[str, str]) -> Dict[str, Any]:
        """Unflatten configuration dictionary from dot notation."""
        result = {}

        for key, value in flat_config.items():
            keys = key.split('.')
            current = result

            for k in keys[:-1]:
                if k not in current:
                    current[k] = {}
                elif not isinstance(current[k], dict):
                    current[k] = {}
                current = current[k]

            # Try to parse value as JSON first
            try:
                parsed_value = json.loads(value)
                current[keys[-1]] = parsed_value
            except json.JSONDecodeError:
                # If not JSON, keep as string or convert to appropriate type
                if value.lower() in ('true', 'false'):
                    current[keys[-1]] = value.lower() == 'true'
                elif value.isdigit():
                    current[keys[-1]] = int(value)
                elif value.replace('.', '', 1).isdigit():
                    current[keys[-1]] = float(value)
                else:
                    current[keys[-1]] = value

        return result

    @staticmethod
    def get_env_specific_config(config: Config, environment: Environment) -> Dict[str, Any]:
        """Get environment-specific configuration overrides."""
        env_name = environment.value
        env_overrides = {}

        # Get environment-specific environment variables
        env_prefix = f"{env_name.upper()}_"
        for key, value in os.environ.items():
            if key.startswith(env_prefix):
                config_key = key[len(env_prefix):].lower().replace('_', '.')
                env_overrides[config_key] = value

        return env_overrides

    @staticmethod
    def create_backup(config: Config, backup_path: Path) -> None:
        """Create a backup of the current configuration."""
        backup_data = config.to_dict()
        timestamp = backup_path.stem + "_" + backup_path.suffix
        backup_file = backup_path.parent / f"backup_{timestamp}"

        with open(backup_file, 'w', encoding='utf-8') as f:
            json.dump(backup_data, f, indent=2, default=str)

        logger.info(f"Configuration backup created: {backup_file}")

    @staticmethod
    def restore_backup(backup_path: Path) -> Config:
        """Restore configuration from backup."""
        if not backup_path.exists():
            raise FileNotFoundError(f"Backup not found: {backup_path}")

        with open(backup_path, 'r', encoding='utf-8') as f:
            backup_data = json.load(f)

        return Config.from_dict(backup_data)


class ConfigTemplate:
    """Configuration template generator."""

    @staticmethod
    def generate_basic_template() -> Dict[str, Any]:
        """Generate basic configuration template."""
        return {
            "environment": "development",
            "config_version": "0.1.0",
            "server": {
                "host": "localhost",
                "port": 8080,
                "max_connections": 100,
                "timeout": 30,
                "ssl_enabled": False
            },
            "logging": {
                "level": "INFO",
                "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
                "file": None,
                "max_size": 10485760,
                "backup_count": 5,
                "json_format": False
            },
            "security": {
                "jwt_secret": "",
                "jwt_algorithm": "HS256",
                "jwt_expiration": 3600,
                "api_key": "",
                "ssl_cert_path": None,
                "ssl_key_path": None,
                "allowed_origins": ["*"]
            },
            "database": {
                "url": None,
                "host": "localhost",
                "port": 5432,
                "name": "a2a_db",
                "username": "",
                "password": "",
                "pool_size": 10,
                "max_overflow": 20,
                "pool_timeout": 30
            },
            "mcp": {
                "server_name": "craftplan-mcp",
                "host": "localhost",
                "port": 9000,
                "protocol_version": "2024-11-05",
                "capabilities": {},
                "max_request_size": 1048576,
                "request_timeout": 300
            },
            "a2a": {
                "agent_name": "a2a-agent",
                "namespace": "default",
                "service_url": "http://localhost:8081",
                "event_bus_url": "http://localhost:8082",
                "task_timeout": 300,
                "max_retries": 3,
                "retry_delay": 5,
                "storage_backend": "ets"
            },
            "bridge": {
                "mcp_server": {
                    "server_name": "craftplan-mcp",
                    "host": "localhost",
                    "port": 9000,
                    "protocol_version": "2024-11-05",
                    "capabilities": {},
                    "max_request_size": 1048576,
                    "request_timeout": 300
                },
                "a2a_agent": {
                    "agent_name": "a2a-agent",
                    "namespace": "default",
                    "service_url": "http://localhost:8081",
                    "event_bus_url": "http://localhost:8082",
                    "task_timeout": 300,
                    "max_retries": 3,
                    "retry_delay": 5,
                    "storage_backend": "ets"
                },
                "auto_start": True,
                "heartbeat_interval": 30,
                "max_bridge_sessions": 10,
                "message_queue_size": 1000,
                "metrics_enabled": True
            },
            "custom_config": {}
        }

    @staticmethod
    def generate_environment_template(environment: Environment) -> Dict[str, Any]:
        """Generate environment-specific template."""
        template = ConfigTemplate.generate_basic_template()
        template["environment"] = environment.value

        # Environment-specific adjustments
        if environment == Environment.PRODUCTION:
            template["server"]["host"] = "0.0.0.0"
            template["server"]["ssl_enabled"] = True
            template["logging"]["level"] = "INFO"
            template["logging"]["json_format"] = True
            template["bridge"]["heartbeat_interval"] = 60
            template["bridge"]["max_bridge_sessions"] = 100
            template["bridge"]["message_queue_size"] = 10000
        elif environment == Environment.DEVELOPMENT:
            template["server"]["host"] = "localhost"
            template["server"]["ssl_enabled"] = False
            template["logging"]["level"] = "DEBUG"
            template["bridge"]["heartbeat_interval"] = 30
            template["bridge"]["max_bridge_sessions"] = 10
            template["bridge"]["message_queue_size"] = 1000

        return template

    @staticmethod
    def save_template(template: Dict[str, Any], file_path: Path, format: str = "json") -> None:
        """Save template to file."""
        file_path.parent.mkdir(parents=True, exist_ok=True)

        if format.lower() == "json":
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(template, f, indent=2, default=str)
        elif format.lower() == "yaml":
            with open(file_path, 'w', encoding='utf-8') as f:
                yaml.dump(template, f, default_flow_style=False)
        elif format.lower() == "toml":
            with open(file_path, 'w', encoding='utf-8') as f:
                toml.dump(template, f)
        else:
            raise ValueError(f"Unsupported format: {format}")


class ConfigExporter:
    """Configuration exporter for different formats."""

    @staticmethod
    def export_config(config: Config, file_path: Path, format: str = "json") -> None:
        """Export configuration to file."""
        file_path.parent.mkdir(parents=True, exist_ok=True)

        config_data = config.to_dict()

        if format.lower() == "json":
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(config_data, f, indent=2, default=str)
        elif format.lower() == "yaml":
            with open(file_path, 'w', encoding='utf-8') as f:
                yaml.dump(config_data, f, default_flow_style=False)
        elif format.lower() == "toml":
            with open(file_path, 'w', encoding='utf-8') as f:
                toml.dump(config_data, f)
        else:
            raise ValueError(f"Unsupported format: {format}")

    @staticmethod
    def export_env_file(config: Config, file_path: Path, environment: Environment) -> None:
        """Export configuration as environment file."""
        file_path.parent.mkdir(parents=True, exist_ok=True)

        flattened = ConfigHelpers.flatten_config(config)
        env_overrides = ConfigHelpers.get_env_specific_config(config, environment)

        # Merge flattened config with environment-specific overrides
        flattened.update(env_overrides)

        with open(file_path, 'w', encoding='utf-8') as f:
            for key, value in flattened.items():
                f.write(f"{key.upper()}={value}\n")

    @staticmethod
    def export_docker_config(config: Config, file_path: Path) -> None:
        """Export configuration as Docker config file."""
        file_path.parent.mkdir(parents=True, exist_ok=True)

        docker_config = {
            "base_image": "erlang:27-alpine",
            "port": config.server.port,
            "hotci_enabled": True,
            "health_check_interval": "30s",
            "health_check_timeout": "5s",
            "health_check_start_period": "5s",
            "health_check_retries": 3
        }

        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(docker_config, f, indent=2)

    @staticmethod
    def export_k8s_config(config: Config, file_path: Path) -> None:
        """Export configuration as Kubernetes config file."""
        file_path.parent.mkdir(parents=True, exist_ok=True)

        k8s_config = {
            "name": "a2a-erl",
            "namespace": "a2a-system",
            "replicas": 3,
            "app_label": "a2a-erl",
            "component_label": "application",
            "version_label": "v0.2.0",
            "container_port": config.server.port,
            "service_port": config.server.port,
            "service_type": "ClusterIP",
            "resource_request_cpu": "100m",
            "resource_request_memory": "128Mi",
            "resource_limit_cpu": "500m",
            "resource_limit_memory": "256Mi",
            "liveness_probe_path": "/health",
            "readiness_probe_path": "/ready",
            "health_check_port": config.server.port,
            "service_account_name": "a2a-service-account",
            "hotci_enabled": True,
            "hotci_check_interval": "30s"
        }

        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(k8s_config, f, indent=2)


class ConfigAnalyzer:
    """Configuration analysis utilities."""

    @staticmethod
    def analyze_config(config: Config) -> Dict[str, Any]:
        """Analyze configuration and provide insights."""
        analysis = {
            "environment": config.environment.value,
            "security_score": ConfigAnalyzer._calculate_security_score(config),
            "performance_score": ConfigAnalyzer._calculate_performance_score(config),
            "complexity_score": ConfigAnalyzer._calculate_complexity_score(config),
            "recommendations": ConfigAnalyzer._get_recommendations(config)
        }

        return analysis

    @staticmethod
    def _calculate_security_score(config: Config) -> int:
        """Calculate security configuration score (0-100)."""
        score = 100

        if not config.security.jwt_secret and not config.security.api_key:
            score -= 50
        if config.server.ssl_enabled and not config.security.ssl_cert_path:
            score -= 20
        if "*" in config.security.allowed_origins:
            score -= 30
        if config.logging.level == "DEBUG":
            score -= 10

        return max(0, score)

    @staticmethod
    def _calculate_performance_score(config: Config) -> int:
        """Calculate performance configuration score (0-100)."""
        score = 100

        if config.server.max_connections > 1000:
            score -= 20
        if config.database.max_overflow > 100:
            score -= 10
        if config.bridge.max_bridge_sessions > 100:
            score -= 15
        if config.bridge.message_queue_size > 10000:
            score -= 10

        return max(0, score)

    @staticmethod
    def _calculate_complexity_score(config: Config) -> int:
        """Calculate configuration complexity score (0-100)."""
        score = 0

        # Count configuration sections
        if config.server.ssl_enabled:
            score += 20
        if config.database.url:
            score += 15
        if config.security.ssl_cert_path:
            score += 10
        if len(config.mcp.capabilities) > 0:
            score += 20
        if len(config.custom_config) > 0:
            score += 15

        return min(100, score)

    @staticmethod
    def _get_recommendations(config: Config) -> List[str]:
        """Get configuration recommendations."""
        recommendations = []

        if not config.security.jwt_secret and not config.security.api_key:
            recommendations.append("Configure either JWT secret or API key for security")
        if config.server.ssl_enabled and not config.security.ssl_cert_path:
            recommendations.append("Configure SSL certificate and key paths")
        if config.logging.level == "DEBUG" and config.environment == Environment.PRODUCTION:
            recommendations.append("Consider changing log level to INFO or higher in production")
        if config.server.max_connections > 500:
            recommendations.append("Consider increasing max_connections for better performance")
        if config.bridge.heartbeat_interval < 30:
            recommendations.append("Consider increasing heartbeat interval to at least 30 seconds")

        return recommendations