"""
Command-line interface for configuration management.
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Optional

from .api import get_config_service
from .core import Config, Environment
from .utils import ConfigTemplate, ConfigExporter, ConfigAnalyzer


class ConfigCLI:
    """Command-line interface for configuration management."""

    def __init__(self):
        """Initialize CLI."""
        self.parser = self._create_parser()

    def _create_parser(self) -> argparse.ArgumentParser:
        """Create argument parser."""
        parser = argparse.ArgumentParser(
            description="Craftplan MCP + A2A Configuration Manager",
            formatter_class=argparse.RawDescriptionHelpFormatter
        )

        subparsers = parser.add_subparsers(dest="command", help="Available commands")

        # Initialize command
        init_parser = subparsers.add_parser("init", help="Initialize configuration")
        init_parser.add_argument(
            "--environment", "-e",
            choices=[env.value for env in Environment],
            default="development",
            help="Environment to initialize"
        )
        init_parser.add_argument(
            "--format", "-f",
            choices=["json", "yaml", "toml"],
            default="json",
            help="Configuration file format"
        )
        init_parser.add_argument(
            "--output", "-o",
            type=Path,
            default=Path("config"),
            help="Output directory"
        )

        # Validate command
        validate_parser = subparsers.add_parser("validate", help="Validate configuration")
        validate_parser.add_argument(
            "config_file",
            type=Path,
            nargs="?",
            help="Configuration file to validate"
        )

        # Export command
        export_parser = subparsers.add_parser("export", help="Export configuration")
        export_parser.add_argument(
            "config_file",
            type=Path,
            help="Configuration file to export"
        )
        export_parser.add_argument(
            "--format", "-f",
            choices=["json", "yaml", "toml"],
            default="json",
            help="Export format"
        )
        export_parser.add_argument(
            "--output", "-o",
            type=Path,
            help="Output file path"
        )
        export_parser.add_argument(
            "--env-file",
            action="store_true",
            help="Export as environment file"
        )
        export_parser.add_argument(
            "--docker-config",
            action="store_true",
            help="Export as Docker config"
        )
        export_parser.add_argument(
            "--k8s-config",
            action="store_true",
            help="Export as Kubernetes config"
        )

        # Analyze command
        analyze_parser = subparsers.add_parser("analyze", help="Analyze configuration")
        analyze_parser.add_argument(
            "config_file",
            type=Path,
            nargs="?",
            help="Configuration file to analyze"
        )

        # Schema command
        schema_parser = subparsers.add_parser("schema", help="Get configuration schema")
        schema_parser.add_argument(
            "--format", "-f",
            choices=["json", "yaml"],
            default="json",
            help="Schema format"
        )
        schema_parser.add_argument(
            "--output", "-o",
            type=Path,
            help="Output file path"
        )

        # Watch command
        watch_parser = subparsers.add_parser("watch", help="Watch configuration files")
        watch_parser.add_argument(
            "--config-dir", "-c",
            type=Path,
            default=Path("config"),
            help="Configuration directory"
        )

        return parser

    async def run(self, args: list = None) -> int:
        """Run CLI with given arguments."""
        if args is None:
            args = sys.argv[1:]

        parsed_args = self.parser.parse_args(args)

        if not parsed_args.command:
            self.parser.print_help()
            return 1

        try:
            if parsed_args.command == "init":
                return await self._init_config(parsed_args)
            elif parsed_args.command == "validate":
                return await self._validate_config(parsed_args)
            elif parsed_args.command == "export":
                return await self._export_config(parsed_args)
            elif parsed_args.command == "analyze":
                return await self._analyze_config(parsed_args)
            elif parsed_args.command == "schema":
                return await self._show_schema(parsed_args)
            elif parsed_args.command == "watch":
                return await self._watch_config(parsed_args)
            else:
                print(f"Unknown command: {parsed_args.command}")
                return 1

        except Exception as e:
            print(f"Error: {e}")
            return 1

    async def _init_config(self, args) -> int:
        """Initialize configuration."""
        config_dir = args.output
        config_dir.mkdir(parents=True, exist_ok=True)

        # Generate template
        environment = Environment(args.environment)
        template = ConfigTemplate.generate_environment_template(environment)

        # Save template
        config_file = config_dir / f"config.{args.format}"
        ConfigTemplate.save_template(template, config_file, args.format)

        # Create additional config files
        local_config = config_dir / "config.local.json"
        ConfigTemplate.save_template({}, local_config, "json")

        print(f"Configuration initialized at: {config_file}")
        print(f"Local overrides file: {local_config}")

        return 0

    async def _validate_config(self, args) -> int:
        """Validate configuration."""
        config_file = args.config_file
        if config_file is None:
            # Use default config manager
            service = get_config_service()
            config = service.get_config()
            errors = service.validate_config(config)
        else:
            from .validator import ConfigValidator
            validator = ConfigValidator()
            errors = validator.validate_file(config_file)

        if errors:
            print("Configuration validation errors:")
            for error in errors:
                print(f"  - {error}")
            return 1
        else:
            print("Configuration is valid")
            return 0

    async def _export_config(self, args) -> int:
        """Export configuration."""
        # Load configuration
        service = get_config_service()
        config = service.get_config()

        if args.env_file:
            output_file = args.output or Path(".env")
            ConfigExporter.export_env_file(config, output_file, config.environment)
            print(f"Environment file exported to: {output_file}")
        elif args.docker_config:
            output_file = args.output or Path("docker.json")
            ConfigExporter.export_docker_config(config, output_file)
            print(f"Docker config exported to: {output_file}")
        elif args.k8s_config:
            output_file = args.output or Path("k8s.json")
            ConfigExporter.export_k8s_config(config, output_file)
            print(f"Kubernetes config exported to: {output_file}")
        else:
            output_file = args.output or f"config.{args.format}"
            ConfigExporter.export_config(config, Path(output_file), args.format)
            print(f"Configuration exported to: {output_file}")

        return 0

    async def _analyze_config(self, args) -> int:
        """Analyze configuration."""
        config_file = args.config_file
        if config_file is None:
            # Use default config
            service = get_config_service()
            config = service.get_config()
        else:
            # Load from file
            from .loader import ConfigLoader
            loader = ConfigLoader()
            config = loader.load_file(config_file)

        analysis = ConfigAnalyzer.analyze_config(config)

        print("Configuration Analysis:")
        print(f"  Environment: {analysis['environment']}")
        print(f"  Security Score: {analysis['security_score']}/100")
        print(f"  Performance Score: {analysis['performance_score']}/100")
        print(f"  Complexity Score: {analysis['complexity_score']}/100")

        if analysis['recommendations']:
            print("\nRecommendations:")
            for rec in analysis['recommendations']:
                print(f"  - {rec}")

        return 0

    async def _show_schema(self, args) -> int:
        """Show configuration schema."""
        service = get_config_service()
        schema = service.get_schema()

        if args.output:
            output_file = args.output
            if args.format == "json":
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump(schema, f, indent=2)
            else:
                import yaml
                with open(output_file, 'w', encoding='utf-8') as f:
                    yaml.dump(schema, f, default_flow_style=False)
            print(f"Schema exported to: {output_file}")
        else:
            if args.format == "json":
                print(json.dumps(schema, indent=2))
            else:
                import yaml
                print(yaml.dump(schema, default_flow_style=False))

        return 0

    async def _watch_config(self, args) -> int:
        """Watch configuration files."""
        from .api import get_config_service, start_config_watcher

        service = get_config_service(args.config_dir)
        await service.initialize()
        await start_config_watcher()

        print(f"Watching configuration files in: {args.config_dir}")
        print("Press Ctrl+C to stop watching...")

        try:
            # Keep the program running
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            print("\nStopping configuration watcher...")
            await stop_config_watcher()
            return 0


async def main():
    """Main entry point."""
    cli = ConfigCLI()
    exit_code = await cli.run()
    sys.exit(exit_code)


if __name__ == "__main__":
    asyncio.run(main())