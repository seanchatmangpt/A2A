"""
Tests for configuration validator.
"""

import pytest
import tempfile
import json
from pathlib import Path

from config.core import Config, Environment
from config.validator import ConfigValidator, ConfigMigration, ValidationError


class TestConfigValidator:
    """Test ConfigValidator class."""

    def test_init(self):
        """Test validator initialization."""
        validator = ConfigValidator()
        assert len(validator.schemas) > 0
        assert "config" in validator.schemas

    def test_validate_valid_config(self):
        """Test validating a valid configuration."""
        validator = ConfigValidator()

        config = Config(
            environment=Environment.DEVELOPMENT,
            config_version="0.1.0",
            server={
                "host": "localhost",
                "port": 8080
            },
            security={
                "jwt_secret": "test-secret",
                "jwt_algorithm": "HS256",
                "jwt_expiration": 3600,
                "api_key": "test-api-key"
            }
        )

        errors = validator.validate_config(config)
        assert len(errors) == 0

    def test_validate_invalid_config(self):
        """Test validating an invalid configuration."""
        validator = ConfigValidator()

        config = Config(
            environment="invalid",  # Invalid environment
            config_version="0.1.0"
        )

        errors = validator.validate_config(config)
        assert len(errors) > 0

    def test_validate_file(self):
        """Test validating configuration file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            config_data = {
                "environment": "development",
                "config_version": "0.1.0",
                "server": {
                    "host": "localhost",
                    "port": 8080
                }
            }
            json.dump(config_data, f)
            f.flush()

            validator = ConfigValidator()
            errors = validator.validate_file(f.name)

            assert len(errors) == 0

            # Clean up
            Path(f.name).unlink()

    def test_validate_nonexistent_file(self):
        """Test validating non-existent file."""
        validator = ConfigValidator()
        errors = validator.validate_file("nonexistent.json")

        assert len(errors) > 0
        assert "File not found" in errors[0]

    def test_validate_invalid_format(self):
        """Test validating invalid file format."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write("invalid content")
            f.flush()

            validator = ConfigValidator()
            errors = validator.validate_file(f.name)

            assert len(errors) > 0
            assert "Unsupported file format" in errors[0]

            # Clean up
            Path(f.name).unlink()

    def test_custom_validation_rules(self):
        """Test custom validation rules."""
        validator = ConfigValidator()

        config_data = {
            "environment": "development",
            "config_version": "0.1.0",
            "a2a": {
                "service_url": "invalid-url"  # Invalid URL
            }
        }

        errors = validator.validate_config(config_data)
        assert len(errors) > 0
        assert "Service URL must start with http:// or https://" in errors[0]

    def test_save_schema(self):
        """Test saving schema to file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            validator = ConfigValidator()
            validator.save_schema("config", Path(f.name))

            # Verify file was created and contains schema
            with open(f.name, 'r') as read_f:
                schema = json.load(read_f)
                assert "$schema" in schema
                assert "type" in schema
                assert "properties" in schema

            # Clean up
            Path(f.name).unlink()

    def test_add_custom_schema(self):
        """Test adding custom schema."""
        validator = ConfigValidator()

        custom_schema = {
            "type": "object",
            "properties": {
                "custom_field": {"type": "string"}
            }
        }

        validator.add_custom_schema("custom", custom_schema)
        assert "custom" in validator.schemas
        assert validator.schemas["custom"]["properties"]["custom_field"]["type"] == "string"

    def test_get_schemas(self):
        """Test getting all schemas."""
        validator = ConfigValidator()
        schemas = validator.get_schemas()

        assert isinstance(schemas, dict)
        assert "config" in schemas


class TestConfigMigration:
    """Test ConfigMigration class."""

    def test_init(self):
        """Test migration initialization."""
        validator = ConfigValidator()
        migration = ConfigMigration(validator)

        assert migration.validator == validator

    def test_migrate_config_same_version(self):
        """Test migrating config with same version."""
        validator = ConfigValidator()
        migration = ConfigMigration(validator)

        config = Config(
            environment=Environment.DEVELOPMENT,
            config_version="0.1.0"
        )

        migrated = migration.migrate_config(config, "0.1.0", "0.1.0")
        assert migrated.config_version == "0.1.0"

    def test_migrate_config_0_1_0_to_0_1_1(self):
        """Test migrating from 0.1.0 to 0.1.1."""
        validator = ConfigValidator()
        migration = ConfigMigration(validator)

        config = Config(
            environment=Environment.DEVELOPMENT,
            config_version="0.1.0",
            logging={},
            bridge={}
        )

        migrated = migration.migrate_config(config, "0.1.0", "0.1.1")

        # Should add missing fields
        assert "logging" in migrated.to_dict()
        assert "json_format" in migrated.to_dict()["logging"]
        assert "bridge" in migrated.to_dict()
        assert "metrics_enabled" in migrated.to_dict()["bridge"]

    def test_migrate_config_0_1_0_to_0_2_0(self):
        """Test migrating from 0.1.0 to 0.2.0."""
        validator = ConfigValidator()
        migration = ConfigMigration(validator)

        config = Config(
            environment=Environment.DEVELOPMENT,
            config_version="0.1.0"
        )

        migrated = migration.migrate_config(config, "0.1.0", "0.2.0")

        # Should add custom_config if not present
        assert "custom_config" in migrated.to_dict()

    def test_generate_migration_report(self):
        """Test generating migration report."""
        validator = ConfigValidator()
        migration = ConfigMigration(validator)

        config = Config(
            environment=Environment.DEVELOPMENT,
            config_version="0.1.0"
        )

        report = migration.generate_migration_report(config, "0.1.0", "0.2.0")

        assert report["from_version"] == "0.1.0"
        assert report["to_version"] == "0.2.0"
        assert "original_config" in report
        assert "migrated_config" in report
        assert "changes" in report

    def test_diff_configs(self):
        """Test comparing two configurations."""
        validator = ConfigValidator()
        migration = ConfigMigration(validator)

        original = {
            "server": {"host": "localhost", "port": 8080},
            "logging": {"level": "INFO"}
        }

        migrated = {
            "server": {"host": "localhost", "port": 9090},
            "logging": {"level": "DEBUG"},
            "custom_config": {}
        }

        changes = migration._diff_configs(original, migrated)

        # Should detect port change, level change, and custom_config addition
        assert len(changes) == 3
        assert any(change["type"] == "modified" and change["path"] == "server.port" for change in changes)
        assert any(change["type"] == "modified" and change["path"] == "logging.level" for change in changes)
        assert any(change["type"] == "added" and change["path"] == "custom_config" for change in changes)


class TestValidationError:
    """Test ValidationError class."""

    def test_validation_error_creation(self):
        """Test creating validation error."""
        error = ValidationError(
            path="server.port",
            message="Invalid port number",
            value=70000,
            schema_path="definitions.server.properties.port"
        )

        assert error.path == "server.port"
        assert error.message == "Invalid port number"
        assert error.value == 70000
        assert error.schema_path == "definitions.server.properties.port"

    def test_validation_error_without_schema_path(self):
        """Test creating validation error without schema path."""
        error = ValidationError(
            path="logging.level",
            message="Invalid log level",
            value="INVALID"
        )

        assert error.path == "logging.level"
        assert error.message == "Invalid log level"
        assert error.value == "INVALID"
        assert error.schema_path == ""


if __name__ == "__main__":
    pytest.main([__file__])