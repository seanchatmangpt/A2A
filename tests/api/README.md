# A2A Bridge API Test Suite

Comprehensive API testing suite for the A2A Bridge REST API, including both pytest-based tests and Newman/Postman collection tests.

## Overview

This test suite validates all endpoints of the A2A Bridge API, including:

- **Health & System Endpoints**: Health checks, system info, metrics, logs
- **Agent Endpoints**: Agent registration, listing, updates, deletion, messaging
- **Workflow Endpoints**: Workflow creation, monitoring, cancellation, logs
- **Configuration Endpoints**: Configuration management

## Test Structure

```
tests/api/
├── __init__.py                 # Package initialization
├── conftest.py                 # Pytest fixtures and configuration
├── test_health_endpoints.py    # Health and system endpoint tests
├── test_agent_endpoints.py     # Agent management tests
├── test_workflow_endpoints.py  # Workflow management tests
├── test_integration.py         # Integration tests
├── postman_collection.json     # Newman/Postman test collection
├── run_tests.sh               # Test runner script
└── README.md                  # This file
```

## Requirements

### Python Dependencies

```bash
pip install -r requirements.txt
```

Required packages:
- pytest>=7.4.3
- pytest-asyncio>=0.21.1
- pytest-cov>=4.1.0
- pytest-httpx>=0.27.0
- aiohttp>=3.8.0
- httpx>=0.25.2

### Newman (Optional)

For running Postman collection tests:

```bash
npm install -g newman
npm install -g newman-reporter-html
```

## Running Tests

### Quick Start

Run all tests:

```bash
./run_tests.sh
```

### Pytest Tests

Run all pytest tests:

```bash
pytest tests/api/ -v
```

Run specific test file:

```bash
pytest tests/api/test_health_endpoints.py -v
```

Run tests by marker:

```bash
pytest tests/api/ -v -m "not integration"  # Skip integration tests
pytest tests/api/ -v -m "integration"       # Only integration tests
```

Run with coverage:

```bash
pytest tests/api/ --cov=elrmcp_bridge/src/api --cov-report=html
```

### Newman Tests

Run Newman collection:

```bash
newman run tests/api/postman_collection.json \
  --reporters cli,html \
  --reporter-html-export tests/api/newman-report.html
```

With environment variables:

```bash
newman run tests/api/postman_collection.json \
  --env-var "base_url=http://localhost:8001" \
  --reporters cli,html
```

## Test Categories

### 1. Health Endpoint Tests

Tests for system health and monitoring:

- `test_health_check_success`: Basic health check
- `test_bridge_status`: Bridge status endpoint
- `test_system_info`: System information
- `test_metrics_endpoint`: Metrics collection
- `test_system_logs`: Log retrieval

### 2. Agent Endpoint Tests

Tests for agent management:

- **List & Get**:
  - `test_list_agents`: List all agents
  - `test_get_specific_agent`: Get agent by ID

- **Registration**:
  - `test_register_agent_minimal`: Register with minimal data
  - `test_register_agent_full`: Register with full data
  - `test_register_agent_duplicate_id`: Handle duplicates

- **Updates**:
  - `test_update_agent`: Update agent information
  - `test_update_agent_status`: Update agent status

- **Deletion**:
  - `test_delete_agent`: Delete agent
  - `test_delete_nonexistent_agent`: Handle missing agents

- **Messaging**:
  - `test_send_message_to_agent`: Send messages
  - `test_send_empty_message`: Validation

- **Capabilities**:
  - `test_get_agents_by_capability`: Query by capability

### 3. Workflow Endpoint Tests

Tests for workflow management:

- **List & Get**:
  - `test_list_workflows`: List all workflows
  - `test_get_specific_workflow`: Get workflow by ID

- **Creation**:
  - `test_start_workflow_minimal`: Start with minimal config
  - `test_start_workflow_full`: Start with full config
  - `test_start_workflow_missing_config`: Validation

- **Control**:
  - `test_cancel_workflow`: Cancel workflow
  - `test_update_workflow_status`: Update status

- **Logs**:
  - `test_get_workflow_logs`: Retrieve logs
  - `test_workflow_logs_structure`: Log format validation

### 4. Integration Tests

End-to-end workflow tests:

- `test_agent_registration_and_workflow`: Agent + workflow interaction
- `test_complete_agent_lifecycle`: Full CRUD lifecycle
- `test_workflow_creation_and_monitoring`: Workflow lifecycle
- `test_concurrent_operations`: Concurrent requests

## Test Fixtures

### `mock_bridge`

Provides a mock A2A Bridge instance with:
- Agent Manager
- Workflow Orchestrator
- Transport layer
- Protocol handler
- Metrics collector

### `api_client`

Async HTTP client for testing API endpoints.

### `api_server`

Running API server instance for integration tests.

## Configuration

### Pytest Configuration

Edit `pytest.ini` or `pyproject.toml`:

```ini
[tool.pytest.ini_options]
testpaths = ["tests/api"]
asyncio_mode = "auto"
markers = [
    "integration: Integration tests",
    "slow: Slow-running tests"
]
```

### Newman Configuration

Edit `postman_collection.json` variables:

```json
{
  "variable": [
    {
      "key": "base_url",
      "value": "http://localhost:8001"
    }
  ]
}
```

## Coverage

Generate coverage report:

```bash
pytest tests/api/ --cov=elrmcp_bridge/src/api --cov-report=html
```

View coverage:

```bash
open htmlcov/index.html  # macOS
xdg-open htmlcov/index.html  # Linux
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Run API Tests
  run: |
    pip install -r tests/requirements.txt
    pytest tests/api/ -v --cov=elrmcp_bridge/src/api

- name: Run Newman Tests
  run: |
    npm install -g newman
    newman run tests/api/postman_collection.json
```

### GitLab CI

```yaml
api-tests:
  script:
    - pip install -r tests/requirements.txt
    - pytest tests/api/ -v --cov=elrmcp_bridge/src/api
    - newman run tests/api/postman_collection.json
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: tests/api/coverage.xml
```

## Troubleshooting

### Tests fail with import errors

Ensure the project is in your Python path:

```bash
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
```

### Newman not found

Install Newman globally:

```bash
npm install -g newman
```

### Async test warnings

Install pytest-asyncio:

```bash
pip install pytest-asyncio
```

### Connection refused errors

Ensure the API server is running or tests are using mocks properly.

## Best Practices

1. **Isolation**: Each test should be independent
2. **Cleanup**: Use fixtures for setup/teardown
3. **Assertions**: Multiple specific assertions > one general assertion
4. **Error Cases**: Test both success and failure paths
5. **Documentation**: Clear test names and docstrings
6. **Performance**: Mark slow tests appropriately

## Contributing

When adding new tests:

1. Follow existing naming conventions
2. Add appropriate markers (`@pytest.mark.asyncio`, `@pytest.mark.integration`)
3. Update this README with new test descriptions
4. Ensure tests are isolated and repeatable
5. Add corresponding Newman tests if applicable

## Support

For issues or questions:
- Open an issue in the repository
- Check existing test examples
- Review API documentation
