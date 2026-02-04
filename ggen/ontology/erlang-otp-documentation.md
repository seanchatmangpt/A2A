# Erlang OTP Ontology Documentation

This document provides a comprehensive overview of the Erlang OTP ontology, designed for template generation using ggen.

## Overview

The Erlang OTP ontology is a comprehensive RDF/TTL (Turtle) ontology that captures patterns, behaviors, and best practices for Erlang/OTP development. It includes:

- Core OTP behaviors (gen_server, gen_statem, supervisor, etc.)
- ETS table patterns and configurations
- Error handling and logging patterns
- HotCI (Hot Code Loading) integration patterns
- Message passing protocols
- Metrics collection and monitoring patterns

## Namespace and Prefixes

```turtle
@prefix erl: <https://erlang.org/otp/>        # Erlang OTP patterns
@prefix a2a: <https://a2a.com/schema/>      # A2A specific properties
@prefix sh: <http://www.w3.org/ns/shacl#>   # SHACL validation
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>  # XML Schema types
```

## Core Ontology Structure

### 1. Base Classes

- `erl:component` - Base class for all Erlang components
- `erl:behaviour` - Base class for OTP behaviours
- `erl:module` - Base class for Erlang modules

### 2. Core OTP Behaviours

#### Server Behaviours
- `erl:gen_server` - Generic server process with synchronous calls
- `erl:gen_statem` - Generic finite state machine with states and events
- `erl:gen_fsm` - Generic finite state machine (legacy)
- `erl:worker` - Generic worker process

#### System Behaviours
- `erl:application` - Top-level OTP application
- `erl:supervisor` - Process supervisor for fault tolerance
- `erl:gen_event` - Generic event handler

#### Web Behaviours
- `erl:cowboy_handler` - Cowboy HTTP request handler
- `erl:cowboy_loop` - Cowboy streaming handler

### 3. ETS Table Patterns

#### Table Types
- `erl:ets_set` - Set table with unique keys
- `erl:ets_bag` - Bag table allowing duplicate keys
- `erl:ets_ordered_set` - Set with ordered keys
- `erl:ets_private_table` - Private to a process
- `erl:ets_public_table` - Visible to all processes
- `erl:ets_named_table` - With a registered name

#### Usage Patterns
- `erl:ets_cache` - Cache pattern using ETS
- `erl:ets_registry` - Registry pattern using ETS

### 4. Error Handling Patterns

- `erl:error_handler` - Base error handling pattern
- `erl:crash_handler` - Process crash handling
- `erl:retry_handler` - Retry logic with backoff
- `erl:circuit_breaker` - Circuit breaker for fault tolerance
- `erl:backoff_strategy` - Backoff strategies (fixed, exponential, linear)

### 5. HotCI Integration Patterns

- `erl:hotci_module` - Module supporting hot code loading
- `erl:hotci_process` - Process supporting hot code upgrade
- `erl:release_handler` - Release handling for HotCI
- `erl:version_manager` - Version management
- `erl:rollback_handler` - Rollback handling
- `erl:upgrade_monitor` - Monitor for upgrade operations

### 6. Message Passing Patterns

- `erl:protocol` - Base message passing protocol
- `erl:request_reply` - Request-reply pattern
- `erl:cast_pattern` - Asynchronous message pattern
- `erl:forwarder` - Message forwarder
- `erl:broadcast` - Broadcast pattern
- `erl:queue_pattern` - Message queue pattern
- `erl:pubsub_pattern` - Publish-subscribe pattern

### 7. Monitoring Patterns

- `erl:metric_collector` - Base metric collection
- `erl:telemetry_handler` - Telemetry event handling
- `erl:health_check` - Health monitoring
- `erl:performance_monitor` - Performance monitoring
- `erl:logging_handler` - Logging patterns
- `erl:tracing_handler` - Tracing patterns
- `erl:alert_handler` - Alert handling

## Key Properties

### Core Properties
- `a2a:module_name` - Module name string
- `a2a:behaviour_type` - Type of behaviour implemented
- `a2a:application_name` - Application name
- `a2a:version` - Version string
- `a2a:description` - Human-readable description

### ETS Table Properties
- `a2a:ets_table_name` - Name of the ETS table
- `a2a:ets_table_type` - Type of ETS table
- `a2a:ets_table_key_type` - Type of keys
- `a2a:ets_table_value_type` - Type of values
- `a2a:ets_table_options` - Additional options
- `a2a:ets_table_size` - Initial size

### Supervisor Properties
- `a2a:supervisor_strategy` - Restart strategy
- `a2a:supervisor_intensity` - Maximum restarts
- `a2a:supervisor_period` - Time period for restarts

### HotCI Properties
- `a2a:hotci_enabled` - Whether HotCI is enabled
- `a2a:version_compatibility` - Version compatibility range
- `a2a:rollback_supported` - Whether rollback is supported
- `a2a:upgrade_monitoring` - Whether upgrade monitoring is enabled

## SHACL Validation Constraints

The ontology includes SHACL validation constraints for key components:

### ETS Table Validation
- Must have a name
- Table type must be valid: set, bag, ordered_set, private, public, named

### Supervisor Validation
- Strategy must be valid: one_for_one, one_for_all, rest_for_one, simple_one_for_one
- Intensity must be between 1 and 100
- Period must be between 1 and 3600 seconds

### HotCI Module Validation
- HotCI enabled must be boolean
- Version compatibility must be in format X.Y or X.Y.Z

### Metric Collector Validation
- Metric name must be valid identifier
- Metric type must be valid: counter, gauge, histogram, summary

## Example Instances

### GenServer Example
```turtle
<https://example.com/gen_server/my_cache> a erl:gen_server ;
    a2a:module_name "my_cache" ;
    a2a:behaviour_type erl:gen_server ;
    a2a:description "Simple cache gen_server implementation" .
```

### Supervisor Example
```turtle
<https://example.com/supervisor/my_app> a erl:supervisor ;
    a2a:module_name "my_app_supervisor" ;
    a2a:supervisor_strategy "one_for_one" ;
    a2a:supervisor_intensity 5 ;
    a2a:supervisor_period 10 ;
    a2a:description "Main application supervisor" .
```

### ETS Table Example
```turtle
<https://example.com/ets/registry> a erl:ets_registry ;
    a2a:ets_table_name "process_registry" ;
    a2a:ets_table_type "set" ;
    a2a:ets_table_key_type "pid" ;
    a2a:ets_table_value_type "term" ;
    a2a:ets_table_size 1000 ;
    a2a:description "Process registry using ETS" .
```

## Usage with ggen

The ontology is designed to work with ggen for template generation. Here's how to use it:

### 1. Basic Template Generation

```bash
ggen generate --ontology ontology/erlang-otp.ttl --pattern erl:gen_server --output ./templates/my_cache
```

### 2. Specific Component Types

```bash
# Generate a supervisor with specific strategy
ggen generate --ontology ontology/erlang-otp.ttl --pattern erl:supervisor \
    --property "a2a:supervisor_strategy=one_for_one" \
    --property "a2a:supervisor_intensity=5" \
    --output ./templates/my_supervisor
```

### 3. Complex Patterns

```bash
# Generate a HotCI-enabled service
ggen generate --ontology ontology/erlang-otp.ttl --pattern erl:hotci_module \
    --property "a2a:hotci_enabled=true" \
    --property "a2a:version_compatibility=2.0.0" \
    --property "a2a:rollback_supported=true" \
    --output ./templates/my_hotci_service
```

### 4. Validation

```bash
# Validate generated templates against ontology
ggen validate --ontology ontology/erlang-otp.ttl --template ./templates/my_cache
```

## Template Examples

### GenServer Template Structure
A generated GenServer template would include:
- Module definition with gen_server behaviour
- State record
- init/1 callback
- handle_call/3 callback
- handle_cast/2 callback
- handle_info/2 callback
- terminate/2 callback
- code_change/3 callback

### Supervisor Template Structure
A generated supervisor template would include:
- Supervisor module
- Child specifications
- Start link function
- Init/1 callback
- Helper functions for managing children

### ETS Table Template Structure
A generated ETS table template would include:
- Module for table management
- Table creation function
- CRUD operations
- Cleanup functions

## Best Practices

1. **Validation Always**: Always validate generated templates against the SHACL constraints
2. **Consistency**: Follow the established patterns in the ontology
3. **Documentation**: Include appropriate comments and documentation
4. **Testing**: Generate test templates alongside production ones
5. **Versioning**: Use version compatibility for HotCI-enabled modules

## Integration with Development Tools

### VS Code Integration
Configure VS Code to recognize the ontology:
```json
{
    "turtle.schemas": ["ontology/erlang-otp.ttl"]
}
```

### CI/CD Integration
Include validation in your pipeline:
```yaml
- name: Validate OTP templates
  run: |
    ggen validate --ontology ontology/erlang-otp.ttl --template ./templates
```

## Troubleshooting

### Common Issues
1. **Invalid Range Values**: Check that enumerated values match the regex patterns
2. **Missing Required Properties**: Ensure all mandatory properties are set
3. **Invalid Identifiers**: Use only valid Erlang identifiers for module names

### Debugging
```bash
# Enable detailed logging
ggen --debug generate ...

# Validate ontology syntax
python3 -c "import rdflib; g = rdflib.Graph(); g.parse('ontology/erlang-otp.ttl')"

# Check specific instance validation
ggen validate --ontology ontology/erlang-otp.ttl --template specific_template
```

## Contributing

When extending the ontology:
1. Follow the established naming conventions
2. Include SHACL validation for new patterns
3. Add example instances for new classes
4. Update documentation
5. Test with ggen integration

## References

- [Erlang/OTP Documentation](https://erlang.org/doc/)
- [RDF Schema](https://www.w3.org/TR/rdf-schema/)
- [SHACL Specification](https://www.w3.org/TR/shacl/)
- [ggen Documentation](https://github.com/ruvnet/ggen)