"""
Configuration validation with JSON schema support.
"""

import json
import jsonschema
import logging
from typing import Any, Dict, List, Optional, Union
from pathlib import Path
from dataclasses import dataclass, field

from .core import BaseConfig, Config, Environment

logger = logging.getLogger(__name__)


@dataclass
class ValidationError:
    """Configuration validation error."""
    path: str
    message: str
    value: Any
    schema_path: str = field(default="")


class ConfigValidator:
    """Configuration validator with JSON schema support."""

    def __init__(self):
        """Initialize validator."""
        self.schemas: Dict[str, Dict[str, Any]] = {}
        self._load_schemas()

    def _load_schemas(self) -> None:
        """Load validation schemas."""
        # Define JSON schema for main configuration
        self.schemas["config"] = {
            "type": "object",
            "properties": {
                "environment": {"type": "string", "enum": ["development", "testing", "staging", "production"]},
                "config_version": {"type": "string"},
                "server": {"$ref": "#/definitions/server"},
                "logging": {"$ref": "#/definitions/logging"},
                "security": {"$ref": "#/definitions/security"},
                "database": {"$ref": "#/definitions/database"},
                "mcp": {"$ref": "#/definitions/mcp"},
                "a2a": {"$ref": "#/definitions/a2a"},
                "bridge": {"$ref": "#/definitions/bridge"},
                "custom_config": {"type": "object"}
            },
            "required": ["environment", "config_version"],
            "definitions": {
                "server": {
                    "type": "object",
                    "properties": {
                        "host": {"type": "string"},
                        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                        "max_connections": {"type": "integer", "minimum": 1},
                        "timeout": {"type": "integer", "minimum": 1},
                        "ssl_enabled": {"type": "boolean"}
                    },
                    "required": ["host", "port"]
                },
                "logging": {
                    "type": "object",
                    "properties": {
                        "level": {"type": "string", "enum": ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]},
                        "format": {"type": "string"},
                        "file": {"type": ["string", "null"]},
                        "max_size": {"type": "integer", "minimum": 1},
                        "backup_count": {"type": "integer", "minimum": 0},
                        "json_format": {"type": "boolean"}
                    }
                },
                "security": {
                    "type": "object",
                    "properties": {
                        "jwt_secret": {"type": ["string", "null"]},
                        "jwt_algorithm": {"type": "string"},
                        "jwt_expiration": {"type": "integer", "minimum": 1},
                        "api_key": {"type": ["string", "null"]},
                        "ssl_cert_path": {"type": ["string", "null"]},
                        "ssl_key_path": {"type": ["string", "null"]},
                        "allowed_origins": {"type": "array", "items": {"type": "string"}}
                    },
                    "required": ["jwt_secret", "api_key"],
                    "oneOf": [
                        {"required": ["jwt_secret"]},
                        {"required": ["api_key"]}
                    ]
                },
                "database": {
                    "type": "object",
                    "properties": {
                        "url": {"type": ["string", "null"]},
                        "host": {"type": "string"},
                        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                        "name": {"type": "string"},
                        "username": {"type": ["string", "null"]},
                        "password": {"type": ["string", "null"]},
                        "pool_size": {"type": "integer", "minimum": 1},
                        "max_overflow": {"type": "integer", "minimum": 0},
                        "pool_timeout": {"type": "integer", "minimum": 1}
                    },
                    "required": ["name"]
                },
                "mcp": {
                    "type": "object",
                    "properties": {
                        "server_name": {"type": "string"},
                        "host": {"type": "string"},
                        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                        "protocol_version": {"type": "string"},
                        "capabilities": {"type": "object"},
                        "max_request_size": {"type": "integer", "minimum": 1},
                        "request_timeout": {"type": "integer", "minimum": 1}
                    },
                    "required": ["server_name", "host", "port"]
                },
                "a2a": {
                    "type": "object",
                    "properties": {
                        "agent_name": {"type": "string"},
                        "namespace": {"type": "string"},
                        "service_url": {"type": "string", "format": "uri"},
                        "event_bus_url": {"type": "string", "format": "uri"},
                        "task_timeout": {"type": "integer", "minimum": 1},
                        "max_retries": {"type": "integer", "minimum": 0},
                        "retry_delay": {"type": "integer", "minimum": 1},
                        "storage_backend": {"type": "string"}
                    },
                    "required": ["agent_name", "namespace", "service_url"]
                },
                "bridge": {
                    "type": "object",
                    "properties": {
                        "mcp_server": {"$ref": "#/definitions/mcp"},
                        "a2a_agent": {"$ref": "#/definitions/a2a"},
                        "auto_start": {"type": "boolean"},
                        "heartbeat_interval": {"type": "integer", "minimum": 1},
                        "max_bridge_sessions": {"type": "integer", "minimum": 1},
                        "message_queue_size": {"type": "integer", "minimum": 1},
                        "metrics_enabled": {"type": "boolean"}
                    },
                    "required": ["mcp_server", "a2a_agent"]
                }
            }
        }

    def validate_config(self, config: Union[Config, Dict[str, Any]], schema_name: str = "config") -> List[ValidationError]:
        """Validate configuration against schema."""
        if isinstance(config, Config):
            config_data = config.to_dict()
        else:
            config_data = config

        errors = []

        try:
            schema = self.schemas.get(schema_name)
            if not schema:
                errors.append(ValidationError("", f"Schema '{schema_name}' not found", None))
                return errors

            jsonschema.validate(config_data, schema)
        except jsonschema.ValidationError as e:
            # Convert JSON schema error to our validation error format
            errors.append(ValidationError(
                path=".".join(str(p) for p in e.path) if e.path else "",
                message=e.message,
                value=e.instance,
                schema_path=".".join(str(p) for p in e.absolute_path) if e.absolute_path else ""
            ))
        except jsonschema.SchemaError as e:
            errors.append(ValidationError("", f"Schema error: {e.message}", None))

        # Additional custom validations
        errors.extend(self._validate_custom_rules(config_data))

        return errors

    def _validate_custom_rules(self, config_data: Dict[str, Any]) -> List[ValidationError]:
        """Apply custom validation rules."""
        errors = []

        # Check if URLs are valid
        if "a2a" in config_data:
            a2a = config_data["a2a"]
            if "service_url" in a2a and not a2a["service_url"].startswith(("http://", "https://")):
                errors.append(ValidationError(
                    "a2a.service_url",
                    "Service URL must start with http:// or https://",
                    a2a["service_url"]
                ))

        # Check database configuration
        if "database" in config_data:
            db = config_data["database"]
            if "url" not in db and "host" not in db:
                errors.append(ValidationError(
                    "database",
                    "Either URL or host must be specified for database configuration",
                    db
                ))

        # Check security configuration
        if "security" in config_data:
            security = config_data["security"]
            if not security.get("jwt_secret") and not security.get("api_key"):
                errors.append(ValidationError(
                    "security",
                    "Either JWT secret or API key must be configured",
                    security
                ))

        return errors

    def validate_file(self, file_path: Union[str, Path], schema_name: str = "config") -> List[ValidationError]:
        """Validate configuration file against schema."""
        file_path = Path(file_path)

        if not file_path.exists():
            return [ValidationError("", f"File not found: {file_path}", None)]

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                if file_path.suffix.lower() == '.json':
                    config_data = json.load(f)
                elif file_path.suffix.lower() in ['.yml', '.yaml']:
                    import yaml
                    config_data = yaml.safe_load(f)
                elif file_path.suffix.lower() == '.toml':
                    import toml
                    config_data = toml.load(f)
                else:
                    return [ValidationError("", f"Unsupported file format: {file_path.suffix}", None)]

            return self.validate_config(config_data, schema_name)
        except Exception as e:
            return [ValidationError("", f"Failed to load file: {e}", None)]

    def save_schema(self, schema_name: str, file_path: Union[str, Path]) -> None:
        """Save schema to file."""
        schema = self.schemas.get(schema_name)
        if not schema:
            raise ValueError(f"Schema '{schema_name}' not found")

        file_path = Path(file_path)
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(schema, f, indent=2)

    def add_custom_schema(self, schema_name: str, schema: Dict[str, Any]) -> None:
        """Add custom validation schema."""
        self.schemas[schema_name] = schema

    def get_schemas(self) -> Dict[str, Dict[str, Any]]:
        """Get all available schemas."""
        return self.schemas.copy()


class ConfigMigration:
    """Configuration migration utilities."""

    def __init__(self, validator: ConfigValidator):
        """Initialize migration."""
        self.validator = validator

    def migrate_config(self, config: Union[Config, Dict[str, Any]],
                      from_version: str, to_version: str) -> Dict[str, Any]:
        """Migrate configuration between versions."""
        if isinstance(config, Config):
            config_data = config.to_dict()
        else:
            config_data = config.copy()

        # Migration rules (these can be expanded as needed)
        if from_version == "0.1.0" and to_version == "0.2.0":
            # Add new fields
            if "custom_config" not in config_data:
                config_data["custom_config"] = {}

            # Update default values
            if "bridge" in config_data:
                if "metrics_enabled" not in config_data["bridge"]:
                    config_data["bridge"]["metrics_enabled"] = True

        elif from_version == "0.1.0" and to_version == "0.1.1":
            # Minor version changes
            if "logging" in config_data:
                if "json_format" not in config_data["logging"]:
                    config_data["logging"]["json_format"] = False

        return config_data

    def generate_migration_report(self, config: Union[Config, Dict[str, Any]],
                                from_version: str, to_version: str) -> Dict[str, Any]:
        """Generate migration report."""
        if isinstance(config, Config):
            config_data = config.to_dict()
        else:
            config_data = config

        report = {
            "from_version": from_version,
            "to_version": to_version,
            "original_config": config_data,
            "migrated_config": self.migrate_config(config_data, from_version, to_version),
            "changes": []
        }

        # Compare configs to detect changes
        migrated = self.migrate_config(config_data, from_version, to_version)
        report["changes"] = self._diff_configs(config_data, migrated)

        return report

    def _diff_configs(self, original: Dict[str, Any], migrated: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Compare two configurations and return differences."""
        changes = []

        def compare_dicts(orig: Dict[str, Any], mig: Dict[str, Any], path: str = ""):
            for key in set(orig.keys()) | set(mig.keys()):
                current_path = f"{path}.{key}" if path else key

                if key not in orig:
                    changes.append({
                        "type": "added",
                        "path": current_path,
                        "value": mig[key]
                    })
                elif key not in mig:
                    changes.append({
                        "type": "removed",
                        "path": current_path,
                        "value": orig[key]
                    })
                elif orig[key] != mig[key]:
                    if isinstance(orig[key], dict) and isinstance(mig[key], dict):
                        compare_dicts(orig[key], mig[key], current_path)
                    else:
                        changes.append({
                            "type": "modified",
                            "path": current_path,
                            "old_value": orig[key],
                            "new_value": mig[key]
                        })

        compare_dicts(original, migrated)
        return changes