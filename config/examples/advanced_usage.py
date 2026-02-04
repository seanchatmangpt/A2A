"""
Advanced usage examples for the A2A Configuration System.
"""

import asyncio
import json
from pathlib import Path
from typing import Dict, Any

from config.api import (
    get_config_service,
    ConfigService,
    ConfigWatcher,
    ConfigEvent,
    start_config_watcher,
    stop_config_watcher,
)
from config.core import Config, Environment
from config.utils import (
    ConfigTemplate,
    ConfigExporter,
    ConfigHelpers,
    ConfigAnalyzer,
)


class ConfigurationManager:
    """Advanced configuration manager example."""

    def __init__(self, config_dir: Path):
        """Initialize configuration manager."""
        self.config_dir = config_dir
        self.service = ConfigService(config_dir)
        self.watcher = None
        self.config_cache = {}

    async def initialize(self):
        """Initialize configuration manager."""
        await self.service.initialize()

        # Setup watcher
        self.watcher = ConfigWatcher(self.service.config_manager)
        self.watcher.add_watch_path(self.config_dir)
        self.watcher.add_event_handler(self._handle_config_change)

        # Load initial configuration
        self._cache_config()
        print(f"Configuration manager initialized with config from {self.config_dir}")

    def _cache_config(self):
        """Cache current configuration."""
        config = self.service.get_config()
        self.config_cache[config.environment.value] = config
        return config

    async def _handle_config_change(self, event: ConfigEvent):
        """Handle configuration change events."""
        if event.event_type == "change":
            print(f"\n🔄 Configuration changed: {event.config_path}")

            # Analyze changes
            if event.old_config and event.new_config:
                old_flat = ConfigHelpers.flatten_config(event.old_config)
                new_flat = ConfigHelpers.flatten_config(event.new_config)

                changed_keys = set(old_flat.keys()) | set(new_flat.keys())
                for key in changed_keys:
                    if key in old_flat and key in new_flat:
                        if old_flat[key] != new_flat[key]:
                            print(f"  Changed: {key} = {old_flat[key]} → {new_flat[key]}")
                    elif key in old_flat:
                        print(f"  Removed: {key} = {old_flat[key]}")
                    else:
                        print(f"  Added: {key} = {new_flat[key]}")

            # Cache new configuration
            self._cache_config()

            # Validate new configuration
            errors = self.service.validate_config()
            if errors:
                print(f"  ❌ Validation errors: {len(errors)}")
                for error in errors[:3]:  # Show first 3 errors
                    print(f"     - {error}")
            else:
                print(f"  ✅ Configuration is valid")

    async def start_watching(self):
        """Start watching configuration files."""
        if self.watcher:
            await self.watcher.start_watching()
            print("👀 Configuration watcher started")

    async def stop_watching(self):
        """Stop watching configuration files."""
        if self.watcher:
            await self.watcher.stop_watching()
            print("🛑 Configuration watcher stopped")

    def get_config(self, environment: Environment = None) -> Config:
        """Get configuration for environment."""
        if environment is None:
            return self.service.get_config()

        env_key = environment.value
        if env_key in self.config_cache:
            return self.config_cache[env_key]

        return self.service.load_config(environment)

    def export_config(self, config: Config, format: str = "json", output_path: Path = None):
        """Export configuration to file."""
        if output_path is None:
            output_path = self.config_dir / f"exported_config.{format}"

        ConfigExporter.export_config(config, output_path, format)
        print(f"📁 Configuration exported to {output_path}")

    def analyze_config(self, config: Config = None) -> Dict[str, Any]:
        """Analyze configuration and return report."""
        if config is None:
            config = self.service.get_config()

        analysis = ConfigAnalyzer.analyze_config(config)
        return analysis

    def generate_migration_report(self, from_version: str, to_version: str) -> Dict[str, Any]:
        """Generate migration report."""
        config = self.service.get_config()
        return self.service.migration.generate_migration_report(config, from_version, to_version)

    def create_environment_config(self, environment: Environment) -> Path:
        """Create environment-specific configuration."""
        template = ConfigTemplate.generate_environment_template(environment)

        config_file = self.config_dir / environment.value / "config.json"
        ConfigTemplate.save_template(template, config_file, "json")

        print(f"🎨 Created environment config: {config_file}")
        return config_file

    def create_backup(self, config: Config = None):
        """Create configuration backup."""
        if config is None:
            config = self.service.get_config()

        backup_path = self.config_dir / "backups"
        backup_path.mkdir(exist_ok=True)

        from datetime import datetime
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_file = backup_path / f"config_backup_{timestamp}.json"

        ConfigHelpers.create_backup(config, backup_file)
        print(f"💾 Backup created: {backup_file}")
        return backup_file

    def get_config_diff(self, env1: Environment, env2: Environment) -> Dict[str, Any]:
        """Compare configurations between environments."""
        config1 = self.get_config(env1)
        config2 = self.get_config(env2)

        flat1 = ConfigHelpers.flatten_config(config1)
        flat2 = ConfigHelpers.flatten_config(config2)

        # Find differences
        all_keys = set(flat1.keys()) | set(flat2.keys())
        differences = {
            "added": [],
            "removed": [],
            "changed": []
        }

        for key in all_keys:
            if key in flat1 and key in flat2:
                if flat1[key] != flat2[key]:
                    differences["changed"].append({
                        "key": key,
                        "old_value": flat1[key],
                        "new_value": flat2[key]
                    })
            elif key in flat1:
                differences["removed"].append({
                    "key": key,
                    "value": flat1[key]
                })
            else:
                differences["added"].append({
                    "key": key,
                    "value": flat2[key]
                })

        return differences


async def main():
    """Main example usage."""
    # Setup configuration directory
    config_dir = Path("example_config")

    # Create configuration manager
    manager = ConfigurationManager(config_dir)
    await manager.initialize()

    # Start watching
    await manager.start_watching()

    try:
        # Example operations
        print("\n=== Configuration Management Demo ===")

        # Get configuration
        config = manager.get_config()
        print(f"📍 Environment: {config.environment.value}")
        print(f"🌐 Server: {config.server.host}:{config.server.port}")

        # Analyze configuration
        analysis = manager.analyze_config()
        print(f"\n📊 Configuration Analysis:")
        print(f"   Security Score: {analysis['security_score']}/100")
        print(f"   Performance Score: {analysis['performance_score']}/100")
        print(f"   Complexity Score: {analysis['complexity_score']}/100")

        if analysis['recommendations']:
            print(f"   Recommendations:")
            for rec in analysis['recommendations']:
                print(f"     • {rec}")

        # Export configurations
        print("\n📤 Exporting configurations:")
        manager.export_config(config, "json", config_dir / "config_export.json")
        manager.export_config(config, "yaml", config_dir / "config_export.yaml")
        manager.export_env_file(config, config_dir / ".env")

        # Create backup
        backup = manager.create_backup()

        # Create different environment configs
        print("\n🏗️ Creating environment configurations:")
        dev_config = manager.create_environment_config(Environment.DEVELOPMENT)
        prod_config = manager.create_environment_config(Environment.PRODUCTION)

        # Compare environments
        diff = manager.get_config_diff(Environment.DEVELOPMENT, Environment.PRODUCTION)
        print(f"\n🔍 Environment Differences:")
        print(f"   Added keys: {len(diff['added'])}")
        print(f"   Removed keys: {len(diff['removed'])}")
        print(f"   Changed keys: {len(diff['changed'])}")

        if diff['changed']:
            print("   Changes:")
            for change in diff['changed'][:3]:  # Show first 3 changes
                print(f"     • {change['key']}: {change['old_value']} → {change['new_value']}")

        # Wait for configuration changes (simulated)
        print("\n⏳ Waiting for configuration changes...")
        print("   Try modifying the configuration files in the 'example_config' directory!")

        # Wait for 30 seconds to allow file watching
        await asyncio.sleep(30)

    finally:
        # Cleanup
        await manager.stop_watching()
        print("\n🔚 Configuration manager shutdown")


async def example_service_usage():
    """Example using global service."""
    print("\n=== Global Service Usage ===")

    # Start global configuration watcher
    await start_config_watcher()

    try:
        # Get configuration
        config = get_config()
        print(f"📍 Environment: {config.environment.value}")

        # Validate configuration
        errors = validate_config()
        if errors:
            print("❌ Validation errors:")
            for error in errors:
                print(f"   - {error}")
        else:
            print("✅ Configuration is valid")

        # Wait a bit
        await asyncio.sleep(10)

    finally:
        # Stop watcher
        await stop_config_watcher()


async def example_templates():
    """Example configuration templates."""
    print("\n=== Configuration Templates ===")

    # Generate templates for different environments
    for env in Environment:
        template = ConfigTemplate.generate_environment_template(env)
        print(f"\n📋 {env.value.title()} Template:")
        print(f"   Server: {template['server']['host']}:{template['server']['port']}")
        print(f"   Logging Level: {template['logging']['level']}")
        print(f"   SSL Enabled: {template['server']['ssl_enabled']}")

        # Save template
        template_dir = Path(f"templates/{env.value}")
        template_dir.mkdir(exist_ok=True)
        ConfigTemplate.save_template(template, template_dir / "config.json", "json")


def example_configuration_analysis():
    """Example configuration analysis."""
    print("\n=== Configuration Analysis ===")

    # Create sample configuration
    config = Config(
        environment=Environment.PRODUCTION,
        server={
            "host": "0.0.0.0",
            "port": 8443,
            "ssl_enabled": True
        },
        logging={
            "level": "INFO",
            "json_format": True
        },
        security={
            "jwt_secret": "secure-secret-key",
            "api_key": "secure-api-key",
            "allowed_origins": ["https://example.com"]
        }
    )

    # Analyze configuration
    analyzer = ConfigAnalyzer()
    analysis = analyzer.analyze_config(config)

    print("📊 Analysis Results:")
    print(f"   Environment: {analysis['environment']}")
    print(f"   Security Score: {analysis['security_score']}/100")
    print(f"   Performance Score: {analysis['performance_score']}/100")
    print(f"   Complexity Score: {analysis['complexity_score']}/100")

    print("\n🎯 Recommendations:")
    for rec in analysis['recommendations']:
        print(f"   • {rec}")


if __name__ == "__main__":
    print("🚀 A2A Configuration System - Advanced Usage Examples")
    print("=" * 60)

    # Run examples
    asyncio.run(main())
    asyncio.run(example_service_usage())
    asyncio.run(example_templates())
    example_configuration_analysis()

    print("\n✅ All examples completed!")