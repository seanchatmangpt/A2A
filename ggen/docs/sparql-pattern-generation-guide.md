# SPARQL Pattern Generation Guide for ggen

This guide provides comprehensive documentation for using SPARQL queries to extract patterns from ontologies and drive template generation using ggen.

## Overview

The ggen system leverages semantic ontologies to generate code templates based on structured patterns. The SPARQL queries in this directory extract specific patterns from three main ontologies:

1. **Erlang OTP Patterns** (`erlang-otp.ttl`) - Erlang module definitions and behaviours
2. **Cloud Infrastructure Patterns** (`cloud-infrastructure.ttl`) - Docker, Kubernetes, and Helm configurations
3. **A2A Protocol Patterns** (`a2a-spec.ttl`) - Agent-to-Agent protocol specifications

## Query Categories

### 1. Erlang Module Definitions
**File:** `queries/erlang-module-definitions.sparql`

This query extracts comprehensive Erlang module information from OTP patterns including:
- Module names and behaviour types
- Exported functions and types
- Record definitions
- HotCI properties (enabled, upgrade monitor, rollback support)
- Callback functions

**Usage:** Generate Erlang module skeletons with proper OTP behaviour implementations.

**Example Pattern:**
```erlang
-module(?MODULE_NAME).
-behaviour(?BEHAVIOUR_TYPE).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(?RECORD_NAME, {
    id,
    name,
    metadata
}).

start_link() ->
    gen_server:start_link({local, ?MODULE_NAME}, ?MODULE_NAME, [], []).

init([]) ->
    {ok, #?RECORD_NAME{}}.
```

### 2. Cloud Infrastructure Configurations
**File:** `queries/cloud-infrastructure-configurations.sparql`

Extracts cloud deployment configurations including:
- Docker configurations (base images, ports, volumes, environment variables)
- Kubernetes resources (deployments, services, configmaps, secrets, ingress)
- Helm charts (versions, schemas, values)
- Resource requests and limits
- Health checks and security configurations

**Usage:** Generate container orchestration templates and deployment manifests.

**Example Pattern:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ?APP_NAME
spec:
  replicas: ?REPLICAS
  template:
    spec:
      containers:
      - name: ?CONTAINER_NAME
        image: ?BASE_IMAGE
        ports:
        - containerPort: ?EXPOSE_PORT
        env:
        - name: ENV_VAR
          value: ?ENV_VALUE
```

### 3. A2A Protocol Specifications
**File:** `queries/a2a-protocol-specifications.sparql`

Comprehensive extraction of A2A protocol elements:
- Task system states and transitions
- Agent capabilities and metadata
- Message types and routing
- JSON-RPC and SSE configurations
- ETS table definitions
- Event system patterns
- HotCI test specifications

**Usage:** Generate protocol handlers, message processors, and agent implementations.

### 4. Constraint-Based Pattern Matching
**File:** `queries/constraint-based-pattern-matching.sparql`

Extracts patterns based on specific constraints and conditions:
- HotCI-enabled modules with rollback support
- Production-ready infrastructure configurations
- Capable agents with valid IDs and descriptive names
- Active tasks with valid states
- Valid messages with proper routing

**Usage:** Generate patterns that meet specific quality and functional requirements.

### 5. Hierarchical Pattern Extraction
**File:** `queries/hierarchical-pattern-extraction.sparql`

Extracts hierarchical relationships between entities:
- Application → Module → Behaviour hierarchy
- Task parent-child relationships
- Agent organizational hierarchies
- Infrastructure deployment hierarchies
- Event and skill dependencies

**Usage:** Generate structured code that reflects hierarchical relationships.

### 6. Conditional Pattern Generation
**File:** `queries/conditional-pattern-generation.sparql`

Generates patterns based on conditional logic:
- HotCI features (enabled, rollback, upgrade monitoring)
- Infrastructure scaling policies
- Agent capabilities and states
- Task priorities and workflow states
- Message routing patterns
- Event handling triggers

**Usage:** Generate adaptive templates that change based on conditions.

### 7. Complex Pattern Composition
**File:** `queries/complex-pattern-composition.sparql`

Composes complex patterns from multiple ontological elements:
- Application-Service compositions
- Service-Module-Agent compositions
- Agent-Task-Workflow compositions
- Infrastructure-Service compositions
- Event-Action compositions

**Usage:** Generate sophisticated, multi-level templates that integrate different system components.

### 8. Template Generation Patterns
**File:** `queries/template-generation-patterns.sparql`

Optimized queries specifically for template generation:
- Template modules with variables and conditions
- Infrastructure templates with deployment environments
- Agent templates with runtime variables
- Task templates with workflows
- Service templates with endpoints and middleware
- Configuration templates with validation
- Record templates with constraints
- Workflow templates with parallel execution

## Using ggen with SPARQL Queries

### Basic Usage

```bash
# Generate Erlang modules from OTP patterns
ggen generate -q queries/erlang-module-definitions.sparql -o generated/erlang-modules/

# Generate cloud infrastructure templates
ggen generate -q queries/cloud-infrastructure-configurations.sparql -o generated/infrastructure/

# Generate A2A protocol handlers
ggen generate -q queries/a2a-protocol-specifications.sparql -o generated/protocol/
```

### Advanced Usage

```bash
# Generate with specific constraints
ggen generate -q queries/constraint-based-pattern-matching.sparql --filter "hotci_enabled=true" -o generated/constrained/

# Generate hierarchical patterns
ggen generate -q queries/hierarchical-pattern-extraction.sparql --hierarchy-level 2 -o generated/hierarchical/

# Generate conditional templates
ggen generate -q queries/conditional-pattern-generation.sparql --condition "scaling_type=high_availability" -o/generated/conditional/

# Generate complex compositions
ggen generate -q queries/complex-pattern-composition.sparql --composition-level "full" -o/generated/composed/

# Generate optimized templates
ggen generate -q queries/template-generation-patterns.sparql --template-type "gen_server_template" -o/generated/templates/
```

## Template Variables and Placeholders

The SPARQL queries extract semantic data that gets mapped to template variables:

### Common Variables
- `?MODULE_NAME` - Erlang module name
- `?BEHAVIOUR_TYPE` - OTP behaviour (gen_server, supervisor, etc.)
- `?EXPORTED_FUNCTIONS` - List of exported functions
- `?BASE_IMAGE` - Docker base image
- `?REPLICAS` - Kubernetes replica count
- `?SERVICE_PORT` - Service port number
- `?CONFIG_SETTINGS` - Configuration key-value pairs

### Conditional Variables
- `?HOTCI_ENABLED` - Boolean HotCI support flag
- `?ROLLBACK_SUPPORT` - Boolean rollback support
- `?SCALING_POLICY` - Infrastructure scaling strategy
- `?AGENT_CAPABILITIES` - Agent capability list
- `?TASK_PRIORITY` - Task priority level

### Hierarchical Variables
- `?PARENT_MODULE` - Parent module in hierarchy
- `?CHILD_MODULES` - List of child modules
- `?DEPENDENCIES` - List of dependencies
- `?WORKFLOW_STEPS` - Workflow step sequence

## Integration with Build Systems

### For Erlang Projects
```makefile
# Generate Erlang modules from patterns
generate-modules:
	ggen generate -q queries/erlang-module-definitions.sparql -o src/
	$(MAKE) compile

# Generate HotCI-enabled modules
generate-hotci-modules:
	ggen generate -q queries/conditional-pattern-generation.sparql --filter "hotci_enabled=true" -o src/hotci/
	$(MAKE) compile
```

### For Kubernetes Projects
```yaml
# GitHub Actions workflow for infrastructure generation
name: Generate Infrastructure Templates
on: [push]
jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Generate Kubernetes manifests
      run: |
        ggen generate -q queries/cloud-infrastructure-configurations.sparql -o k8s/
        helm lint k8s/
```

## Best Practices

### 1. Query Optimization
- Use `LIMIT` clauses to control result sets
- Leverage `OPTIONAL` for flexible pattern matching
- Use `BIND` with `COALESCE` for default values
- Filter with complex conditions for targeted generation

### 2. Template Organization
- Separate generated code from hand-written code
- Use consistent naming conventions
- Include generated files in version control
- Document generation parameters and constraints

### 3. Quality Assurance
- Validate generated templates against schema
- Run automated tests on generated code
- Review generated code for security issues
- Monitor generation performance

### 4. Maintenance
- Regularly update ontologies to reflect new patterns
- Review and optimize queries for new requirements
- Update templates to match evolving standards
- Archive old query versions for compatibility

## Troubleshooting

### Common Issues

1. **Empty Results**
   - Check ontology data is properly loaded
   - Verify prefix declarations match ontology
   - Ensure class/property relationships exist

2. **Template Generation Errors**
   - Verify template syntax is correct
   - Check variable mappings from SPARQL results
   - Validate template engine compatibility

3. **Performance Issues**
   - Add LIMIT clauses to complex queries
   - Optimize triple patterns for faster matching
   - Use query caching when possible

### Debug Commands

```bash
# Validate SPARQL query syntax
ggen validate-query queries/erlang-module-definitions.sparql

# Test query with sample data
ggen test-query queries/erlang-module-definitions.sparql --sample-size 10

# Generate debug information
ggen generate --debug -q queries/erlang-module-definitions.sparql -o debug-output/
```

## Future Enhancements

1. **Machine Learning Integration**
   - Use ML to suggest optimal patterns
   - Auto-generate constraints based on usage patterns
   - Predict template quality metrics

2. **Dynamic Query Generation**
   - Generate SPARQL queries from natural language descriptions
   - Auto-optimize queries based on performance metrics
   - Create query templates for common patterns

3. **Enhanced Template Engines**
   - Support for multiple template engines (Handlebars, Jinja2, etc.)
   - Real-time template preview and validation
   - Interactive template editing capabilities

4. **Expanded Ontology Support**
   - Additional domain-specific ontologies
   - Cross-ontology pattern composition
   - Versioned ontology management

## Conclusion

These SPARQL queries provide a powerful foundation for semantic-driven code generation. By leveraging the rich structure of ontologies, ggen can generate sophisticated templates that are both correct and maintainable. The comprehensive query patterns cover a wide range of use cases from simple module generation to complex multi-system compositions.

For support and contributions, please refer to the project documentation and issue tracker.