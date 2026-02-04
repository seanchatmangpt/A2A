"""
Test fixtures for Craftplan MCP + A2A Integration

This module provides test fixtures for various testing scenarios:
- Mock servers and clients
- Test data fixtures
- Service fixtures
- Configuration fixtures
"""

import asyncio
import json
import time
from typing import Dict, Any, List, Optional

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from tests.utils import AsyncHTTPClient, TestWebSocketClient, TestDataGenerator


class MockMCPServer:
    """Mock MCP Server for testing"""

    def __init__(self, host: str = "localhost", port: int = 8090):
        self.host = host
        self.port = port
        self.app = FastAPI()
        self.client = TestClient(self.app)
        self.tools = {
            "customer_management": {
                "name": "customer_management",
                "description": "Manage customers",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "operation": {"type": "string", "enum": ["create", "read", "update", "delete"]},
                        "customer_id": {"type": "string"},
                        "customer_data": {"type": "object"}
                    }
                }
            },
            "order_management": {
                "name": "order_management",
                "description": "Manage orders",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "operation": {"type": "string", "enum": ["create", "update", "cancel"]},
                        "order_id": {"type": "string"},
                        "order_data": {"type": "object"}
                    }
                }
            }
        }
        self.setup_routes()

    def setup_routes(self):
        """Setup mock server routes"""

        @self.app.get("/health")
        async def health_check():
            return {"status": "ok", "service": "mcp", "timestamp": time.time()}

        @self.app.post("/mcp")
        async def mcp_handler(request: Dict[str, Any]):
            """Mock MCP handler"""
            if request.get("method") == "tools/list":
                return {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "tools": list(self.tools.values())
                    }
                }
            elif request.get("method") == "tools/call":
                tool_name = request["params"]["name"]
                if tool_name in self.tools:
                    return {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "result": {
                            "success": True,
                            "message": f"Tool {tool_name} executed successfully"
                        }
                    }
                else:
                    return {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "error": {
                            "code": -32601,
                            "message": f"Tool '{tool_name}' not found"
                        }
                    }
            else:
                return {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "error": {
                        "code": -32601,
                        "message": "Method not found"
                    }
                }

        @self.app.get("/.well-known/agent-card")
        async def agent_card():
            """Mock agent card endpoint"""
            return {
                "agent_id": "mock-mcp-server",
                "agent_type": "mcp",
                "capabilities": ["tools/call"],
                "endpoints": {
                    "mcp": f"http://{self.host}:{self.port}"
                },
                "metadata": {
                    "version": "1.0.0",
                    "created_at": time.time()
                }
            }

    def start(self):
        """Start the mock server"""
        import threading
        import uvicorn
        from concurrent.futures import ThreadPoolExecutor

        def run_server():
            uvicorn.run(self.app, host=self.host, port=self.port, log_level="error")

        self.executor = ThreadPoolExecutor(max_workers=1)
        self.executor.submit(run_server)

    def stop(self):
        """Stop the mock server"""
        if hasattr(self, 'executor'):
            self.executor.shutdown(wait=True)

    def get_client(self) -> TestClient:
        """Get test client"""
        return self.client


class MockA2AServer:
    """Mock A2A Server for testing"""

    def __init__(self, host: str = "localhost", port: int = 8080):
        self.host = host
        self.port = port
        self.app = FastAPI()
        self.client = TestClient(self.app)
        self.tasks = {}
        self.task_counter = 0
        self.setup_routes()

    def setup_routes(self):
        """Setup mock server routes"""

        @self.app.get("/health")
        async def health_check():
            return {"status": "ok", "service": "a2a", "timestamp": time.time()}

        @self.app.post("/a2a")
        async def a2a_handler(request: Dict[str, Any]):
            """Mock A2A handler"""
            if request.get("method") == "task.submit":
                task_type = request["params"]["task_type"]
                params = request["params"]["params"]

                self.task_counter += 1
                task_id = f"task_{self.task_counter}"

                self.tasks[task_id] = {
                    "id": task_id,
                    "task_type": task_type,
                    "params": params,
                    "status": "pending",
                    "created_at": time.time()
                }

                # Simulate task processing
                await asyncio.sleep(0.1)
                self.tasks[task_id]["status"] = "completed"

                return {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "task_id": task_id,
                        "status": "completed"
                    }
                }

            elif request.get("method") == "task.list":
                return {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "tasks": list(self.tasks.values())
                    }
                }

            elif request.get("method") == "task.get":
                task_id = request["params"]["task_id"]
                if task_id in self.tasks:
                    return {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "result": self.tasks[task_id]
                    }
                else:
                    return {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "error": {
                            "code": -32601,
                            "message": f"Task '{task_id}' not found"
                        }
                    }

        @self.app.get("/.well-known/agent-card")
        async def agent_card():
            """Mock agent card endpoint"""
            return {
                "agent_id": "mock-a2a-server",
                "agent_type": "a2a",
                "capabilities": ["task.submit", "task.list", "task.get"],
                "endpoints": {
                    "a2a": f"http://{self.host}:{self.port}"
                },
                "metadata": {
                    "version": "1.0.0",
                    "created_at": time.time()
                }
            }

    def start(self):
        """Start the mock server"""
        import threading
        import uvicorn
        from concurrent.futures import ThreadPoolExecutor

        def run_server():
            uvicorn.run(self.app, host=self.host, port=self.port, log_level="error")

        self.executor = ThreadPoolExecutor(max_workers=1)
        self.executor.submit(run_server)

    def stop(self):
        """Stop the mock server"""
        if hasattr(self, 'executor'):
            self.executor.shutdown(wait=True)

    def get_client(self) -> TestClient:
        """Get test client"""
        return self.client

    def get_tasks(self) -> Dict[str, Any]:
        """Get all tasks"""
        return self.tasks

    def clear_tasks(self):
        """Clear all tasks"""
        self.tasks.clear()
        self.task_counter = 0


class MockElrmcpServer:
    """Mock elrmcp Server for testing"""

    def __init__(self, host: str = "localhost", port: int = 9090):
        self.host = host
        self.port = port
        self.app = FastAPI()
        self.client = TestClient(self.app)
        self.relations = {}
        self.setup_routes()

    def setup_routes(self):
        """Setup mock server routes"""

        @self.app.get("/health")
        async def health_check():
            return {"status": "ok", "service": "elrmcp", "timestamp": time.time()}

        @self.app.post("/api/v1/relations")
        async def create_relation(request: Dict[str, Any]):
            """Mock relation creation"""
            relation_id = f"relation_{len(self.relations) + 1}"
            self.relations[relation_id] = request
            return {"relation_id": relation_id, "status": "created"}

        @self.app.get("/api/v1/relations")
        async def list_relations():
            """Mock relation listing"""
            return {"relations": list(self.relations.values())}

        @self.app.get("/api/v1/relations/{relation_id}")
        async def get_relation(relation_id: str):
            """Mock relation retrieval"""
            if relation_id in self.relations:
                return self.relations[relation_id]
            else:
                raise HTTPException(status_code=404, detail="Relation not found")

    def start(self):
        """Start the mock server"""
        import threading
        import uvicorn
        from concurrent.futures import ThreadPoolExecutor

        def run_server():
            uvicorn.run(self.app, host=self.host, port=self.port, log_level="error")

        self.executor = ThreadPoolExecutor(max_workers=1)
        self.executor.submit(run_server)

    def stop(self):
        """Stop the mock server"""
        if hasattr(self, 'executor'):
            self.executor.shutdown(wait=True)

    def get_client(self) -> TestClient:
        """Get test client"""
        return self.client

    def get_relations(self) -> Dict[str, Any]:
        """Get all relations"""
        return self.relations


# Test fixtures
@pytest.fixture
def mock_mcp_server():
    """Mock MCP server fixture"""
    server = MockMCPServer()
    server.start()
    yield server
    server.stop()


@pytest.fixture
def mock_a2a_server():
    """Mock A2A server fixture"""
    server = MockA2AServer()
    server.start()
    yield server
    server.stop()


@pytest.fixture
def mock_elrmcp_server():
    """Mock elrmcp server fixture"""
    server = MockElrmcpServer()
    server.start()
    yield server
    server.stop()


@pytest.fixture
def async_http_client(test_settings):
    """Async HTTP client fixture"""
    client = AsyncHTTPClient(test_settings.mcp_url)
    yield client
    asyncio.run(client.close())


@pytest.fixture
def test_data_generator():
    """Test data generator fixture"""
    return TestDataGenerator()


@pytest.fixture
def mcp_tool_calls(test_data_generator):
    """MCP tool calls test data"""
    return [
        test_data_generator.generate_mcp_tool_call(
            "customer_management",
            {"operation": "create", "customer_id": "cust_123", "customer_data": {"name": "Test Customer"}}
        ),
        test_data_generator.generate_mcp_tool_call(
            "order_management",
            {"operation": "create", "order_id": "ord_123", "order_data": {"items": []}}
        )
    ]


@pytest.fixture
def a2a_tasks(test_data_generator):
    """A2A tasks test data"""
    return [
        test_data_generator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        ),
        test_data_generator.generate_a2a_task(
            "shipping_management",
            {"operation": "create_shipment", "order_id": "ord_123"}
        )
    ]


@pytest.fixture
def agent_cards(test_data_generator):
    """Agent cards test data"""
    return [
        test_data_generator.generate_agent_card("mcp-server", "mcp"),
        test_data_generator.generate_agent_card("a2a-agent", "a2a"),
        test_data_generator.generate_agent_card("elrmcp-server", "elrmcp")
    ]


@pytest.fixture
def test_environments(mock_mcp_server, mock_a2a_server, mock_elrmcp_server):
    """Complete test environment with all mock servers"""
    return {
        "mcp": mock_mcp_server,
        "a2a": mock_a2a_server,
        "elrmcp": mock_elrmcp_server
    }