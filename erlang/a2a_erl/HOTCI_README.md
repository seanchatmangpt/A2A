# HotCI Framework for Distributed Erlang/OTP Systems

## Overview

HotCI (Hot Code Improvement) is a comprehensive testing framework for validating hot code upgrades across distributed Erlang/OTP systems. It provides a complete solution for testing upgrade consistency, reliability, and performance in multi-node Docker environments.

## Features

### 🎯 Core Capabilities

- **Multi-node Container Orchestration**: Deploy and manage test nodes across Docker containers
- **Hot Code Upgrade Validation**: Comprehensive testing of upgrade scenarios
- **Consistency Checking**: Ensure data and state consistency across nodes during upgrades
- **Failure Injection**: Simulate various failure scenarios to test system resilience
- **Rollback Coordination**: Safe rollback mechanisms with validation
- **Real-time Metrics**: Performance and health metrics collection and analysis
- **Test Automation**: Automated test execution with comprehensive reporting

### 🔧 Architecture Components

1. **Node Orchestrator**: Manages test node lifecycle and cluster operations
2. **Upgrade Validator**: Validates upgrade compatibility and functionality
3. **Consistency Checker**: Ensures system-wide consistency during upgrades
4. **Metrics Collector**: Collects and analyzes system metrics
5. **Failure Injector**: Simulates failure scenarios for resilience testing
6. **Rollback Coordinator**: Manages safe rollback operations
7. **Test Supervisor**: Manages test execution and timeouts

## Quick Start

### Prerequisites

- Erlang/OTP 28+
- Docker and Docker Compose
- Rebar3 for building
- PostgreSQL (optional, for metrics storage)

### Basic Setup

1. **Clone and build the application**:
```bash
cd erlang/a2a_erl
rebar3 compile
```

2. **Start the HotCI framework**:
```bash
# Enable HotCI in the configuration
export HOTCI_MODE=master
export ENABLE_HOTCI=true

# Start the application
rebar3 shell
```

3. **Deploy test cluster**:
```erlang
1> ClusterId = hotci_node_orchestrator:create_test_cluster(#{
2>     nodes => [
3>         #{ip => "127.0.0.1", port => 8081, version => "1.0.0"},
4>         #{ip => "127.0.0.1", port => 8082, version => "1.0.0"}
5>     ]
6> }).
```

### Docker Setup

Use the provided Docker Compose configuration for a complete HotCI environment:

```bash
# Start all HotCI services
docker-compose -f docker/hotci-compose.yml up -d

# View logs
docker-compose -f docker/hotci-compose.yml logs -f

# Stop services
docker-compose -f docker/hotci-compose.yml down
```

## API Reference

### Node Orchestrator API

```erlang
% Create a test cluster
hotci_node_orchestrator:create_test_cluster(Config)

% Get cluster status
hotci_node_orchestrator:get_cluster_status()

% Upgrade a node
hotci_node_orchestrator:upgrade_node(ClusterId, NodeId, NewVersion)

% Destroy cluster
hotci_node_orchestrator:destroy_cluster(ClusterId)
```

### Upgrade Validator API

```erlang
% Start upgrade validation
hotci_upgrade_validator:start_upgrade_validation(ClusterId, TargetVersion)

% Validate consistency
hotci_upgrade_validator:validate_consistency(ClusterId)

% Get validation results
hotci_upgrade_validator:get_validation_results()
```

### Consistency Checker API

```erlang
% Check cluster consistency
hotci_consistency_checker:check_consistency(ClusterId)

% Check data consistency
hotci_consistency_checker:check_data_consistency(ClusterId)

% Get consistency metrics
hotci_consistency_checker:get_consistency_metrics()
```

### Failure Injector API

```erlang
% Inject failure immediately
hotci_failure_injector:inject_failure(ClusterId, NodeId, ScenarioId)

% Schedule failure for future injection
hotci_failure_injector:schedule_failure(ClusterId, NodeId, ScenarioId)

% Enable failure mode
hotci_failure_injector:enable_failure_mode(ScenarioId, Probability)
```

### Rollback Coordinator API

```erlang
% Initiate rollback
hotci_rollback_coordinator:initiate_rollback(ClusterId, TargetVersion)

% Rollback specific node
hotci_rollback_coordinator:rollback_node(ClusterId, NodeId, TargetVersion)

% Validate rollback
hotci_rollback_coordinator:validate_rollback(SessionId)
```

## Testing

### Running Tests

```bash
# Run all HotCI tests
rebar3 ct --suite test/hotci_*.erl

# Run specific test suite
rebar3 ct --suite test/hotci_node_orchestrator_SUITE

# Run tests with coverage
rebar3 ct --cover
```

### Test Scenarios

The framework includes comprehensive test suites for:

- **Node Orchestration**: Cluster creation, node management, scaling
- **Upgrade Validation**: Version compatibility, functionality testing
- **Consistency Checking**: Data consistency, process consistency
- **Failure Injection**: Network partitions, node crashes, timeouts
- **Rollback Coordination**: Safe rollback, validation, recovery

## Configuration

### Environment Variables

```bash
# HotCI Mode
HOTCI_MODE=master|orchestrator|validator|consistency|metrics|failure_injector|rollback|test_node

# Cluster Configuration
HOTCI_CLUSTER_SIZE=5
HOTCI_CHECK_INTERVAL=5000
HOTCI_CONSISTENCY_THRESHOLD=0.95

# Testing Configuration
HOTCI_TEST_TIMEOUT=30000
HOTCI_MAX_CONCURRENT_TESTS=5

# Metrics Configuration
ENABLE_METRICS=true
METRICS_RETENTION_DAYS=30
```

### Erlang Configuration

```erlang
% sys.config
[
    {a2a_erl, [
        {enable_hotci, true},
        {hotci_mode, master},
        {cluster_size, 5},
        {check_interval, 5000},
        {consistency_threshold, 0.95},
        {test_timeout, 30000},
        {enable_failure_injection, true},
        {failure_probability, 0.1}
    ]}
].
```

## Monitoring and Metrics

### Prometheus Integration

The HotCI framework includes Prometheus metrics:

```bash
# Access Prometheus metrics
curl http://localhost:8080/hotci/metrics/prometheus

# Query specific metrics
curl http://localhost:9090/api/v1/query?query=hotci_cluster_nodes_total
```

### Grafana Dashboards

Pre-configured Grafana dashboards are available for:

- **Cluster Overview**: Node counts, health status, upgrade progress
- **Performance Metrics**: CPU, memory, network I/O
- **Validation Results**: Test success rates, consistency scores
- **Failure Analysis**: Failure rates, recovery times

### Custom Metrics

```erlang
% Record custom metrics
hotci_metrics_collector:record_metric(ClusterId, #{
    node_id => <<"node-1">>,
    type => cpu_usage,
    value => 25.5,
    unit => <<"percent">>,
    metadata => #{application => a2a_erl}
}).
```

## Failure Scenarios

### Built-in Failure Types

- **Node Crash**: Simulates Erlang node termination
- **Network Partition**: Isolates nodes from communication
- **Memory Exhaustion**: Simulates memory pressure
- **Disk Space Full**: Simulates storage issues
- **Timeout**: Simulates operation timeouts
- **Message Corruption**: Corrupts inter-node messages
- **Process Killed**: Terminates critical processes
- **Database Failure**: Simulates database connectivity issues
- **Connection Loss**: Simulates external service failures
- **Upgrade Failure**: Simulates upgrade process failures

### Failure Configuration

```erlang
% Enable failure scenario
hotci_failure_injector:enable_failure_mode(<<"node_crash">>, 0.1)

% Inject failure immediately
hotci_failure_injector:inject_failure(ClusterId, NodeId, <<"node_crash">>)

% Schedule failure
hotci_failure_injector:schedule_failure(ClusterId, NodeId, <<"network_partition">>)
```

## Rollback Strategies

### Built-in Strategies

1. **Graceful Rollback**: Minimal disruption, full validation
2. **Immediate Rollback**: Fast rollback for critical failures
3. **Phased Rollback**: Incremental rollback with validation

### Custom Rollback Strategies

```erlang
% Define custom rollback strategy
Strategy = #rollback_strategy{
    name = <<"custom_rollback">>,
    description = <<"Custom rollback strategy">>,
    priority = 1,
    rollback_order = [primary, auxiliaries, workers],
    validation_tests = [basic_functionality, data_integrity],
    rollback_timeout = 120000,
    health_check_interval = 3000,
    max_retries = 3
},

% Apply strategy
hotci_rollback_coordinator:set_rollback_strategy(ClusterId, <<"custom_rollback">>)
```

## Best Practices

### 1. Test Environment Setup

- Use isolated Docker containers for testing
- Ensure proper network configuration
- Monitor resource usage during tests
- Set appropriate timeouts based on system complexity

### 2. Upgrade Validation

- Test upgrade compatibility before production
- Validate data migration and schema changes
- Check backwards compatibility
- Test rollback procedures

### 3. Consistency Monitoring

- Monitor consistency scores regularly
- Set appropriate thresholds for your system
- Investigate inconsistencies immediately
- Implement automated alerts

### 4. Failure Testing

- Test realistic failure scenarios
- Combine multiple failures for stress testing
- Verify recovery procedures
- Document failure modes and responses

### 5. Performance Optimization

- Monitor system metrics during upgrades
- Optimize test concurrency based on resources
- Implement proper timeout handling
- Use appropriate retry strategies

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    HotCI Master                         │
│                 (Controller & API)                       │
├─────────────────────────────────────────────────────────┤
│  Node Orchestrator  │  Upgrade Validator  │ Consistency  │
│    (Cluster Mgmt)    │  (Testing)        │   Checker     │
│                     │                   │              │
│  Rollback Coord.    │  Metrics Collect. │ Failure      │
│  (Safety Net)       │  (Analytics)      │  Injector     │
│                     │                   │              │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│                  Test Cluster                           │
│                 (Docker Nodes)                          │
├─────────────────────────────────────────────────────────┤
│  Node 1  │  Node 2  │  Node 3  │  Node 4  │  Node 5  │
│          │          │          │          │          │
│  A2A     │  A2A     │  A2A     │  A2A     │  A2A     │
│  Tasks   │  Tasks   │  Tasks   │  Tasks   │  Tasks   │
│          │          │          │          │          │
│  State   │  State   │  State   │  State   │  State   │
│  Machine │  Machine │  Machine │  Machine │  Machine │
│          │          │          │          │          │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│                 External Services                        │
├─────────────────────────────────────────────────────────┤
│  PostgreSQL  │  Prometheus  │  Grafana  │  Load Gen   │
│  (Metrics)   │  (Metrics)  │  (Dash)  │  (Testing)  │
└─────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Common Issues

1. **Node Connection Failures**
   - Check network configuration
   - Verify EPMD ports are open
   - Ensure release cookie matches

2. **Upgrade Validation Failures**
   - Check version compatibility
   - Validate data migration scripts
   - Review upgrade dependencies

3. **Consistency Check Failures**
   - Investigate data divergence
   - Check network partitions
   - Verify process restarts

4. **Resource Exhaustion**
   - Monitor CPU and memory usage
   - Adjust test concurrency
   - Increase resource limits

### Debug Mode

```erlang
% Enable debug logging
application:set_env(logger, level, debug)

% Start with verbose output
rebar3 shell --verbose
```

## Contributing

### Development Guidelines

1. Follow Erlang/OTP best practices
2. Implement comprehensive tests
3. Document all public APIs
4. Handle errors gracefully
5. Monitor performance impact

### Running Tests

```bash
# Run unit tests
rebar3 eunit -m hotci_*

# Run integration tests
rebar3 ct --suite test/hotci_*

# Run property-based tests
rebar3 proper
```

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Support

For support and questions:

- Create an issue on GitHub
- Check the documentation
- Review the test examples
- Monitor logs for debugging information

---

HotCI provides a robust foundation for testing distributed Erlang/OTP systems, ensuring reliable hot code upgrades and maintaining system consistency across complex deployments.