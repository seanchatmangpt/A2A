# GGen Testing Framework Documentation

## Overview

This document describes the comprehensive testing framework for the ggen (A2A code generation system). The testing framework is designed to ensure the reliability, performance, and correctness of the generated code.

## Test Structure

The testing framework is organized into several categories:

```
test/
├── unit/                    # Unit tests for individual modules
│   ├── ggen_generator_tests.erl
│   └── ggen_metrics_collector_tests.erl
├── integration/            # End-to-end integration tests
│   └── ggen_integration_tests.erl
├── validation/             # Generated code validation tests
│   └── ggen_validation_tests.erl
├── performance/            # Performance testing
│   └── ggen_performance_tests.erl
├── template_tests.erl      # Template rendering tests
├── test_runner.sh          # Test runner script
├── generate_test_data.sh   # Test data generator
├── test_data/              # Test fixtures and data
│   └── fixtures/
│       ├── ontologies/     # Sample ontology files
│       ├── configs/        # Sample configuration files
│       ├── modules/        # Sample module files
│       └── *.sql          # Database schemas
└── test.config             # Test configuration
```

## Test Categories

### 1. Unit Tests (`test/unit/`)

**Purpose**: Test individual modules in isolation

**Files**:
- `ggen_generator_tests.erl` - Tests for code generation logic
- `ggen_metrics_collector_tests.erl` - Tests for metrics collection

**Key Tests**:
- Generation of different component types (Erlang, Docker, K8s, Helm)
- Generation with different options
- Helper function testing
- Error handling
- Metrics tracking

### 2. Integration Tests (`test/integration/`)

**Purpose**: Test end-to-end generation workflows

**Files**:
- `ggen_integration_tests.erl` - Comprehensive integration testing

**Key Tests**:
- End-to-end generation workflow
- Multiple generation types
- Configuration handling
- File validation
- Metric collection during generation
- Generation speed requirements

### 3. Validation Tests (`test/validation/`)

**Purpose**: Test generated code compilation and functionality

**Files**:
- `ggen_validation_tests.erl` - Validation testing

**Key Tests**:
- Generated Erlang file compilation
- Template-specific feature validation
- Generated module functionality
- Supervisor child specifications
- HotCI and rollback feature validation
- Dependency resolution

### 4. Performance Tests (`test/performance/`)

**Purpose**: Measure generation speed and performance characteristics

**Files**:
- `ggen_performance_tests.erl` - Performance testing

**Key Tests**:
- Single generation performance
- Generation scalability with module count
- All generation performance
- Template rendering performance
- Concurrent generation performance
- Memory usage during generation
- Repeated generation consistency

### 5. Template Tests (`template_tests.erl`)

**Purpose**: Test template rendering and variable substitution

**Key Tests**:
- GenServer template rendering
- GenStatem template rendering
- Supervisor template rendering
- Template with properties
- HotCI template features
- Rollback template features
- Template error handling
- Variable substitution
- Conditional rendering
- Generated code compilation

## Test Data

### Test Ontologies (`test_data/fixtures/ontologies/`)

- `basic_ontology.ttl` - Basic ontology with simple components
- `complex_ontology.ttl` - Complex ontology with multiple components
- `test_ontology.ttl` - Comprehensive test ontology

### Test Configurations (`test_data/fixtures/configs/`)

- `basic_config.json` - Simple project configuration
- `full_config.json` - Complete project configuration
- `test_config.json` - Detailed test configuration

### Test Modules (`test_data/fixtures/modules/`)

- `simple_gen_server.erl` - Basic gen_server implementation
- `complex_gen_statem.erl` - Complex gen_statem implementation

### SQL Schemas (`test_data/fixtures/`)

- `schema.mysql.sql` - MySQL database schema
- `schema.pgsql.sql` - PostgreSQL database schema

### CSV Data (`test_data/fixtures/test_data.csv`)

- Module configuration data for testing

## Running Tests

### Using Makefile

```bash
# Run all tests
make test-all

# Run specific test categories
make test-unit
make test-integration
make test-validation
make test-performance

# Run tests with test runner script
make test-runner

# Generate test data
make test-data
```

### Using Test Runner Script

```bash
# Run all tests
./test/test_runner.sh --all

# Run specific test categories
./test/test_runner.sh --unit
./test/test_runner.sh --integration
./test/test_runner.sh --validation
./test/test_runner.sh --performance

# Clean up test artifacts
./test/test_runner.sh --clean

# Generate test report
./test/test_runner.sh --all --report
```

### Using Test Data Generator

```bash
# Generate all test data
./test/generate_test_data.sh --all

# Generate specific data types
./test/generate_test_data.sh --ontologies
./test/generate_test_data.sh --config
./test/generate_test_data.sh --modules
./test/generate_test_data.sh --sql
./test/generate_test_data.sh --templates

# Clean up test data
./test/generate_test_data.sh --clean
```

### Using Erlang Console

```bash
# Compile test files
make compile

# Run unit tests
erl -pa ebin -eval "eunit:test(ggen_generator_tests, [verbose]), init:stop(0)"

# Run integration tests
erl -pa ebin -eval "eunit:test(ggen_integration_tests, [verbose]), init:stop(0)"

# Run all tests
erl -pa ebin -eval "eunit:test([ggen_generator_tests, ggen_metrics_collector_tests, ggen_integration_tests, ggen_validation_tests, ggen_performance_tests, template_tests], [verbose]), init:stop(0)"
```

## Test Environment Setup

### Prerequisites

1. **Erlang/OTP**: Ensure Erlang/OTP 22+ is installed
2. **Erlang Compiler**: `erlc` must be available in PATH
3. **Optional**: `rebar3` for additional test features

### Setup Commands

```bash
# Clone the repository
git clone <repository-url>
cd ggen

# Create necessary directories
mkdir -p ebin test/test_data/fixtures

# Compile the application
make compile

# Generate test data
make test-data

# Run tests
make test-all
```

## Test Configuration

### Environment Variables

- `TEST_OUTPUT_DIR` - Directory for test output (default: `test_output`)
- `TIMEOUT` - Test timeout in milliseconds (default: 30000)
- `REBAR3_PATH` - Path to rebar3 executable (optional)

### Test Configuration File (`test/test.config`)

```erlang
{erl_opts, [debug_info, warnings_as_errors]}.
{cover_enabled, true}.
{eunit_compile_opts, [{i, "test"}]}.
{include, ["include", "test/include"]}.
```

## Test Coverage

The test framework includes comprehensive test coverage:

### Coverage Areas

- **Unit Testing**: 90%+ coverage for individual modules
- **Integration Testing**: Complete workflow testing
- **Validation Testing**: Generated code compilation and functionality
- **Performance Testing**: Speed and scalability validation
- **Template Testing**: Variable substitution and conditional rendering

### Coverage Reports

- EUnit coverage reports are generated when using rebar3
- Manual coverage can be measured by instrumenting the code
- Performance metrics are collected during test execution

## Error Handling

### Common Test Failures

1. **Compilation Errors**: Generated code doesn't compile
2. **Missing Templates**: Template files not found
3. **Configuration Issues**: Invalid configuration data
4. **Timeout Errors**: Tests taking too long to complete
5. **Memory Issues**: High memory usage during generation

### Debugging Tips

1. **Check Logs**: Test logs are saved in `*.log` files
2. **Run Individual Tests**: Use specific test targets to isolate issues
3. **Verify Test Data**: Ensure test data is properly generated
4. **Check Dependencies**: Verify all required dependencies are installed
5. **Monitor Memory**: Use `erlang:memory()` to check memory usage

## Performance Metrics

### Key Metrics Tracked

- **Generation Time**: Time taken to generate code
- **Memory Usage**: Memory consumed during generation
- **File Count**: Number of files generated
- **Template Renders**: Number of template operations
- **Error Rate**: Percentage of failed operations

### Performance Thresholds

- **Single Generation**: < 5 seconds
- **All Generation**: < 15 seconds
- **Memory Usage**: < 1MB per generation
- **Template Rendering**: < 1 second per template

## Test Automation

### Continuous Integration

The testing framework is designed for CI/CD integration:

```yaml
# Example CI pipeline
steps:
  - name: Setup
    run: make setup

  - name: Unit Tests
    run: make test-unit

  - name: Integration Tests
    run: make test-integration

  - name: Performance Tests
    run: make test-performance

  - name: Generate Report
    run: make test-report
```

### Test Result Reporting

- Test results are saved in `test_report.txt`
- Performance metrics are logged during execution
- JSON reports can be generated for CI integration

## Best Practices

### Writing Tests

1. **Follow EUnit conventions**: Use proper test naming and setup/teardown
2. **Test edge cases**: Include tests for error conditions and boundary values
3. **Use mock data**: Generate realistic test data
4. **Document tests**: Include comments explaining test purpose
5. **Keep tests focused**: Each test should verify one specific behavior

### Test Maintenance

1. **Update regularly**: Update tests when code changes
2. **Add new tests**: Write tests for new features
3. **Refactor tests**: Keep tests clean and maintainable
4. **Monitor performance**: Update performance thresholds as needed
5. **Review test data**: Update test data to match current requirements

### Code Quality

1. **Error handling**: Test error conditions thoroughly
2. **Memory management**: Monitor memory usage during tests
3. **Concurrency**: Test concurrent generation scenarios
4. **Compatibility**: Test with different template variations
5. **Validation**: Always validate generated code

## Future Enhancements

### Planned Features

1. **More Test Templates**: Add template tests for all template types
2. **Cross-Platform Testing**: Test on different operating systems
3. **Integration with CI**: Enhanced CI/CD integration
4. **Performance Benchmarking**: Detailed performance analysis
5. **Test Coverage Reports**: Detailed coverage reports
6. **Mock Generation**: Mock generation for testing complex scenarios

### Technology Updates

1. **Test Framework**: Consider moving to Common Test for advanced features
2. **Performance Testing**: Integrate with proper benchmarking tools
3. **Visual Testing**: Add visual regression testing
4. **API Testing**: Test generation API endpoints
5. **Load Testing**: Test under heavy load conditions

## Conclusion

The ggen testing framework provides comprehensive coverage for all aspects of the code generation system. By following the guidelines in this document, developers can ensure the reliability, performance, and correctness of the generated code.

The framework is designed to be:
- **Comprehensive**: Covers all aspects of the system
- **Maintainable**: Easy to update and extend
- **Performant**: Optimized for fast test execution
- **Scalable**: Can handle growing test suites
- **Automated**: Integrated with CI/CD pipelines

By using this framework, developers can confidently generate and deploy Erlang applications with the assurance that the generated code is correct, efficient, and reliable.