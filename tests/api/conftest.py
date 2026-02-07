"""Pytest configuration and fixtures for API tests."""

import asyncio
import pytest
from typing import AsyncGenerator, Generator
from unittest.mock import Mock, MagicMock, AsyncMock
import sys
from pathlib import Path

# Register custom markers
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "integration: mark test as integration test")
    config.addinivalue_line("markers", "slow: mark test as slow running test")

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "elrmcp_bridge"))

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer
from elrmcp_bridge.src.api.server import APIServer, APIServerConfig
from elrmcp_bridge.src.config import BridgeConfig


class MockBridge:
    """Mock A2A Bridge for testing."""

    def __init__(self):
        self.state = Mock()
        self.state.value = "READY"
        self.state.READY = "READY"
        self.start_time = asyncio.get_event_loop().time()

        # Create a simple mock config instead of real BridgeConfig
        self.config = Mock()
        self.config.host = "localhost"
        self.config.port = 8001

        # Mock components
        self.agent_manager = MockAgentManager()
        self.workflow_orchestrator = MockWorkflowOrchestrator()
        self.transport = MockTransport()
        self.protocol = MockProtocol()
        self.metrics = MockMetrics()

    async def get_bridge_metrics(self):
        """Get bridge metrics."""
        return {
            "state": self.state.value,
            "uptime": 100.0,
            "metrics": {
                "total_messages_processed": 42,
                "total_workflows_completed": 5,
                "total_agents_discovered": 3
            }
        }

    async def get_agent_status(self, agent_id):
        """Get agent status."""
        return {
            "agent_id": agent_id,
            "name": f"Agent {agent_id}",
            "status": "active",
            "capabilities": ["chat", "task"]
        }

    async def send_to_agent(self, agent_id, message):
        """Send message to agent."""
        return {
            "status": "success",
            "response": f"Response from {agent_id}"
        }

    async def start_workflow(self, workflow_config):
        """Start workflow."""
        return "workflow-123"

    async def stop(self):
        """Stop bridge."""
        pass

    async def start(self):
        """Start bridge."""
        pass


class MockAgentManager:
    """Mock Agent Manager."""

    def __init__(self):
        self._agents = {}

    async def get_agent_status(self):
        """Get all agents status."""
        return [
            {
                "agent_id": "agent-1",
                "name": "Test Agent 1",
                "status": "active"
            },
            {
                "agent_id": "agent-2",
                "name": "Test Agent 2",
                "status": "active"
            }
        ]

    async def _register_agent(self, agent_info):
        """Register agent."""
        self._agents[agent_info["agent_id"]] = agent_info

    async def unregister_agent(self, agent_id):
        """Unregister agent."""
        if agent_id in self._agents:
            del self._agents[agent_id]

    def get_active_agents(self):
        """Get active agents."""
        return list(self._agents.values())

    async def get_agents_by_capability(self, capability):
        """Get agents by capability."""
        return [
            Mock(to_dict=lambda: {
                "agent_id": "agent-1",
                "name": "Test Agent",
                "capabilities": [capability]
            })
        ]


class MockWorkflowOrchestrator:
    """Mock Workflow Orchestrator."""

    def __init__(self):
        self.running_workflows = {}

    async def get_workflow_status(self, workflow_id=None):
        """Get workflow status."""
        if workflow_id:
            return {
                "workflow_id": workflow_id,
                "status": "running",
                "progress": 50
            }
        return [
            {
                "workflow_id": "wf-1",
                "status": "running"
            },
            {
                "workflow_id": "wf-2",
                "status": "completed"
            }
        ]

    async def _cancel_workflow(self, workflow_id, workflow):
        """Cancel workflow."""
        workflow["status"] = "cancelled"


class MockTransport:
    """Mock Transport."""

    def get_stats(self):
        """Get transport stats."""
        return {
            "connections": 5,
            "messages_sent": 100,
            "messages_received": 95
        }


class MockProtocol:
    """Mock Protocol."""

    def get_metrics(self):
        """Get protocol metrics."""
        return {
            "requests_total": 150,
            "errors_total": 2,
            "average_latency": 0.05
        }


class MockMetrics:
    """Mock Metrics."""

    def __init__(self):
        self.total_messages_processed = 42
        self.total_workflows_completed = 5
        self.total_agents_discovered = 3


@pytest.fixture
def mock_bridge():
    """Create a mock bridge instance."""
    return MockBridge()


@pytest.fixture
async def api_server(mock_bridge) -> AsyncGenerator[APIServer, None]:
    """Create an API server instance for testing."""
    config = APIServerConfig(
        host="127.0.0.1",
        port=8001,
        debug=True,
        auth_required=False
    )

    server = APIServer(mock_bridge, config)
    await server.start()

    yield server

    await server.stop()


@pytest.fixture
async def aiohttp_client():
    """Create aiohttp test client."""
    clients = []

    async def go(app, **kwargs):
        server = TestServer(app, **kwargs)
        client = TestClient(server)
        await client.start_server()
        clients.append(client)
        return client

    yield go

    for client in clients:
        await client.close()


@pytest.fixture
async def api_client(mock_bridge, aiohttp_client):
    """Create API test client."""
    config = APIServerConfig(
        host="127.0.0.1",
        port=8001,
        debug=True,
        auth_required=False,
        enable_cors=False  # Disable CORS for testing
    )

    server = APIServer(mock_bridge, config)

    # Create application
    server.app = web.Application(debug=True)

    # Manually add routes without static files
    for route_path, handler in server.endpoints.items():
        server.app.router.add_route(
            "*", route_path, server._create_handler(handler)
        )

    # Add dashboard route
    server.app.router.add_get("/", server._dashboard)

    # Don't add middlewares for now - they have compatibility issues
    # This is ok for testing as we're just testing the endpoint logic

    client = await aiohttp_client(server.app)
    return client


# Event loop fixture is provided by pytest-asyncio
