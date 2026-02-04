"""
Tests for configuration loader.
"""

import pytest
import tempfile
import json
import yaml
import toml
from pathlib import Path

from config.core import Config, Environment
from config.loader import ConfigLoader, ConfigManager


class TestConfigLoader:
    """Test ConfigLoader class."""

    def test_init(self):
        """Test loader initialization."""
        loader = ConfigLoader()
        assert loader.config_class == Config
        assert len(loader.sources) == 0

    def test_add_source(self):
        """Test adding configuration source."""
        loader = ConfigLoader()

        # Add a JSON source
        loader.add_source("test.json", "json", priority=50)

        assert len(loader.sources) == 1
        assert loader.sources[0].path == Path("test.json")
        assert loader.sources[0].format.value == "json"
        assert loader.sources[0].priority == 50

    def test_add_default_sources(self):
        """Test adding default sources."""
        with tempfile.TemporaryDirectory() as temp_dir:
            loader = ConfigLoader()
            loader.add_default_sources(Path(temp_dir))

            # Should add multiple sources
            assert len(loader.sources) > 0

    def test_load_json(self):
        """Test loading JSON configuration."""
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

            # Load configuration
            loader = ConfigLoader()
            loader.add_source(f.name, "json")
            config = loader.load()

            assert config.environment == Environment.DEVELOPMENT
            assert config.server.host == "localhost"
            assert config.server.port == 8080

            # Clean up
            Path(f.name).unlink()

    def test_load_yaml(self):
        """Test loading YAML configuration."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            config_data = {
                "environment": "production",
                "config_version": "0.1.0",
                "server": {
                    "host": "0.0.0.0",
                    "port": 8443
                }
            }
            yaml.dump(config_data, f)
            f.flush()

            # Load configuration
            loader = ConfigLoader()
            loader.add_source(f.name, "yaml")
            config = loader.load(Environment.PRODUCTION)

            assert config.environment == Environment.PRODUCTION
            assert config.server.host == "0.0.0.0"
            assert config.server.port == 8443

            # Clean up
            Path(f.name).unlink()

    def test_load_toml(self):
        """Test loading TOML configuration."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as f:
            config_data = {
                "environment": "testing",
                "config_version": "0.1.0",
                "server": {
                    "host": "localhost",
                    "port": 8080
                }
            }
            toml.dump(config_data, f)
            f.flush()

            # Load configuration
            loader = ConfigLoader()
            loader.add_source(f.name, "toml")
            config = loader.load(Environment.TESTING)

            assert config.environment == Environment.TESTING
            assert config.server.host == "localhost"
            assert config.server.port == 8080

            # Clean up
            Path(f.name).unlink()

    def test_load_nonexistent_file(self):
        """Test loading non-existent file."""
        loader = ConfigLoader()
        loader.add_source("nonexistent.json", "json", required=False)

        # Should return default configuration
        config = loader.load()
        assert config.environment == Environment.DEVELOPMENT

    def test_load_required_file(self):
        """Test loading required non-existent file."""
        loader = ConfigLoader()
        loader.add_source("nonexistent.json", "json", required=True)

        # Should raise FileNotFoundError
        with pytest.raises(FileNotFoundError):
            loader.load()

    def test_merge_configs(self):
        """Test configuration merging."""
        loader = ConfigLoader()

        base = {
            "server": {
                "host": "localhost",
                "port": 8080
            }
        }

        override = {
            "server": {
                "port": 9090,
                "ssl_enabled": True
            },
            "logging": {
                "level": "DEBUG"
            }
        }

        merged = loader._merge_configs(base, override)

        assert merged["server"]["host"] == "localhost"
        assert merged["server"]["port"] == 9090
        assert merged["server"]["ssl_enabled"] is True
        assert merged["logging"]["level"] == "DEBUG"

    def test_apply_environment_overrides(self):
        """Test environment variable overrides."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create test configuration
            config_file = Path(temp_dir) / "config.json"
            config_data = {
                "environment": "development",
                "config_version": "0.1.0",
                "server": {
                    "host": "localhost",
                    "port": 8080
                }
            }
            with open(config_file, 'w') as f:
                json.dump(config_data, f)

            # Set environment variables
            import os
            os.environ["DEVELOPMENT_SERVER_PORT"] = "9090"
            os.environ["DEVELOPMENT_LOGGING_LEVEL"] = "DEBUG"

            # Load configuration
            loader = ConfigLoader()
            loader.add_source(config_file, "json")
            config = loader.load(Environment.DEVELOPMENT)

            assert config.server.port == 9090
            assert config.logging.level == "DEBUG"

            # Clean up environment variables
            del os.environ["DEVELOPMENT_SERVER_PORT"]
            del os.environ["DEVELOPMENT_LOGGING_LEVEL"]

    def test_get_schema(self):
        """Test getting configuration schema."""
        loader = ConfigLoader()
        schema = loader.get_schema()

        assert isinstance(schema, dict)
        assert "environment" in schema
        assert "server" in schema
        assert "logging" in schema


class TestConfigManager:
    """Test ConfigManager class."""

    def test_init(self):
        """Test manager initialization."""
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = ConfigManager(Path(temp_dir))
            assert isinstance(manager.loader, ConfigLoader)

    def test_load_config(self):
        """Test loading configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create test configuration
            config_file = Path(temp_dir) / "config.json"
            config_data = {
                "environment": "production",
                "config_version": "0.1.0",
                "server": {
                    "host": "0.0.0.0",
                    "port": 8443
                }
            }
            with open(config_file, 'w') as f:
                json.dump(config_data, f)

            # Load configuration
            manager = ConfigManager(Path(temp_dir))
            config = manager.load_config(Environment.PRODUCTION)

            assert config.environment == Environment.PRODUCTION
            assert config.server.host == "0.0.0.0"
            assert config.server.port == 8443

    def test_get_config(self):
        """Test getting current configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = ConfigManager(Path(temp_dir))
            config = manager.get_config()

            assert isinstance(config, Config)
            assert config.environment == Environment.DEVELOPMENT

    def test_reload_config(self):
        """Test reloading configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create initial configuration
            config_file = Path(temp_dir) / "config.json"
            config_data = {
                "environment": "development",
                "config_version": "0.1.0",
                "server": {
                    "host": "localhost",
                    "port": 8080
                }
            }
            with open(config_file, 'w') as f:
                json.dump(config_data, f)

            # Load configuration
            manager = ConfigManager(Path(temp_dir))
            config1 = manager.get_config()

            # Update configuration file
            config_data["server"]["port"] = 9090
            with open(config_file, 'w') as f:
                json.dump(config_data, f)

            # Reload configuration
            config2 = manager.reload_config()

            assert config1.server.port == 8080
            assert config2.server.port == 9090

    def test_add_custom_source(self):
        """Test adding custom source."""
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = ConfigManager(Path(temp_dir))

            # Add custom source
            custom_file = Path(temp_dir) / "custom.json"
            with open(custom_file, 'w') as f:
                json.dump({"test": "value"}, f)

            manager.add_custom_source(custom_file, "json", priority=200)

            # Should have the custom source
            assert len(manager.loader.sources) > 0

    def test_get_schema(self):
        """Test getting schema."""
        with tempfile.TemporaryDirectory() as temp_dir:
            manager = ConfigManager(Path(temp_dir))
            schema = manager.get_schema()

            assert isinstance(schema, dict)
            assert "environment" in schema


if __name__ == "__main__":
    pytest.main([__file__])