# Configuration Guide

This guide provides detailed information about configuring the elrmcp bridge for various use cases.

## Configuration Overview

The elrmcp bridge supports multiple configuration methods:

1. **Configuration Files** - Static configuration
2. **Environment Variables** - Runtime configuration
3. **Runtime API** - Dynamic configuration updates

## Configuration Files

### bridge.config

Main configuration file for the bridge:

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:8090",
      "timeout": 30000,
      "auth_token": null
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 100,
      "burst_size": 10,
      "refill_interval_ms": 1000
    },
    "tool_management": {
      "whitelist": [],
      "blacklist": [],
      "auto_register": true,
      "cache_ttl": 300000
    },
    "performance": {
      "enable_caching": true,
      "cache_size": 1000,
      "request_timeout": 30000,
      "connect_timeout": 5000
    },
    "logging": {
      "level": "info",
      "enable_metrics": true,
      "request_logging": true,
      "error_logging": true
    },
    "health_checks": {
      "enabled": true,
      "interval_ms": 30000,
      "timeout_ms": 5000
    },
    "security": {
      "validate_inputs": true,
      "sanitize_outputs": true,
      "max_request_size": 1048576,
      "allowed_origins": ["*"]
    }
  }
}
```

### vm.args

Virtual machine arguments for Erlang runtime:

```erlang
## Kernel
+K true
+zdbbl 128000

## Process Limits
+P 1048576
+A 64

## Scheduling
+S 128
+Q 65536

## Memory
-heap_type optimal
-hms 64 +hmsz 64 +hmtvm 128
+hmbsz 32

## ETS
+ets [file_table {read_concurrency true}]

## Logging
-kernel logger '[{handler, default, logger_std_h,
                  #{formatter => {logger_formatter,
                                 #{single_line => true,
                                   legacy_header => false}}},
                  #{level => info}}]'

## Crash Dump
-crash_dump /tmp/elrmcp_bridge.crashdump

## Heart
-heartbeat_interval 30
-heartbeat_timeout 60
```

### rebar.config

Build configuration:

```erlang
{erl_opts, [
    debug_info,
    warnings_as_errors,
    {platform_define, "^[0-9]+", "ERLANG_OTP_23"}
]}.

{deps, [
    {cowboy, "2.12.0"},
    {jiffy, "1.1.1"},
    {uuid, "2.0.6"}
]}.
```

## Environment Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `CRAFTPLAN_URL` | Craftplan MCP server URL | `http://localhost:8090` | String |
| `LOG_LEVEL` | Logging level | `info` | String |
| `BRIDGE_TIMEOUT` | Request timeout in ms | `30000` | Integer |
| `BRIDGE_RATE_LIMIT` | Rate limit per second | `100` | Integer |
| `BRIDGE_CACHE_SIZE` | Cache size | `1000` | Integer |
| `BRIDGE_CACHE_TTL` | Cache TTL in ms | `300000` | Integer |
| `BRIDGE_MAX_REQUEST_SIZE` | Max request size in bytes | `1048576` | Integer |
| `NODE_NAME` | Erlang node name | `elrmcp-bridge` | String |
| `COOKIE` | Erlang cookie | `elrmcp` | String |

### Usage Examples

```bash
# Set environment variables
export CRAFTPLAN_URL="http://craftplan-mcp:8090"
export LOG_LEVEL="debug"
export BRIDGE_RATE_LIMIT="200"

# Run the application
./_build/default/rel/elrmcp_bridge/bin/elrmcp_bridge console
```

## Runtime Configuration Updates

### API Configuration Updates

The bridge provides runtime API for configuration updates:

```erlang
% Update configuration
NewConfig = #{
    craftplan_url => <<"http://localhost:9000">>,
    timeout => 60000,
    rate_limit => 150
},
elrmcp_mcp_bridge:configure_bridge(NewConfig).
```

### Configuration Validation

The bridge validates configuration updates:

```erlang
% Invalid configuration
InvalidConfig = #{
    craftplan_url => "invalid-url",
    rate_limit => -1
},
Result = elrmcp_mcp_bridge:configure_bridge(InvalidConfig).
% Result: {error, {invalid_config, "Invalid rate limit"}}
```

## Configuration Sections

### Craftplan Configuration

#### Connection Settings

```json
{
  "craftplan": {
    "url": "http://localhost:8090",
    "timeout": 30000,
    "auth_token": null,
    "connect_timeout": 5000,
    "max_retries": 3,
    "retry_delay_ms": 1000
  }
}
```

#### Authentication

```json
{
  "craftplan": {
    "auth_token": "your-api-key",
    "auth_type": "bearer",
    "ssl_verify": true,
    "ssl_ca_file": "/path/to/ca.pem"
  }
}
```

### Rate Limiting Configuration

#### Token Bucket Settings

```json
{
  "rate_limiting": {
    "enabled": true,
    "requests_per_second": 100,
    "burst_size": 10,
    "refill_interval_ms": 1000,
    "burst_tokens_per_refill": 10
  }
}
```

#### Rate Limit Policies

```json
{
  "rate_limiting": {
    "policies": [
      {
        "name": "global",
        "limit": 100,
        "burst": 10,
        "enabled": true
      },
      {
        "name": "per_tool",
        "limit": 50,
        "burst": 5,
        "enabled": true,
        "tools": ["customer_management", "order_management"]
      }
    ]
  }
}
```

### Tool Management Configuration

#### Tool Filtering

```json
{
  "tool_management": {
    "whitelist": ["customer_management", "order_management"],
    "blacklist": ["admin_tools", "internal_tools"],
    "auto_register": true,
    "cache_ttl": 300000,
    "refresh_interval_ms": 60000
  }
}
```

#### Tool Metadata

```json
{
  "tool_management": {
    "metadata": {
      "customer_management": {
        "category": "crm",
        "priority": "high",
        "timeout": 10000
      },
      "order_management": {
        "category": "ecommerce",
        "priority": "medium",
        "timeout": 15000
      }
    }
  }
}
```

### Performance Configuration

#### Caching Settings

```json
{
  "performance": {
    "enable_caching": true,
    "cache_size": 1000,
    "cache_ttl": 300000,
    "cache_key_prefix": "elrmcp:",
    "cache_metrics": true
  }
}
```

#### Timeouts and Retries

```json
{
  "performance": {
    "request_timeout": 30000,
    "connect_timeout": 5000,
    "read_timeout": 10000,
    "max_retries": 3,
    "retry_delay_ms": 1000,
    "retry_backoff_factor": 2
  }
}
```

### Logging Configuration

#### Logging Levels

```json
{
  "logging": {
    "level": "info",
    "enable_metrics": true,
    "request_logging": true,
    "error_logging": true,
    "access_log_file": "/var/log/elrmcp-bridge/access.log",
    "error_log_file": "/var/log/elrmcp-bridge/error.log"
  }
}
```

#### Structured Logging

```json
{
  "logging": {
    "structured": true,
    "format": "json",
    "fields": {
      "service": "elrmcp-bridge",
      "version": "1.0.0"
    }
  }
}
```

### Health Check Configuration

#### Health Check Settings

```json
{
  "health_checks": {
    "enabled": true,
    "interval_ms": 30000,
    "timeout_ms": 5000,
    "path": "/health",
    "health_threshold": 3,
    "unhealthy_threshold": 2
  }
}
```

#### Dependency Health Checks

```json
{
  "health_checks": {
    "dependencies": {
      "craftplan": {
        "enabled": true,
        "url": "http://localhost:8090/health",
        "timeout_ms": 5000,
        "interval_ms": 30000
      }
    }
  }
}
```

### Security Configuration

#### Input Validation

```json
{
  "security": {
    "validate_inputs": true,
    "sanitize_outputs": true,
    "max_request_size": 1048576,
    "allowed_origins": ["*"],
    "trusted_proxies": ["192.168.1.0/24"]
  }
}
```

#### CORS Settings

```json
{
  "security": {
    "cors": {
      "enabled": true,
      "allowed_origins": ["https://example.com"],
      "allowed_methods": ["GET", "POST"],
      "allowed_headers": ["Content-Type", "Authorization"],
      "expose_headers": ["X-RateLimit-Limit"],
      "max_age": 3600
    }
  }
}
```

## Configuration Examples

### Development Environment

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:8090",
      "timeout": 30000,
      "auth_token": null
    },
    "rate_limiting": {
      "enabled": false
    },
    "tool_management": {
      "whitelist": [],
      "blacklist": [],
      "auto_register": true
    },
    "performance": {
      "enable_caching": false
    },
    "logging": {
      "level": "debug",
      "enable_metrics": true,
      "request_logging": true
    },
    "health_checks": {
      "enabled": true
    },
    "security": {
      "validate_inputs": true,
      "sanitize_outputs": true
    }
  }
}
```

### Production Environment

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "https://craftplan-prod.example.com:8090",
      "timeout": 15000,
      "auth_token": "${CRAFTPLAN_API_TOKEN}",
      "connect_timeout": 3000,
      "max_retries": 5,
      "retry_delay_ms": 1000
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 500,
      "burst_size": 50,
      "refill_interval_ms": 1000
    },
    "tool_management": {
      "whitelist": ["customer_management", "order_management", "inventory_management"],
      "blacklist": ["admin_tools", "debug_tools"],
      "auto_register": true,
      "cache_ttl": 600000
    },
    "performance": {
      "enable_caching": true,
      "cache_size": 5000,
      "cache_ttl": 600000,
      "request_timeout": 15000,
      "connect_timeout": 3000
    },
    "logging": {
      "level": "info",
      "enable_metrics": true,
      "request_logging": true,
      "error_logging": true
    },
    "health_checks": {
      "enabled": true,
      "interval_ms": 10000,
      "timeout_ms": 3000
    },
    "security": {
      "validate_inputs": true,
      "sanitize_outputs": true,
      "max_request_size": 2097152,
      "allowed_origins": ["https://elrmcp.example.com"]
    }
  }
}
```

### High-Load Environment

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "https://craftplan-cluster.example.com:8090",
      "timeout": 10000,
      "auth_token": "${CRAFTPLAN_API_TOKEN}",
      "connect_timeout": 2000,
      "max_retries": 2,
      "retry_delay_ms": 500
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 2000,
      "burst_size": 200,
      "refill_interval_ms": 1000
    },
    "tool_management": {
      "whitelist": ["customer_management", "order_management"],
      "blacklist": [],
      "auto_register": true,
      "cache_ttl": 900000
    },
    "performance": {
      "enable_caching": true,
      "cache_size": 10000,
      "cache_ttl": 900000,
      "request_timeout": 10000,
      "connect_timeout": 2000
    },
    "logging": {
      "level": "warn",
      "enable_metrics": true,
      "request_logging": false,
      "error_logging": true
    },
    "health_checks": {
      "enabled": true,
      "interval_ms": 5000,
      "timeout_ms": 2000
    },
    "security": {
      "validate_inputs": true,
      "sanitize_outputs": true,
      "max_request_size": 4194304
    }
  }
}
```

## Configuration Management

### Configuration Management Systems

#### Vault Integration

```json
{
  "craftplan": {
    "auth_token": "{{ vault secret/data/elrmcp/bridge token }}"
  }
}
```

#### Consul Integration

```json
{
  "craftplan": {
    "url": "{{ consul kv get elrmcp/bridge/craftplan_url }}"
  }
}
```

### Configuration Validation

#### Schema Validation

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "elrmcp_bridge": {
      "type": "object",
      "properties": {
        "craftplan": {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "format": "uri"
            },
            "timeout": {
              "type": "integer",
              "minimum": 1000,
              "maximum": 300000
            }
          }
        }
      }
    }
  }
}
```

### Configuration Hot Reload

```erlang
% Reload configuration
elrmcp_mcp_bridge:reload_config().

% Get current configuration
{ok, Config} = elrmcp_mcp_bridge:get_config().
```

## Troubleshooting

### Common Configuration Issues

#### Connection Issues

```bash
# Check configuration
grep "craftplan" config/bridge.config

# Test connection
curl -f http://localhost:8090/health
```

#### Rate Limiting Issues

```bash
# Check rate limit configuration
grep "rate_limit" config/bridge.config

# Monitor rate limiting metrics
curl http://localhost:9090/metrics | grep elrmcp_bridge_rate_limit
```

#### Cache Issues

```bash
# Check cache configuration
grep "cache" config/bridge.config

# Monitor cache metrics
curl http://localhost:9090/metrics | grep elrmcp_bridge_cache
```

### Configuration Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug

# Start with debug config
rebar3 shell --config config/debug.config
```

### Configuration Migration

#### Version Migration

```json
{
  "migrations": {
    "from_0.9.0": {
      "changes": {
        "rate_limiting.requests_per_second": "rate_limiting.limit"
      }
    }
  }
}
```

#### Backup and Restore

```bash
# Backup configuration
cp config/bridge.config config/bridge.config.backup

# Restore configuration
cp config/bridge.config.backup config/bridge.config
```

## Best Practices

### Configuration Security

1. **Never hardcode sensitive information**
2. **Use environment variables for secrets**
3. **Implement proper access controls**
4. **Regularly audit configuration**

### Performance Considerations

1. **Use appropriate cache sizes**
2. **Configure realistic timeouts**
3. **Enable rate limiting in production**
4. **Monitor configuration impact**

### Maintainability

1. **Document configuration options**
2. **Use version control for configurations**
3. **Implement configuration validation**
4. **Regular configuration reviews**