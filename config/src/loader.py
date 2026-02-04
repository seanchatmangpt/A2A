"""
Configuration loader with support for multiple formats and sources.
"""

import os
import json
import yaml
import toml
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional, Union, Type
from dataclasses import dataclass, field

from .core import BaseConfig, Config, ConfigFormat, Environment

logger = logging.getLogger(__name__)


@dataclass
class ConfigSource:
    """Configuration source definition."""
    path: Path
    format: ConfigFormat
    priority: int = 100
    required: bool = False
    environment_specific: bool = True


class ConfigLoader:
    """Configuration loader that supports multiple sources and formats."""

    def __init__(self, config_class: Type[BaseConfig] = Config):
        """Initialize config loader."""
        self.config_class = config_class
        self.sources: List[ConfigSource] = []
        self._cache: Dict[str, Any] = {}

    def add_source(self, path: Union[str, Path], format: ConfigFormat,
                  priority: int = 100, required: bool = False,
                  environment_specific: bool = True) -> None:
        """Add a configuration source."""
        path = Path(path)
        self.sources.append(ConfigSource(
            path=path,
            format=format,
            priority=priority,
            required=required,
            environment_specific=environment_specific
        ))

    def add_default_sources(self, config_dir: Path = None) -> None:
        """Add default configuration sources."""
        if config_dir is None:
            config_dir = Path("config")

        # Environment-specific directories
        env_map = {
            Environment.DEVELOPMENT: "dev",
            Environment.TESTING: "test",
            Environment.STAGING: "staging",
            Environment.PRODUCTION: "prod"
        }

        # Add config files in order of priority (low to high)
        formats = [ConfigFormat.JSON, ConfigFormat.YAML, ConfigFormat.TOML]

        # Base config files (lowest priority)
        for fmt in formats:
            self.add_source(config_dir / f"config.{fmt.value}", fmt, 10, required=False, environment_specific=False)

        # Environment-specific config files
        for env, env_name in env_map.items():
            for fmt in formats:
                self.add_source(config_dir / env_name / f"config.{fmt.value}", fmt, 20, required=False, environment_specific=True)

        # Local overrides (highest priority)
        for fmt in formats:
            self.add_source(config_dir / f"config.local.{fmt.value}", fmt, 100, required=False, environment_specific=False)

    def load(self, environment: Environment = Environment.DEVELOPMENT) -> Config:
        """Load configuration from all sources."""
        config_data = {}
        environment_name = environment.value

        # Sort sources by priority
        sorted_sources = sorted(self.sources, key=lambda x: x.priority)

        # Load each source
        for source in sorted_sources:
            if source.environment_specific and environment_name not in str(source.path):
                continue

            try:
                if source.path.exists():
                    data = self._load_file(source.path, source.format)
                    config_data = self._merge_configs(config_data, data)
                    logger.info(f"Loaded config from {source.path}")
                elif source.required:
                    raise FileNotFoundError(f"Required config file not found: {source.path}")
            except Exception as e:
                logger.error(f"Failed to load config from {source.path}: {e}")
                if source.required:
                    raise

        # Apply environment variables
        config_data = self._apply_environment_overrides(config_data, environment_name)

        # Create and validate config instance
        config = self.config_class.from_dict(config_data)
        errors = config.validate()

        if errors:
            logger.warning(f"Config validation errors: {errors}")

        return config

    def _load_file(self, path: Path, format: ConfigFormat) -> Dict[str, Any]:
        """Load configuration file."""
        try:
            with open(path, 'r', encoding='utf-8') as f:
                if format == ConfigFormat.JSON:
                    return json.load(f)
                elif format == ConfigFormat.YAML:
                    return yaml.safe_load(f) or {}
                elif format == ConfigFormat.TOML:
                    return toml.load(f)
                else:
                    raise ValueError(f"Unsupported format: {format}")
        except Exception as e:
            raise ValueError(f"Failed to load {path} as {format.value}: {e}")

    def _merge_configs(self, base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
        """Merge configuration dictionaries with deep merging."""
        result = base.copy()

        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self._merge_configs(result[key], value)
            else:
                result[key] = value

        return result

    def _apply_environment_overrides(self, config: Dict[str, Any], env_name: str) -> Dict[str, Any]:
        """Apply environment variable overrides."""
        # Environment variables prefixed with the environment name
        env_prefix = f"{env_name.upper()}_"

        for key, value in os.environ.items():
            if key.startswith(env_prefix):
                # Remove prefix and convert to nested key path
                nested_key = key[len(env_prefix):].lower().replace('_', '.')
                config = self._set_nested_key(config, nested_key, value)

        return config

    def _set_nested_key(self, config: Dict[str, Any], key_path: str, value: Any) -> Dict[str, Any]:
        """Set nested configuration key from dot-separated path."""
        keys = key_path.split('.')
        current = config

        # Create nested dictionaries if they don't exist
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            elif not isinstance(current[key], dict):
                current[key] = {}
            current = current[key]

        # Set the final value
        current[keys[-1]] = value
        return config

    def reload(self, environment: Environment = None) -> Config:
        """Reload configuration and clear cache."""
        self._cache.clear()
        if environment is None:
            # Try to get environment from cached config if available
            if self._cache.get("config"):
                environment = self._cache["config"].environment
            else:
                environment = Environment.DEVELOPMENT

        return self.load(environment)

    def get_schema(self) -> Dict[str, Any]:
        """Get configuration schema for documentation."""
        schema = {}
        config_instance = self.config_class()

        for key, value in config_instance.to_dict().items():
            schema[key] = {
                "type": type(value).__name__,
                "description": getattr(value, "__dataclass_fields__", {}).get(key, {}).get("metadata", {}).get("description", ""),
                "default": value if not isinstance(value, dict) else {}
            }

        return schema


class ConfigManager:
    """High-level configuration manager."""

    def __init__(self, config_dir: Path = None):
        """Initialize config manager."""
        self.loader = ConfigLoader()
        self.loader.add_default_sources(config_dir)
        self._current_config: Optional[Config] = None

    def load_config(self, environment: Environment = Environment.DEVELOPMENT) -> Config:
        """Load configuration for the specified environment."""
        self._current_config = self.loader.load(environment)
        return self._current_config

    def get_config(self) -> Config:
        """Get current configuration."""
        if self._current_config is None:
            self._current_config = self.load_config()
        return self._current_config

    def reload_config(self) -> Config:
        """Reload current configuration."""
        if self._current_config is not None:
            self._current_config = self.loader.reload(self._current_config.environment)
        else:
            self._current_config = self.load_config()
        return self._current_config

    def add_custom_source(self, path: Union[str, Path], format: ConfigFormat,
                         priority: int = 100, required: bool = False) -> None:
        """Add a custom configuration source."""
        self.loader.add_source(path, format, priority, required, False)

    def get_schema(self) -> Dict[str, Any]:
        """Get configuration schema."""
        return self.loader.get_schema()