"""
Tests for configuration API.
"""

import pytest
import asyncio
import tempfile
import json
from pathlib import Path
from unittest.mock import Mock, patch

from config.core import Config, Environment
from config.api import ConfigService, ConfigWatcher, ConfigEvent, get_config_service


class TestConfigService:
    """Test ConfigService class."""

    def test_init(self):
        """Test service initialization."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))
            assert isinstance(service.config_manager, ConfigManager)
            assert isinstance(service.validator, ConfigValidator)
            assert isinstance(service.watcher, ConfigWatcher)
            assert service._initialized is False

    @pytest.mark.asyncio
    async def test_initialize(self):
        """Test service initialization."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            await service.initialize()

            assert service._initialized is True
            assert len(service.watcher.watch_paths) > 0

    @pytest.mark.asyncio
    async def test_start_watcher(self):
        """Test starting watcher."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))
            await service.initialize()

            await service.start_watcher()

            assert service.watcher.watching is True
            assert len(service.watcher.watch_tasks) > 0

    @pytest.mark.asyncio
    async def test_stop_watcher(self):
        """Test stopping watcher."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))
            await service.initialize()
            await service.start_watcher()

            await service.stop_watcher()

            assert service.watcher.watching is False
            assert len(service.watcher.watch_tasks) == 0

    def test_load_config(self):
        """Test loading configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            config = service.load_config(Environment.DEVELOPMENT)

            assert isinstance(config, Config)
            assert config.environment == Environment.DEVELOPMENT

    def test_get_config(self):
        """Test getting configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            config = service.get_config()

            assert isinstance(config, Config)
            assert config.environment == Environment.DEVELOPMENT

    def test_validate_config(self):
        """Test validating configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            config = Config(
                environment=Environment.DEVELOPMENT,
                config_version="0.1.0",
                security={
                    "jwt_secret": "test-secret",
                    "api_key": "test-api-key"
                }
            )

            errors = service.validate_config(config)

            assert len(errors) == 0

    def test_validate_invalid_config(self):
        """Test validating invalid configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            config = Config(
                environment="invalid",  # Invalid environment
                config_version="0.1.0"
            )

            errors = service.validate_config(config)

            assert len(errors) > 0

    def test_migrate_config(self):
        """Test migrating configuration."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            config = Config(
                environment=Environment.DEVELOPMENT,
                config_version="0.1.0"
            )

            migrated = service.migrate_config(config, "0.1.0", "0.2.0")

            assert migrated.config_version == "0.2.0"

    def test_get_schema(self):
        """Test getting schema."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            schema = service.get_schema()

            assert isinstance(schema, dict)
            assert "environment" in schema

    def test_save_schema(self):
        """Test saving schema."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            schema_file = Path(temp_dir) / "schema.json"
            service.save_schema(schema_file)

            assert schema_file.exists()

            with open(schema_file, 'r') as f:
                saved_schema = json.load(f)

            assert isinstance(saved_schema, dict)
            assert "environment" in saved_schema

    @pytest.mark.asyncio
    async def test_config_context(self):
        """Test configuration context manager."""
        with tempfile.TemporaryDirectory() as temp_dir:
            service = ConfigService(Path(temp_dir))

            async with service.config_context(Environment.DEVELOPMENT) as config:
                assert isinstance(config, Config)
                assert config.environment == Environment.DEVELOPMENT


class TestConfigWatcher:
    """Test ConfigWatcher class."""

    def test_init(self):
        """Test watcher initialization."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_manager = Mock()
            watcher = ConfigWatcher(config_manager)

            assert watcher.config_manager == config_manager
            assert watcher.watching is False
            assert len(watcher.watch_tasks) == 0
            assert len(watcher.event_handlers) == 0
            assert len(watcher.watch_paths) == 0

    def test_add_watch_path(self):
        """Test adding watch path."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_manager = Mock()
            watcher = ConfigWatcher(config_manager)

            test_path = Path(temp_dir) / "config.json"
            test_path.touch()  # Create the file

            watcher.add_watch_path(test_path)

            assert len(watcher.watch_paths) == 1
            assert watcher.watch_paths[0] == test_path

    def test_add_event_handler(self):
        """Test adding event handler."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_manager = Mock()
            watcher = ConfigWatcher(config_manager)

            def handler(event):
                pass

            watcher.add_event_handler(handler)

            assert len(watcher.event_handlers) == 1
            assert watcher.event_handlers[0] == handler

    def test_notify_handlers(self):
        """Test notifying event handlers."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_manager = Mock()
            watcher = ConfigWatcher(config_manager)

            events_received = []

            def handler(event):
                events_received.append(event)

            watcher.add_event_handler(handler)

            # Create and send event
            event = ConfigEvent(
                event_type="change",
                config_path="test.json",
                timestamp=1234567890
            )

            watcher._notify_handlers(event)

            assert len(events_received) == 1
            assert events_received[0] == event

    @pytest.mark.asyncio
    async def test_watch_files_simple_polling(self):
        """Test file watching with simple polling."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_manager = Mock()
            config_manager.reload_config.return_value = Config(
                environment=Environment.DEVELOPMENT,
                config_version="0.1.0"
            )

            watcher = ConfigWatcher(config_manager)

            # Create test file
            test_file = Path(temp_dir) / "config.json"
            test_file.touch()

            watcher.add_watch_path(test_file)

            # Mock asyncio.sleep to avoid actual waiting
            with patch('asyncio.sleep', return_value=None):
                # Start watching for a short time
                task = asyncio.create_task(watcher._watch_files())

                # Let it run briefly
                await asyncio.sleep(0.1)

                # Stop the task
                task.cancel()

            # Verify config manager was called
            config_manager.reload_config.assert_called()


class TestGlobalFunctions:
    """Test global configuration functions."""

    def test_get_config_service(self):
        """Test getting global config service."""
        # Clear any existing service
        import config.api
        config.api._config_service = None

        service = get_config_service()

        assert isinstance(service, ConfigService)

        # Test that subsequent calls return the same instance
        service2 = get_config_service()
        assert service is service2

    def test_get_config(self):
        """Test getting global configuration."""
        # Clear any existing service
        import config.api
        config.api._config_service = None

        config = get_config()

        assert isinstance(config, Config)
        assert config.environment == Environment.DEVELOPMENT

    def test_validate_config(self):
        """Test validating global configuration."""
        # Clear any existing service
        import config.api
        config.api._config_service = None

        config = Config(
            environment=Environment.DEVELOPMENT,
            config_version="0.1.0",
            security={
                "jwt_secret": "test-secret",
                "api_key": "test-api-key"
            }
        )

        errors = validate_config(config)

        assert len(errors) == 0

    @pytest.mark.asyncio
    async def test_start_config_watcher(self):
        """Test starting global config watcher."""
        # Clear any existing service
        import config.api
        config.api._config_service = None

        # Mock the service methods
        with tempfile.TemporaryDirectory() as temp_dir:
            service = get_config_service(Path(temp_dir))
            service.initialize = Mock()
            service.start_watcher = Mock()

            await start_config_watcher()

            service.initialize.assert_called_once()
            service.start_watcher.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_config_watcher(self):
        """Test stopping global config watcher."""
        # Clear any existing service
        import config.api
        config.api._config_service = None

        # Create a service
        service = get_config_service()
        service.stop_watcher = Mock()

        await stop_config_watcher()

        service.stop_watcher.assert_called_once()


if __name__ == "__main__":
    pytest.main([__file__])