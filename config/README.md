# A2A Configuration System

A comprehensive configuration system for integrating Craftplan MCP + A2A with elrmcp.

## Features

- **Hierarchical Configuration**: Multi-level configuration with environment support
- **Multiple Formats**: Support for JSON, YAML, and TOML
- **Environment Variables**: Override configuration with environment variables
- **Dynamic Reloading**: Watch configuration files for changes
- **Validation**: JSON Schema validation with custom rules
- **Migration**: Configuration migration between versions
- **Templates**: Pre-configured templates for different environments
- **CLI Tools**: Command-line interface for configuration management
- **Analysis**: Configuration analysis and recommendations

## Installation

```bash
pip install a2a-config
```

For development:

```bash
git clone https://github.com/a2a/config.git
cd config
pip install -e ".[dev]"
```

## Quick Start

### 1. Initialize Configuration

```bash
# Initialize development configuration
a2a-config init --environment development

# Initialize production configuration
a2a-config init --environment production --format yaml
```

### 2. Load Configuration

```python
from config.api import get_config

# Get configuration
config = get_config()
print(config.environment)
print(config.server.port)
```

### 3. Validate Configuration

```bash
# Validate configuration file
a2a-config validate config/development/config.json

# Validate current configuration
python -c "from config.api import validate_config; print(validate_config())"
```

### 4. Export Configuration

```bash
# Export as JSON
a2a-config export config.json --format json

# Export as environment file
a2a-config export config.json --env-file

# Export as Docker config
a2a-config export config.json --docker-config

# Export as Kubernetes config
a2a-config export config.json --k8s-config
```

## Configuration Structure

### Base Configuration

```json
{
  "environment": "development",
  "config_version": "0.1.0",
  "server": {
    "host": "localhost",
    "port": 8080,
    "max_connections": 100,
    "timeout": 30,
    "ssl_enabled": false
  },
  "logging": {
    "level": "INFO",
    "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    "file": null,
    "max_size": 10485760,
    "backup_count": 5,
    "json_format": false
  },
  "security": {
    "jwt_secret": "dev-secret-key",
    "jwt_algorithm": "HS256",
    "jwt_expiration": 3600,
    "api_key": "dev-api-key",
    "ssl_cert_path": null,
    "ssl_key_path": null,
    "allowed_origins": ["*"]
  },
  "database": {
    "url": null,
    "host": "localhost",
    "port": 5432,
    "name": "a2a_db",
    "username": "postgres",
    "password": "password",
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
    "auto_start": true,
    "heartbeat_interval": 30,
    "max_bridge_sessions": 10,
    "message_queue_size": 1000,
    "metrics_enabled": true
  },
  "custom_config": {}
}
```

### Environment Variables

Configuration can be overridden using environment variables:

```bash
# Override server port
export DEVELOPMENT_SERVER_PORT=9090

# Override JWT secret
export DEVELOPMENT_SECURITY_JWT_SECRET="my-secret-key"

# Override database URL
export PRODUCTION_DATABASE_URL="postgresql://user:pass@localhost/db"
```

## Configuration Files

### File Priority (Low to High)

1. `config/config.json` - Base configuration
2. `config/development/config.json` - Environment-specific
3. `config/production/config.json` - Production-specific
4. `config/config.local.json` - Local overrides

### Environment-Specific Files

- `development/` - Development environment
- `testing/` - Testing environment
- `staging/` - Staging environment
- `production/` - Production environment

## Configuration API

### Basic Usage

```python
from config.api import get_config_service, Config, Environment

# Get configuration service
service = get_config_service()

# Load specific environment
config = service.load_config(Environment.PRODUCTION)

# Reload configuration
config = service.reload_config()

# Validate configuration
errors = service.validate_config(config)
if errors:
    print("Validation errors:", errors)
```

### Configuration Watcher

```python
from config.api import ConfigWatcher, ConfigEvent

def handle_config_change(event: ConfigEvent):
    if event.event_type == "change":
        print(f"Configuration reloaded from {event.config_path}")
        print(f"New server port: {event.new_config.server.port}")

# Set up watcher
watcher = ConfigWatcher(config_manager)
watcher.add_event_handler(handle_config_change)
watcher.add_watch_path("config/")

# Start watching
await watcher.start_watching()
```

### Configuration Templates

```python
from config.utils import ConfigTemplate

# Generate template
template = ConfigTemplate.generate_environment_template(Environment.PRODUCTION)

# Save template
ConfigTemplate.save_template(template, Path("config/production/config.json"), "yaml")
```

### Configuration Export

```python
from config.utils import ConfigExporter

# Export as JSON
ConfigExporter.export_config(config, Path("config.json"), "json")

# Export as environment file
ConfigExporter.export_env_file(config, Path(".env"), Environment.PRODUCTION)

# Export as Docker config
ConfigExporter.export_docker_config(config, Path("docker.json"))

# Export as Kubernetes config
ConfigExporter.export_k8s_config(config, Path("k8s.json"))
```

### Configuration Analysis

```python
from config.utils import ConfigAnalyzer

# Analyze configuration
analysis = ConfigAnalyzer.analyze_config(config)
print(f"Security Score: {analysis['security_score']}/100")
print(f"Performance Score: {analysis['performance_score']}/100")

# Get recommendations
for rec in analysis['recommendations']:
    print(f"Recommendation: {rec}")
```

## Configuration Schema

The configuration system uses JSON Schema for validation:

```json
{
  "type": "object",
  "properties": {
    "environment": {"enum": ["development", "testing", "staging", "production"]},
    "server": {
      "type": "object",
      "properties": {
        "host": {"type": "string"},
        "port": {"type": "integer", "minimum": 1, "maximum": 65535}
      }
    }
  }
}
```

## Migration

```python
from config.api import ConfigMigration

# Migrate configuration
migrated_config = migration.migrate_config(
    config,
    from_version="0.1.0",
    to_version="0.2.0"
)

# Generate migration report
report = migration.generate_migration_report(
    config,
    from_version="0.1.0",
    to_version="0.2.0"
)
```

## CLI Reference

### Commands

#### `a2a-config init`
Initialize configuration directory.

```bash
a2a-config init --environment development --format json --output ./config
```

#### `a2a-config validate`
Validate configuration file.

```bash
a2a-config validate config/development/config.json
```

#### `a2a-config export`
Export configuration to different formats.

```bash
a2a-config export config.json --format yaml --output config.yaml
a2a-config export config.json --env-file
a2a-config export config.json --docker-config
a2a-config export config.json --k8s-config
```

#### `a2a-config analyze`
Analyze configuration.

```bash
a2a-config analyze config.json
```

#### `a2a-config schema`
Show configuration schema.

```bash
a2a-config schema --format json --output schema.json
```

#### `a2a-config watch`
Watch configuration files for changes.

```bash
a2a-config watch --config-dir ./config
```

## Examples

### Example: Multi-Environment Setup

```python
from config.api import get_config_service, Environment

# Development
dev_service = get_config_service(Path("config/dev"))
dev_config = dev_service.load_config(Environment.DEVELOPMENT)

# Production
prod_service = get_config_service(Path("config/prod"))
prod_config = prod_service.load_config(Environment.PRODUCTION)

# Compare configurations
print(f"Dev server port: {dev_config.server.port}")
print(f"Prod server port: {prod_config.server.port}")
```

### Example: Dynamic Configuration Reload

```python
import asyncio
from config.api import get_config_service, ConfigEvent

async def config_manager():
    service = get_config_service()
    await service.initialize()
    await service.start_watcher()

    while True:
        config = service.get_config()
        print(f"Current port: {config.server.port}")
        await asyncio.sleep(5)

asyncio.run(config_manager())
```

### Example: Configuration Validation

```python
from config.api import get_config_service

service = get_config_service()
config = service.load_config(Environment.PRODUCTION)

errors = service.validate_config(config)
if errors:
    print("Configuration errors:")
    for error in errors:
        print(f"  - {error}")
else:
    print("Configuration is valid!")
```

## Security Considerations

- Always use environment variables for sensitive data
- Store configuration files in secure locations
- Use proper file permissions for configuration files
- Consider encrypting sensitive configuration values
- Regularly rotate secrets and API keys

## Performance Optimization

- Use configuration caching to reduce file I/O
- Minimize configuration file size
- Use appropriate logging levels
- Optimize connection pool settings
- Consider using Redis for shared configuration

## Troubleshooting

### Common Issues

1. **Configuration not found**: Check file paths and permissions
2. **Validation errors**: Review schema requirements
3. **Environment variables not working**: Check variable names and prefixes
4. **File watcher not working**: Check file system permissions

### Debug Mode

Enable debug logging:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

# Or set environment variable
export LOG_LEVEL=DEBUG
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Run the test suite
5. Submit a pull request

## License

MIT License - see LICENSE file for details.