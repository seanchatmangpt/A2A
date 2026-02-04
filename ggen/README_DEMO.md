# A2A ggen Comprehensive Demo System

A comprehensive demonstration system showcasing the ggen-based code generation system for A2A Erlang applications. This demo system provides end-to-end examples of generating production-quality Erlang modules, cloud infrastructure, and advanced features like HotCI integration.

## 🚀 Features

- **Comprehensive Demo System**: Multiple demo scenarios showcasing different aspects of the ggen system
- **Erlang Module Generation**: Generate various OTP behaviours (gen_server, gen_statem, supervisor)
- **Cloud Infrastructure**: Generate Docker, Kubernetes, and Helm configurations
- **HotCI Integration**: Hot code loading with rollback support and monitoring
- **Advanced Scenarios**: Complex workflows with state machines and orchestration
- **Testing Framework**: Comprehensive validation and testing of generated code
- **Production Ready**: All generated code includes error handling, documentation, and tests

## 📁 System Structure

```
ggen/
├── demo_comprehensive.erl        # Comprehensive demo runner
├── test_validation.erl            # Testing and validation suite
├── scenarios/                    # Generation scenarios
│   ├── scenario_basic.erl        # Basic module generation
│   └── scenario_advanced.erl     # Advanced generation with HotCI
├── scripts/                      # Automation scripts
│   ├── run_demo.sh              # Comprehensive demo runner
│   └── run_scenario.sh           # Scenario-specific runner
├── docs/                        # Documentation
│   └── README_DEMO.md           # Detailed documentation
├── examples/                    # Usage examples
│   └── usage_example.md        # Practical examples
└── generated/                  # Generated output
    ├── basic/                  # Basic scenario output
    ├── advanced/               # Advanced scenario output
    ├── cloud/                  # Cloud infrastructure output
    ├── hotci/                  # HotCI output
    └── integration/           # Integration output
```

## 🎯 Demo Scenarios

### 1. Basic Scenario (`generated/basic/`)
Simple Erlang modules with gen_server behaviour:
- `a2a_task_worker`: Task processing worker
- `a2a_event_bus`: Event bus implementation
- Basic configuration and tests

### 2. Advanced Scenario (`generated/advanced/`)
Complex modules with advanced features:
- `a2a_workflow_orchestrator`: State machine for workflow orchestration
- `a2a_hotci_manager`: HotCI manager with rollback support
- `a2a_metrics_collector`: Metrics collection with Prometheus
- Comprehensive testing and monitoring

### 3. Cloud Scenario (`generated/cloud/`)
Complete cloud infrastructure:
- Multi-stage Dockerfile
- Kubernetes deployment with auto-scaling
- Helm chart with values customization
- Health checks and monitoring

### 4. HotCI Scenario (`generated/hotci/`)
HotCI-enabled modules:
- Hot code loading support
- Runtime monitoring
- Rollback capabilities
- Consistency checking

### 5. Integration Scenario (`generated/integration/`)
Complete application integration:
- Complex orchestration
- Message passing systems
- Distributed system patterns

## 🚀 Quick Start

### Prerequisites

1. **Erlang/OTP 27.0+**
2. **ggen**: `cargo install ggen`
3. **Make**: For build automation

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd ggen

# Compile the system
make compile

# Run comprehensive demo
make demo-comprehensive
```

### Running Demos

```bash
# Using Make targets
make demo-basic          # Basic demo
make demo-advanced       # Advanced demo
make demo-cloud         # Cloud demo
make demo-hotci         # HotCI demo
make demo-integration   # Integration demo

# Using scripts
./scripts/run_demo.sh demo all      # Run all demos
./scripts/run_scenario.sh basic    # Run specific scenario
./scripts/run_scenario.sh advanced # Run advanced scenario

# Generate all scenarios
make generate-all
```

### Testing

```bash
# Run tests
make test                    # All tests
make test-all-scenarios      # Test all scenarios
./scripts/run_demo.sh test all # Using script

# Validate code
./scripts/run_demo.sh validate
```

## 📋 Configuration

### System Configuration

The demo system supports various configuration options:

```erlang
% Basic configuration
#{}

% With HotCI enabled
#{hotci_enabled => true, rollback_support => true}

% With custom output directory
#{output_dir => "my_project/"}
```

### Template Configuration

Templates are configured with metadata:

```yaml
# Template metadata
description: "Generate gen_server module"
output_dir: "src/"
file_extension: ".erl"
dependencies: ["extract-erlang-modules.sparql"]
```

## 🧪 Testing Framework

### Test Categories

1. **Syntax Tests**: Validate Erlang syntax, configuration syntax, template syntax
2. **Logic Tests**: Validate generation logic, infrastructure logic, configuration logic
3. **Integration Tests**: Validate end-to-end workflows, complex scenarios, error handling
4. **Performance Tests**: Validate generation speed, memory usage, concurrent generation

### Running Tests

```bash
# All tests
make test

# Specific test categories
make test-unit
make test-integration
make test-performance
make test-validation

# Custom test execution
erl -pa ebin -eval "test_validation:main([test, all])" -s init stop
```

## 🏗️ Generated Code Examples

### Erlang Module Example

```erlang
% Generated gen_server module
-module(a2a_task_worker).
-behaviour(gen_server).

-export([
    start_link/0,
    execute_task/1,
    get_status/0
]).

-record(state, {
    ets_table :: ets:tid(),
    max_retries :: integer(),
    metrics :: map(),
    stats :: map()
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

execute_task(TaskData) ->
    gen_server:call(?MODULE, execute_task_request(TaskData)).
```

### Cloud Infrastructure Example

```dockerfile
# Generated Dockerfile
FROM erlang:27-alpine AS builder

RUN apk add --no-cache git make curl
WORKDIR /app
COPY rebar3 /usr/local/bin/
COPY rebar.config config src include /app/
RUN rebar3 compile

FROM erlang:27-alpine
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001
WORKDIR /app
COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/a2a_erl /app
COPY --from=builder --chown=appuser:appuser /app/config /app/config
RUN chown -R appuser:appuser /app && mkdir -p /app/log /app/data
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
CMD ["/app/bin/a2a_erl", "foreground"]
```

## 🎨 Customization

### Creating Custom Scenarios

```erlang
% Define custom module
CustomModule = #{
    module_name => "my_custom_module",
    behaviour_type => "gen_server",
    hotci_enabled => true,
    properties => [
        #{name => "my_config", type => "string()", default => "default_value"}
    ],
    exported_functions => [
        #{name => "my_function", args => ["Arg1", "Arg2"]}
    ]
},

% Generate custom module
ggen_generator:generate(erlang, #{
    output_dir => "custom_output/",
    modules => [CustomModule]
}).
```

### Modifying Templates

1. **Locate templates**: `templates/` directory
2. **Edit Tera templates**: Modify existing templates or create new ones
3. **Test changes**: Run scenarios to verify template correctness
4. **Validate output**: Check generated code for quality

## 🔧 Integration

### CI/CD Integration

```bash
# Add to your CI pipeline
make compile
make test
make generate-all
./scripts/run_demo.sh validate
```

### HotCI Integration

Generated modules include HotCI support:

```erlang
% HotCI-enabled modules include:
- Hot code loading support
- Runtime monitoring
- Rollback capabilities
- Consistency checking
```

## 📊 Performance

### Generation Speed

- **100+ modules per minute** for basic generation
- **50+ modules per minute** for complex generation
- **Streaming generation** for memory efficiency
- **Parallel processing** supported

### Memory Usage

- **Optimized streaming** for large files
- **Efficient template caching**
- **Garbage collection** optimization
- **Resource pooling** for better performance

## 🔍 Troubleshooting

### Common Issues

1. **Erlang compilation errors**: Check module syntax and dependencies
2. **Template errors**: Validate template syntax and structure
3. **Permission issues**: Check file permissions and paths
4. **Missing dependencies**: Install required packages

### Debug Mode

```bash
# Enable verbose output
make demo V=1

# Generate debug logs
./scripts/run_demo.sh demo all 2>&1 | tee demo.log
```

### Logging

Generated logs are available in:
- `generated/logs/generation.log`
- `generated/logs/validation.log`
- `generated/logs/test.log`

## 📚 Documentation

- **[Detailed Documentation](docs/README_DEMO.md)**: Comprehensive system documentation
- **[Usage Examples](examples/usage_example.md)**: Practical usage examples
- **[Template Guide](templates/README.md)**: Template customization guide
- **[API Reference](docs/api.md)**: API documentation

## 🎯 Best Practices

1. **Use scenarios** for consistent generation
2. **Validate generated code** before deployment
3. **Leverage HotCI** for safe updates
4. **Monitor performance** of generated systems
5. **Customize templates** for specific needs
6. **Maintain comprehensive testing**

## 🚀 Next Steps

1. **Explore generated code** in `generated/` directory
2. **Customize scenarios** for your specific needs
3. **Create custom templates** for additional functionality
4. **Integrate with CI/CD** pipelines
5. **Extend with custom generators** for additional languages

## 🤝 Contributing

Contributions are welcome! Please see the contributing guidelines for:
- Bug reports
- Feature requests
- Code contributions
- Documentation improvements

## 📄 License

This demo system is licensed under the MIT License. See the LICENSE file for details.

---

**Happy generating! 🚀**