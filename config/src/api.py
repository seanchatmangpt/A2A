"""
Configuration API and utilities.
"""

import os
import asyncio
import logging
from typing import Any, Dict, List, Optional, Union, Callable
from pathlib import Path
from dataclasses import dataclass
from contextlib import asynccontextmanager

from .core import Config, Environment, ServerConfig, LogConfig, SecurityConfig, DatabaseConfig, MCPConfig, A2AConfig, BridgeConfig
from .loader import ConfigManager
from .validator import ConfigValidator, ConfigMigration

logger = logging.getLogger(__name__)


@dataclass
class ConfigEvent:
    """Configuration change event."""
    event_type: str  # "change", "reload", "error"
    config_path: Optional[str] = None
    old_config: Optional[Config] = None
    new_config: Optional[Config] = None
    error: Optional[str] = None
    timestamp: Optional[float] = None


class ConfigWatcher:
    """Configuration file watcher with auto-reload."""

    def __init__(self, config_manager: ConfigManager):
        """Initialize config watcher."""
        self.config_manager = config_manager
        self.watching = False
        self.watch_tasks: List[asyncio.Task] = []
        self.event_handlers: List[Callable[[ConfigEvent], None]] = []
        self.watch_paths: List[Path] = []

    def add_watch_path(self, path: Union[str, Path]) -> None:
        """Add path to watch for changes."""
        path = Path(path)
        if path.exists() and path not in self.watch_paths:
            self.watch_paths.append(path)

    def add_event_handler(self, handler: Callable[[ConfigEvent], None]) -> None:
        """Add event handler for configuration changes."""
        self.event_handlers.append(handler)

    def _notify_handlers(self, event: ConfigEvent) -> None:
        """Notify all event handlers."""
        for handler in self.event_handlers:
            try:
                handler(event)
            except Exception as e:
                logger.error(f"Event handler error: {e}")

    async def _watch_files(self) -> None:
        """Watch configuration files for changes."""
        import aiofiles
        import time
        from watchdog.observers import Observer
        from watchdog.events import FileSystemEventHandler

        class ConfigFileHandler(FileSystemEventHandler):
            def __init__(self, watcher: ConfigWatcher):
                self.watcher = watcher
                self.last_triggered = 0
                self.debounce_interval = 2.0  # seconds

            def on_modified(self, event):
                if time.time() - self.last_triggered > self.debounce_interval:
                    self.last_triggered = time.time()
                    asyncio.create_task(self._handle_change(event))

            async def _handle_change(self, event):
                if event.is_directory:
                    return

                file_path = Path(event.src_path)
                if file_path.suffix.lower() in ['.json', '.yml', '.yaml', '.toml']:
                    try:
                        logger.info(f"Configuration file changed: {file_path}")
                        new_config = self.watcher.config_manager.reload_config()

                        change_event = ConfigEvent(
                            event_type="change",
                            config_path=str(file_path),
                            old_config=self.watcher.config_manager._current_config,
                            new_config=new_config,
                            timestamp=time.time()
                        )
                        self.watcher._notify_handlers(change_event)
                    except Exception as e:
                        error_event = ConfigEvent(
                            event_type="error",
                            config_path=str(file_path),
                            error=str(e),
                            timestamp=time.time()
                        )
                        self.watcher._notify_handlers(error_event)

        if not self.watch_paths:
            return

        # Fallback: simple file polling
        while self.watching:
            try:
                current_time = time.time()
                for path in self.watch_paths:
                    if path.exists():
                        stat = path.stat()
                        if hasattr(self, f"_last_modified_{path.name}"):
                            last_modified = getattr(self, f"_last_modified_{path.name}")
                            if stat.st_mtime > last_modified:
                                setattr(self, f"_last_modified_{path.name}", stat.st_mtime)

                                new_config = self.config_manager.reload_config()

                                change_event = ConfigEvent(
                                    event_type="change",
                                    config_path=str(path),
                                    old_config=self.config_manager._current_config,
                                    new_config=new_config,
                                    timestamp=current_time
                                )
                                self._notify_handlers(change_event)
                        else:
                            setattr(self, f"_last_modified_{path.name}", stat.st_mtime)

                await asyncio.sleep(5)  # Check every 5 seconds
            except Exception as e:
                logger.error(f"Error watching files: {e}")
                await asyncio.sleep(5)

    async def start_watching(self) -> None:
        """Start watching configuration files."""
        if self.watching:
            return

        self.watching = True
        task = asyncio.create_task(self._watch_files())
        self.watch_tasks.append(task)
        logger.info(f"Started watching {len(self.watch_paths)} configuration files")

    async def stop_watching(self) -> None:
        """Stop watching configuration files."""
        self.watching = False
        for task in self.watch_tasks:
            task.cancel()
        self.watch_tasks.clear()
        logger.info("Stopped watching configuration files")


class ConfigService:
    """High-level configuration service with all features."""

    def __init__(self, config_dir: Path = None):
        """Initialize configuration service."""
        self.config_manager = ConfigManager(config_dir)
        self.validator = ConfigValidator()
        self.migration = ConfigMigration(self.validator)
        self.watcher = ConfigWatcher(self.config_manager)
        self._initialized = False

    async def initialize(self) -> None:
        """Initialize configuration service."""
        if self._initialized:
            return

        # Load initial configuration
        self.config_manager.load_config()

        # Add watch paths
        config_dir = self.config_manager.loader.sources[0].path.parent
        self.watcher.add_watch_path(config_dir)

        # Set up event handlers
        self.watcher.add_event_handler(self._handle_config_event)

        self._initialized = True
        logger.info("Configuration service initialized")

    def _handle_config_event(self, event: ConfigEvent) -> None:
        """Handle configuration events."""
        if event.event_type == "error":
            logger.error(f"Configuration error: {event.error}")
        elif event.event_type == "change":
            logger.info(f"Configuration reloaded from {event.config_path}")

    async def start_watcher(self) -> None:
        """Start configuration watcher."""
        await self.watcher.start_watching()

    async def stop_watcher(self) -> None:
        """Stop configuration watcher."""
        await self.watcher.stop_watching()

    def load_config(self, environment: Environment = None) -> Config:
        """Load configuration."""
        return self.config_manager.load_config(environment)

    def get_config(self) -> Config:
        """Get current configuration."""
        return self.config_manager.get_config()

    def reload_config(self) -> Config:
        """Reload current configuration."""
        return self.config_manager.reload_config()

    def validate_config(self, config: Union[Config, Dict[str, Any]] = None) -> List[str]:
        """Validate configuration."""
        if config is None:
            config = self.get_config()

        validation_errors = self.validator.validate_config(config)
        return [f"{error.path}: {error.message}" for error in validation_errors]

    def migrate_config(self, config: Config, from_version: str, to_version: str) -> Config:
        """Migrate configuration."""
        migrated_data = self.migration.migrate_config(config, from_version, to_version)
        return self.config_manager.config_class.from_dict(migrated_data)

    def generate_migration_report(self, config: Config, from_version: str, to_version: str) -> Dict[str, Any]:
        """Generate migration report."""
        return self.migration.generate_migration_report(config, from_version, to_version)

    def get_schema(self) -> Dict[str, Any]:
        """Get configuration schema."""
        return self.config_manager.get_schema()

    def save_schema(self, file_path: Path) -> None:
        """Save configuration schema to file."""
        schema = self.get_schema()
        import json
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(schema, f, indent=2)

    @asynccontextmanager
    async def config_context(self, environment: Environment = None):
        """Context manager for configuration with auto-reload."""
        await self.initialize()
        if environment:
            config = self.load_config(environment)
        else:
            config = self.get_config()

        try:
            yield config
        finally:
            pass


# Global configuration service instance
_config_service: Optional[ConfigService] = None


def get_config_service(config_dir: Path = None) -> ConfigService:
    """Get global configuration service instance."""
    global _config_service
    if _config_service is None:
        _config_service = ConfigService(config_dir)
    return _config_service


def get_config() -> Config:
    """Get global configuration."""
    return get_config_service().get_config()


def validate_config(config: Union[Config, Dict[str, Any]] = None) -> List[str]:
    """Validate configuration using global service."""
    return get_config_service().validate_config(config)


async def start_config_watcher() -> None:
    """Start global configuration watcher."""
    service = get_config_service()
    await service.initialize()
    await service.start_watcher()


async def stop_config_watcher() -> None:
    """Stop global configuration watcher."""
    if _config_service:
        await _config_service.stop_watcher()