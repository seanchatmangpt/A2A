# A2A Comprehensive Demo System Documentation

This document provides a comprehensive overview of the ggen-based code generation demo system for A2A Erlang applications.

## 🚀 Overview

The demo system showcases the full capabilities of the ggen code generation system, including:
- **Erlang module generation** with various OTP behaviours
- **Cloud infrastructure generation** for Docker, Kubernetes, and Helm
- **HotCI integration** for hot code loading and rollback support
- **Complex scenarios** with state machines and orchestration
- **Comprehensive testing** and validation
- **Production-ready code** generation

## 📁 Demo System Structure

```
ggen/
├── demo_comprehensive.erl        # Comprehensive demo runner
├── test_validation.erl            # Testing and validation suite
├── scenarios/                    # Generation scenarios
│   ├── scenario_basic.erl        # Basic module generation
│   └── scenario_advanced.erl     # Advanced generation with HotCI
├── templates/                    # Tera templates
│   ├── erlang/src/              # Erlang source templates
│   ├── erlang/config/           # Configuration templates
│   ├── docker/                  # Docker templates
│   ├── k8s/                    # Kubernetes templates
│   └── helm/                   # Helm templates
├── ontology/                   # RDF/TTL ontology files
├── queries/                    # SPARQL query files
└── generated/                  # Generated output
    ├── basic/                  # Basic scenario output
    ├── advanced/               # Advanced scenario output
    ├── cloud/                  # Cloud infrastructure output
    ├── hotci/                  # HotCI output
    └── integration/           # Integration output
```

## 🎯 Demo Scenarios

### 1. Basic Scenario (`generated/basic/`)

Generates simple Erlang modules with gen_server behaviour:

**Generated Modules:**
- `a2a_task_worker` - Task processing worker
- `a2a_event_bus` - Event bus implementation

**Features:**
- Basic gen_server implementation
- HotCI support
- Proper error handling
- EUnit tests

### 2. Advanced Scenario (`generated/advanced/`)

Generates complex modules with advanced features:

**Generated Modules:**
- `a2a_workflow_orchestrator` - State machine for workflow orchestration
- `a2a_hotci_manager` - HotCI manager with rollback support
- `a2a_metrics_collector` - Metrics collection with Prometheus

**Features:**
- gen_statem with complex state transitions
- HotCI integration with upgrade testing
- Rollback support with strategy pattern
- Metrics and monitoring
- Comprehensive testing

### 3. Cloud Scenario (`generated/cloud/`)

Generates complete cloud infrastructure:

**Generated Files:**
- `Dockerfile` - Multi-stage build with HotCI support
- `deployment.yaml` - Kubernetes deployment
- `service.yaml` - Kubernetes service
- `configmap.yaml` - Configuration map
- `a2a-erl/` - Helm chart

**Features:**
- Production-ready Docker builds
- Kubernetes manifests with auto-scaling
- Helm charts with values customization
- Health checks and monitoring

### 4. HotCI Scenario (`generated/hotci/`)

Generates HotCI-enabled modules:

**Generated Modules:**
- HotCI-enabled servers
- Monitoring modules
- Rollback handlers

**Features:**
- Hot code loading support
- Runtime monitoring
- Rollback capabilities
- Consistency checking

### 5. Integration Scenario (`generated/integration/`)

Generates complete application integration:

**Generated Modules:**
- `a2a_orchestrator` - Workflow orchestrator
- `a2a_workflow_manager` - Workflow management
- `a2a_message_broker` - Message passing

**Features:**
- Complex orchestration
- Message passing systems
- Distributed system patterns
- Integration with cloud infrastructure

## 🚀 Getting Started

### Prerequisites

1. **Install Erlang/OTP**: Version 27.0 or later
2. **Install ggen**: `cargo install ggen`
3. **Install dependencies**:
   ```bash
   cd /Users/sac/A2A
   make deps
   ```

### Running the Demo

#### 1. Basic Demo
```bash
# Compile the demo
make compile

# Run basic demo
make demo_erlang

# Or using Erlang shell
erl -pa ebin -eval "demo_comprehensive:main([demo, erlang])" -s init stop
```

#### 2. Comprehensive Demo
```bash
# Run all demos
make demo

# Run specific demo
erl -pa ebin -eval "demo_comprehensive:main([demo, advanced])" -s init stop
```

#### 3. Generate All Scenarios
```bash
# Generate all scenarios
make generate

# Or using Erlang
erl -pa ebin -eval "demo_comprehensive:main([generate])" -s init stop
```

#### 4. Run Tests
```bash
# Run validation tests
make test

# Or using test validation
erl -pa ebin -eval "test_validation:main([test])" -s init stop
```

#### 5. Validate Generated Code
```bash
# Validate all generated code
erl -pa ebin -eval "test_validation:main([validate])" -s init stop

# Validate specific scenario
erl -pa ebin -eval "test_validation:main([validate, advanced])" -s init stop
```

## 📋 Usage Examples

### Scenario-Based Generation

```erlang
%% Basic scenario
scenario_basic:generate([
    {output_dir, "my_project/"}
]).

%% Advanced scenario
scenario_advanced:generate([
    {output_dir, "my_advanced_project/"},
    {hotci_enabled, true},
    {rollback_support, true}
]).
```

### Custom Generation

```erlang
%% Define custom module
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

%% Generate custom module
ggen_generator:generate(erlang, #{
    output_dir => "custom_output/",
    modules => [CustomModule]
}).
```

### Validation and Testing

```erlang
%% Validate generated code
test_validation:validate_code_quality("all").

%% Run specific tests
test_validation:run_test_suite("integration").

%% Run benchmarks
test_validation:run_benchmarks().
```

## 🧪 Testing Framework

### Test Categories

1. **Syntax Tests**: Validate Erlang syntax, configuration syntax, template syntax
2. **Logic Tests**: Validate generation logic, infrastructure logic, configuration logic
3. **Integration Tests**: Validate end-to-end workflows, complex scenarios, error handling
4. **Performance Tests**: Validate generation speed, memory usage, concurrent generation

### Running Tests

```bash
# Run all tests
make test

# Run specific test category
erl -pa ebin -eval "test_validation:main([test, syntax])" -s init stop

# Run benchmarks
erl -pa ebin -eval "test_validation:main([benchmark])" -s init stop
```

## 🔧 Configuration

### ggen Configuration

The system uses a hierarchical configuration system:

```erlang
%% Basic configuration
#{}
```

### Template Configuration

Templates are configured in the `templates/` directory:

```yaml
# Template metadata
description: "Generate gen_server module"
output_dir: "src/"
file_extension: ".erl"
dependencies: ["extract-erlang-modules.sparql"]
```

### Ontology Configuration

Ontologies define the schema and relationships:

```turtle
# Define a module
a2a:gen_server_module a owl:Class ;
    rdfs:label "GenServer Module" ;
    rdfs:subClassOf a2a:erlang_module .
```

## 🎨 Template System

### Template Types

1. **Source Templates**: Generate Erlang source code
2. **Configuration Templates**: Generate configuration files
3. **Infrastructure Templates**: Generate cloud infrastructure
4. **Test Templates**: Generate test code

### Template Features

- **Tera Templating**: Full template engine support
- **Conditional Logic**: `{% if %}` statements
- **Loops**: `{% for %}` iterations
- **Filters**: Data transformation filters
- **Includes**: Template composition

### Example Template

```tera
---
description: "Generate gen_server module"
output_dir: "src/"
file_extension: ".erl"
---

-module({{ module.module_name }}).
-behaviour(gen_server).

{% if module.hotci_enabled %}
-export([
    get_metrics/0,
    get_status/0
]).
{% endif %}

-record(state, {
{% for prop in module.properties %}
    {{ prop.name }} :: {{ prop.type | default("term()") }},
{% endfor %}
    metrics :: map()
}).
```

## 🔌 HotCI Integration

### HotCI Features

1. **Hot Code Loading**: Runtime code updates without restart
2. **Rollback Support**: Automatic rollback on failures
3. **Consistency Checking**: Validate system state after updates
4. **Monitoring**: Track system health and performance

### HotCI Configuration

```erlang
%% Enable HotCI in generated modules
#{hotci_enabled => true, rollback_support => true}
```

### HotCI Testing

```erlang
%% Run HotCI tests
test_validation:run_test_suite("hotci").

%% Validate HotCI implementation
test_validation:validate_hotci_quality("generated/hotci/").
```

## ☁️ Cloud Infrastructure

### Docker Generation

```erlang
%% Dockerfile generation
generate_comprehensive_dockerfile("generated/cloud/").
```

### Kubernetes Generation

```erlang
%% Kubernetes manifests
generate_comprehensive_k8s("generated/cloud/").
```

### Helm Chart Generation

```erlang
%% Helm chart
generate_comprehensive_helm("generated/cloud/").
```

## 📊 Performance Optimization

### Generation Speed

- **Parallel Generation**: Generate multiple files concurrently
- **Caching**: Cache template results
- **Incremental Generation**: Only generate changed files

### Memory Usage

- **Streaming**: Stream large files instead of loading into memory
- **Garbage Collection**: Optimize memory usage patterns
- **Pool Management**: Efficient resource pooling

### Scaling

- **Distributed Generation**: Generate across multiple nodes
- **Batch Processing**: Process large batches efficiently
- **Load Balancing**: Distribute generation load

## 🔍 Troubleshooting

### Common Issues

1. **Syntax Errors**: Check Erlang syntax in generated modules
2. **Template Errors**: Validate template syntax and dependencies
3. **Configuration Errors**: Verify configuration file paths and content
4. **Dependency Issues**: Ensure all dependencies are installed

### Debug Mode

```bash
# Run in debug mode
export DEBUG=1
make demo

# Enable verbose output
make demo V=1
```

### Log Files

- `generated/logs/generation.log`: Generation logs
- `generated/logs/validation.log`: Validation logs
- `generated/logs/test.log`: Test logs

## 🎯 Best Practices

### Code Quality

1. **Consistent Naming**: Use consistent naming conventions
2. **Error Handling**: Implement comprehensive error handling
3. **Documentation**: Include documentation for all generated code
4. **Testing**: Generate comprehensive test suites

### Performance

1. **Template Optimization**: Optimize templates for performance
2. **Resource Management**: Manage system resources efficiently
3. **Cache Management**: Use caching effectively
4. **Parallel Processing**: Utilize parallel processing where possible

### Maintenance

1. **Version Control**: Track template and configuration changes
2. **Documentation**: Keep documentation up to date
3. **Testing**: Maintain comprehensive test coverage
4. **Monitoring**: Monitor generation performance and quality

## 🔮 Future Enhancements

### Planned Features

1. **AI-Powered Generation**: Use AI for template generation
2. **Visual Interface**: Web-based generation interface
3. **Real-time Generation**: Real-time code generation
4. **Advanced Analytics**: Advanced analytics and insights

### Integration Plans

1. **CI/CD Integration**: Direct integration with CI/CD pipelines
2. **IDE Integration**: IDE plugins for seamless integration
3. **API Access**: REST API for remote generation
4. **Plugin System**: Plugin system for extensibility

## 📄 License

This demo system is licensed under the MIT License. See the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please see the CONTRIBUTING.md file for guidelines.

## 📞 Support

For support and questions:
- Create an issue on GitHub
- Join our community forum
- Contact the development team

---

Happy generating! 🚀