"""
Pytest configuration for elrmcp_bridge tests
"""

import pytest
import asyncio
import sys
from pathlib import Path

# Add the src directory to Python path
src_path = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(src_path))

# Configure pytest for async tests
@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

# Global test configuration
@pytest.fixture
def test_config():
    """Test configuration dictionary"""
    return {
        "test_mode": True,
        "debug": True,
        "mock_data": True,
        "test_timeout": 30,
        "retry_attempts": 3
    }

@pytest.fixture
def mock_response():
    """Mock response for API calls"""
    return {
        "status": "success",
        "data": {
            "id": "test-id",
            "result": "test-result"
        },
        "timestamp": "2023-01-01T00:00:00Z"
    }

@pytest.fixture
def sample_workflow_data():
    """Sample workflow data for tests"""
    return {
        "workflow_id": "test-workflow",
        "name": "Test Workflow",
        "description": "A test workflow for unit tests",
        "tasks": [
            {
                "task_id": "task-1",
                "name": "first_task",
                "type": "agent",
                "parameters": {
                    "input": "test_data"
                }
            },
            {
                "task_id": "task-2",
                "name": "second_task",
                "type": "agent",
                "parameters": {
                    "input": "{{task-1.result}}"
                },
                "dependencies": ["task-1"]
            }
        ],
        "timeout": 300,
        "priority": 1
    }

@pytest.fixture
def sample_agent_data():
    """Sample agent data for tests"""
    return {
        "agent_id": "test-agent",
        "name": "Test Agent",
        "version": "1.0.0",
        "capabilities": ["file_operations", "data_processing"],
        "endpoints": {
            "a2a": "http://localhost:9090",
            "websocket": "ws://localhost:9090/ws"
        },
        "metadata": {
            "type": "test",
            "purpose": "testing"
        },
        "status": "active"
    }

@pytest.fixture
def sample_message_data():
    """Sample message data for tests"""
    return {
        "id": "msg-123",
        "type": "mcp_request",
        "method": "tools/call",
        "params": {
            "name": "file_read",
            "arguments": {
                "path": "/tmp/test.txt"
            }
        }
    }

# Test utilities
def create_mock_component(component_class, **kwargs):
    """Factory function to create mock components"""
    mock = Mock(spec=component_class)
    mock.start = AsyncMock()
    mock.stop = AsyncMock()
    mock.is_running = False
    return mock

# Async test helpers
async def async_sleep(seconds):
    """Helper for async sleep in tests"""
    await asyncio.sleep(seconds)

def create_test_task(task_id, name, task_type="agent", parameters=None, dependencies=None):
    """Helper to create test tasks"""
    from elrmcp_bridge.src.workflows import TaskDefinition

    return TaskDefinition(
        task_id=task_id,
        name=name,
        type=task_type,
        parameters=parameters or {},
        dependencies=dependencies or []
    )

def create_test_agent(agent_id, name, capabilities=None, status="active"):
    """Helper to create test agents"""
    from elrmcp_bridge.src.agents import Agent

    return Agent(
        agent_id=agent_id,
        name=name,
        version="1.0.0",
        capabilities=capabilities or [],
        endpoints={},
        metadata={},
        status=status,
        last_seen=asyncio.get_event_loop().time()
    )

# Test markers
def pytest_configure(config):
    """Configure pytest markers"""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests"
    )
    config.addinivalue_line(
        "markers", "unit: marks tests as unit tests"
    )
    config.addinivalue_line(
        "markers", "asyncio: marks tests as asyncio tests"
    )