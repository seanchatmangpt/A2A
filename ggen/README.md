# A2A GGen - Erlang Code Generation System

A comprehensive ggen-based code generation system for Erlang applications with cloud infrastructure support.

## 🚀 Features

### Erlang Generation
- **OTP Behaviors**: GenServer, GenStatem, Supervisor, Cowboy handlers
- **HotCI Integration**: Hot code upgrade support with rollback
- **Ets Table Management**: Automatic table creation and management
- **Error Handling**: Comprehensive error handling and recovery
- **Metrics Collection**: Built-in monitoring and telemetry
- **Testing Framework**: Unit, integration, performance, and validation tests

### Cloud Infrastructure
- **Docker**: Multi-stage builds with security hardening
- **Kubernetes**: Production-ready manifests with HPA, rolling updates
- **Helm Charts**: Complete chart with values and annotations
- **CI/CD Integration**: GitHub Actions and Jenkins pipelines
- **Monitoring**: Prometheus and Grafana configurations

### A2A Protocol
- **Task Management**: Task lifecycle states and workflows
- **Agent Communication**: Message passing and routing patterns
- **State Machines**: Complex orchestration with transitions
- **Error Propagation**: Comprehensive error handling

## 📁 Project Structure

```
ggen/
├── ggen.toml                    # Main configuration file
├── demo.erl                     # Demo system entry point
├── Makefile                     # Build automation
├── README.md                    # This file
├── ontology/                    # RDF/TTL ontologies
│   ├── erlang-otp.ttl          # Erlang behavior patterns
│   ├── cloud-infrastructure.ttl # Cloud infrastructure patterns
│   └── a2a-spec.ttl            # A2A protocol patterns
├── queries/                     # SPARQL queries
│   ├── extract-erlang-modules.sparql
│   ├── extract-task-states.sparql
│   ├── extract-records.sparql
│   ├── extract-k8s-resources.sparql
│   └── extract-docker-config.sparql
├── templates/                   # Tera templates
│   ├── erlang/                 # Erlang module templates
│   ├── docker/                 # Docker configuration templates
│   ├── k8s/                   # Kubernetes templates
│   └── helm/                  # Helm chart templates
├── test/                       # Test framework
│   ├── unit/                  # Unit tests
│   ├── integration/          # Integration tests
│   ├── validation/           # Validation tests
│   └── performance/          # Performance tests
└── generated/                  # Generated files
    ├── demo_*.erl            # Generated Erlang modules
    ├── demo_*                # Generated cloud configurations
    └── logs/                 # Generation logs
```

## 🛠️ Installation

### Prerequisites
- Erlang/OTP 27+
- rebar3 (optional, for advanced builds)
- ggen (Rust-based code generator)

### Install ggen
```bash
cargo install ggen
```

### Clone Repository
```bash
git clone https://github.com/a2a/ggen.git
cd ggen
```

## 🚀 Quick Start

### Run Demo
```bash
# Run comprehensive demo
make demo

# Run specific demos
make demo_erlang
make demo_docker
make demo_k8s
make demo_helm
```

### Generate Files
```bash
# Generate all demo files
make generate

# Generate specific types
make generate_erlang
make generate_docker
make generate_k8s
make generate_helm
```

### Run Tests
```bash
# Run all tests
make test

# Run specific test suites
make test-unit
make test-integration
make test-validation
make test-performance
```

## 📖 Usage Examples

### Command Line Interface
```bash
# Basic usage
erl -pa ebin -eval "demo:main()" -s init stop

# With arguments
erl -pa ebin -eval "demo:main([demo, erlang])" -s init stop
```

### Programmatic Usage
```erlang
% Generate Erlang modules
demo:main([generate, erlang])

% Run comprehensive demo
demo:main([demo, all])

% Run tests
demo:main([test, all])
```

## 🔧 Configuration

### ggen.toml
The main configuration file defines:
- Project metadata
- Ontology sources
- Template mappings
- Generation phases
- Validation rules
- Cloud configurations

### Example Configuration
```toml
[project]
name = "a2a-ggen"
version = "0.2.0"

[ontology]
sources = [
    { path = "ontology/erlang-otp.ttl", prefix = "erl" },
    { path = "ontology/cloud-infrastructure.ttl", prefix = "k8s" },
    { path = "ontology/a2a-spec.ttl", prefix = "a2a" }
]

[templates]
paths = [
    "templates/erlang",
    "templates/docker",
    "templates/k8s",
    "templates/helm"
]

[generation.phases]
# 8-phase generation pipeline with dependencies
```

## 🧪 Testing

### Test Categories
1. **Unit Tests**: Individual component testing
2. **Integration Tests**: End-to-end workflows
3. **Validation Tests**: Generated code validation
4. **Performance Tests**: Generation speed and scalability

### Test Execution
```bash
# Run all tests
make test

# Run specific test suites
make test-unit
make test-integration
make test-validation
make test-performance

# Run with test runner
make test-runner
```

## 📊 Generated Components

### Erlang Modules
- **GenServer Modules**: With HotCI support and metrics
- **GenStatem Modules**: State machine implementations
- **Supervisor Trees**: Fault-tolerant process hierarchies
- **HTTP Handlers**: Cowboy-based REST endpoints
- **ETS Management**: Automatic table lifecycle

### Cloud Infrastructure
- **Docker Files**: Multi-stage builds with security
- **Kubernetes**: Deployments, services, configmaps
- **Helm Charts**: Complete chart with values
- **CI/CD Pipelines**: GitHub Actions workflows

### A2A Protocol
- **Task Workflows**: State machine implementations
- **Message Handlers**: Request/response patterns
- **Agent Communication**: Inter-agent messaging

## 🎯 Best Practices

### Template Organization
- Single responsibility per template
- Clear variable definitions
- Proper error handling
- Comprehensive documentation

### Code Quality
- Erlang compilation validation
- Template syntax checking
- Integration testing
- Performance monitoring

### Security
- Non-root containers
- Secret scanning
- Vulnerability scanning
- Network policies

## 🚀 Advanced Features

### HotCI Integration
HotCI (Hot Code Loading) support enables:
- Zero-downtime upgrades
- Rolling updates
- Automatic rollback
- Version management

### Monitoring & Metrics
- Prometheus integration
- Grafana dashboards
- Application metrics
- Health checks

### Multi-Environment
- Development configurations
- Staging environments
- Production deployments
- Environment-specific templates

## 📚 Documentation

- [Ontology Documentation](ontology/README.md)
- [Template Reference](templates/README.md)
- [Testing Guide](test/README.md)
- [Configuration Guide](docs/configuration.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run the test suite
6. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

## 🚀 Roadmap

- [ ] Web-based UI for template generation
- [ ] AI-powered template suggestions
- [ ] Multi-language support (Python, Go, Rust)
- [ ] Cloud provider specific templates (AWS, GCP, Azure)
- [ ] Advanced monitoring and alerting
- [ ] Performance optimization suite

---

**A2A GGen** - Making Erlang development faster and more efficient!