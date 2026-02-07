# A2A Protocol Performance Benchmarks and SLA Validation

This directory contains comprehensive performance benchmarking and SLA validation tools for the A2A Protocol.

## Overview

The performance testing suite includes:

1. **Benchmark Suite** (`benchmark_suite.py`) - Comprehensive performance benchmarks
2. **SLA Validator** (`sla_validator.py`) - Service Level Agreement validation
3. **Mock Server** (`mock_server.py`) - Lightweight mock API for testing

## Features

### Performance Metrics Tested

#### Latency Metrics
- **Health Check Latency** - Response time for health endpoint
- **API Endpoint Latency** - Individual endpoint response times
- **P50, P95, P99 Latencies** - Percentile latency measurements

#### Throughput Metrics
- **Concurrent Requests** - Throughput at various concurrency levels (10, 50, 100, 200)
- **Burst Load** - System behavior under sudden traffic spikes
- **Sustained Load** - Performance under continuous load (30s test)

#### Resource Usage Metrics
- **CPU Utilization** - Average and peak CPU usage
- **Memory Usage** - Average and peak memory consumption
- **Disk I/O** - Read/write operations per second

### SLA Definitions

The system validates the following SLAs:

#### Availability SLAs
- System availability: ≥99.9%
- Health check success rate: ≥99.95%
- Error rate: ≤0.1%

#### Latency SLAs
- Health check P50: ≤20ms
- Health check P95: ≤100ms (CRITICAL)
- Health check P99: ≤200ms (CRITICAL)
- API endpoint P95: ≤150ms (CRITICAL)
- Agent discovery P95: ≤200ms
- Workflow query P95: ≤200ms

#### Throughput SLAs
- Minimum throughput: ≥100 req/s (CRITICAL)
- Burst throughput: ≥500 req/s

#### Resource SLAs
- Average CPU utilization: ≤80%
- Average memory usage: ≤512MB
- Peak memory usage: ≤1GB (CRITICAL)

## Installation

```bash
# Install dependencies
pip install -r requirements.txt
```

## Usage

### Option 1: Run with Mock Server (Quick Test)

```bash
# Terminal 1 - Start mock server
python3 mock_server.py

# Terminal 2 - Run benchmarks
python3 benchmark_suite.py

# Terminal 3 - Run SLA validation
python3 sla_validator.py
```

### Option 2: Run with Real API Server

```bash
# Start your A2A API server on port 8001
# Then run the benchmarks
python3 benchmark_suite.py
python3 sla_validator.py
```

### Option 3: Use the Run Script

```bash
chmod +x run_benchmarks.sh
./run_benchmarks.sh
```

## Benchmark Tests

### Test 1: Health Check Latency
- Measures: Response time for health endpoint
- Requests: 1000
- Validates: Basic system responsiveness

### Test 2: API Endpoint Latency
- Measures: Individual endpoint performance
- Endpoints: /health, /bridge/status, /agents, /workflows, /metrics, /config, /system/info
- Requests: 500 per endpoint

### Test 3: Concurrent Throughput
- Measures: System throughput at different concurrency levels
- Concurrency levels: 10, 50, 100, 200
- Requests: 1000 per level

### Test 4: Burst Load
- Measures: System behavior under sudden traffic spikes
- Pattern: 50 requests per burst with brief pauses
- Total: 500 requests

### Test 5: Sustained Load
- Measures: Performance under continuous load
- Duration: 30 seconds
- Target rate: 50 req/s

### Test 6: Resource Usage
- Measures: CPU, memory, and disk I/O under load
- Requests: 1000 with concurrency of 100

### Test 7: Agent Discovery Performance
- Measures: Agent listing endpoint performance
- Requests: 300

### Test 8: Workflow Orchestration Performance
- Measures: Workflow query performance
- Requests: 300

## Output

### Benchmark Results
Results are saved to:
```
benchmark_results_YYYYMMDD_HHMMSS.json
```

Format:
```json
{
  "timestamp": "2024-01-01T12:00:00",
  "sla_targets": {...},
  "summary": {
    "total_tests": 15,
    "passed_sla": 13,
    "failed_sla": 2
  },
  "results": [...]
}
```

### SLA Validation Results
Results are saved to:
```
sla_validation_YYYYMMDD_HHMMSS.json
```

## Interpreting Results

### Performance Metrics

- **Latency**: Lower is better
  - P50: Median response time
  - P95: 95% of requests complete within this time
  - P99: 99% of requests complete within this time

- **Throughput**: Higher is better
  - Measured in requests per second (req/s)

- **Resource Usage**: Lower is better (within capacity)
  - CPU: Percentage of CPU capacity used
  - Memory: Megabytes of RAM used

### SLA Compliance

- ✅ **PASS**: Metric meets or exceeds SLA target
- ⚠️ **FAIL (non-critical)**: Metric doesn't meet target but system is operational
- ❌ **FAIL (critical)**: Critical SLA violation requiring immediate attention

## Customization

### Adjusting SLA Targets

Edit the `SLATargets` in `benchmark_suite.py`:

```python
sla_targets = SLATargets(
    max_latency_ms=100.0,          # Adjust P95 latency target
    max_p99_latency_ms=200.0,      # Adjust P99 latency target
    min_success_rate=99.9,         # Adjust success rate target
    max_cpu_percent=80.0,          # Adjust CPU limit
    max_memory_mb=512.0,           # Adjust memory limit
    min_throughput_rps=100.0       # Adjust throughput requirement
)
```

### Adding Custom Tests

Add new test methods to the `PerformanceBenchmark` class:

```python
async def test_custom_scenario(self):
    """Custom performance test"""
    # Your test implementation
    pass
```

## Continuous Integration

Integrate with CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Performance Tests
  run: |
    python3 tests/performance/benchmark_suite.py
    python3 tests/performance/sla_validator.py
```

## Troubleshooting

### Server Connection Issues
- Ensure the API server is running on `http://localhost:8001`
- Check firewall settings
- Verify the server is responding: `curl http://localhost:8001/health`

### High Latency
- Check system resource availability
- Verify network connectivity
- Review server logs for errors

### Failed SLAs
- Review specific failure reasons in the output
- Check resource constraints (CPU, memory)
- Analyze server configuration and capacity

## Contributing

When adding new performance tests:
1. Follow the existing test patterns
2. Document SLA targets and rationale
3. Include resource cleanup
4. Update this README

## License

Apache License 2.0 - See LICENSE file in the repository root
