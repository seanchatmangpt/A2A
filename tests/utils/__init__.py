"""
Testing utilities for Craftplan MCP + A2A Integration

This package provides common utilities for testing the integration:
- Mock servers and clients
- Test data generators
- Performance measurement tools
- Assertion helpers
- Test configuration management
"""

import asyncio
import json
import logging
import time
from contextlib import asynccontextmanager, contextmanager
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Union

import httpx
import pytest
from fastapi import FastAPI
from websockets import WebSocketClientProtocol

logger = logging.getLogger(__name__)


@dataclass
class TestConfig:
    """Test configuration dataclass"""
    mcp_url: str = "http://localhost:8090"
    a2a_url: str = "http://localhost:8080"
    elrmcp_url: str = "http://localhost:9090"
    timeout: float = 30.0
    retry_attempts: int = 3
    debug: bool = False

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "mcp_url": self.mcp_url,
            "a2a_url": self.a2a_url,
            "elrmcp_url": self.elrmcp_url,
            "timeout": self.timeout,
            "retry_attempts": self.retry_attempts,
            "debug": self.debug
        }


class AsyncHTTPClient:
    """Async HTTP client for testing"""

    def __init__(self, base_url: str, timeout: float = 30.0):
        self.base_url = base_url
        self.timeout = httpx.Timeout(timeout)
        self.client = httpx.AsyncClient(timeout=self.timeout)

    async def close(self):
        """Close the HTTP client"""
        await self.client.aclose()

    async def get(self, endpoint: str, **kwargs) -> httpx.Response:
        """GET request"""
        url = f"{self.base_url}{endpoint}"
        response = await self.client.get(url, **kwargs)
        response.raise_for_status()
        return response

    async def post(self, endpoint: str, data: Any = None, **kwargs) -> httpx.Response:
        """POST request"""
        url = f"{self.base_url}{endpoint}"
        if data is not None and not isinstance(data, str):
            data = json.dumps(data)
        response = await self.client.post(url, data=data, **kwargs)
        response.raise_for_status()
        return response

    async def put(self, endpoint: str, data: Any = None, **kwargs) -> httpx.Response:
        """PUT request"""
        url = f"{self.base_url}{endpoint}"
        if data is not None and not isinstance(data, str):
            data = json.dumps(data)
        response = await self.client.put(url, data=data, **kwargs)
        response.raise_for_status()
        return response

    async def delete(self, endpoint: str, **kwargs) -> httpx.Response:
        """DELETE request"""
        url = f"{self.base_url}{endpoint}"
        response = await self.client.delete(url, **kwargs)
        response.raise_for_status()
        return response


class TestWebSocketClient:
    """WebSocket client for testing"""

    def __init__(self, url: str):
        self.url = url
        self.websocket = None

    async def connect(self) -> WebSocketClientProtocol:
        """Connect to WebSocket"""
        import websockets
        self.websocket = await websockets.connect(self.url)
        return self.websocket

    async def send(self, message: str):
        """Send message"""
        if self.websocket:
            await self.websocket.send(message)

    async def receive(self) -> str:
        """Receive message"""
        if self.websocket:
            return await self.websocket.recv()
        raise RuntimeError("WebSocket not connected")

    async def close(self):
        """Close connection"""
        if self.websocket:
            await self.websocket.close()


class PerformanceTimer:
    """Performance measurement timer"""

    def __init__(self, name: str):
        self.name = name
        self.start_time = None
        self.end_time = None

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, *args):
        self.end_time = time.time()

    @property
    def duration(self) -> float:
        """Get duration in seconds"""
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return 0.0

    def __str__(self):
        return f"{self.name}: {self.duration:.3f}s"


class TestDataGenerator:
    """Test data generator"""

    @staticmethod
    def generate_mcp_tool_call(tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Generate MCP tool call"""
        return {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": arguments
            },
            "id": f"mcp_call_{tool_name}"
        }

    @staticmethod
    def generate_a2a_task(task_type: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """Generate A2A task"""
        return {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": task_type,
                "params": params
            },
            "id": f"a2a_task_{task_type}"
        }

    @staticmethod
    def generate_agent_card(agent_id: str, agent_type: str = "mcp") -> Dict[str, Any]:
        """Generate agent card"""
        return {
            "agent_id": agent_id,
            "agent_type": agent_type,
            "capabilities": [
                {
                    "name": "tools/call",
                    "description": "Can call MCP tools"
                }
            ],
            "endpoints": {
                "mcp": f"http://localhost:8090",
                "a2a": f"http://localhost:8080"
            },
            "metadata": {
                "version": "1.0.0",
                "created_at": time.time()
            }
        }


@contextmanager
def mock_server(endpoint: str, response_data: Dict[str, Any]):
    """Mock server context manager"""
    import threading
    import http.server
    import socketserver
    import json
    from io import StringIO

    class MockHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response_data).encode())

        def log_request(self, *args):
            pass

    handler = MockHandler

    with socketserver.TCPServer(("", 0), handler) as httpd:
        port = httpd.server_address[1]

        def serve():
            httpd.handle_request()

        thread = threading.Thread(target=serve)
        thread.daemon = True
        thread.start()

        yield f"http://localhost:{port}"
        httpd.shutdown()


@asynccontextmanager
async def mock_websocket_server(handler):
    """Mock WebSocket server context manager"""
    import websockets
    import asyncio

    async def echo_server(websocket, path):
        await handler(websocket, path)

    async with websockets.serve(echo_server, "localhost", 8765):
        yield "ws://localhost:8765"


def assert_mcp_response(response: Dict[str, Any], expected_result: Dict[str, Any] = None):
    """Assert MCP response structure"""
    assert response["jsonrpc"] == "2.0"
    assert "id" in response
    assert "result" in response or "error" in response

    if expected_result:
        assert response["result"] == expected_result

    if "error" in response:
        error = response["error"]
        assert "code" in error
        assert "message" in error


def assert_a2a_response(response: Dict[str, Any], expected_result: Dict[str, Any] = None):
    """Assert A2A response structure"""
    assert response["jsonrpc"] == "2.0"
    assert "id" in response
    assert "result" in response or "error" in response

    if expected_result:
        assert response["result"] == expected_result

    if "error" in response:
        error = response["error"]
        assert "code" in error
        assert "message" in error


def wait_for_condition(condition_func, timeout: float = 10.0, interval: float = 0.1):
    """Wait for condition to be true"""
    start_time = time.time()

    while time.time() - start_time < timeout:
        if condition_func():
            return True
        time.sleep(interval)

    return False


async def async_wait_for_condition(condition_func, timeout: float = 10.0, interval: float = 0.1):
    """Async wait for condition to be true"""
    start_time = time.time()

    while time.time() - start_time < timeout:
        if condition_func():
            return True
        await asyncio.sleep(interval)

    return False


class TestMetrics:
    """Test metrics collector"""

    def __init__(self):
        self.metrics = {
            "requests": 0,
            "responses": 0,
            "errors": 0,
            "response_times": [],
            "start_time": time.time()
        }

    def record_request(self):
        """Record a request"""
        self.metrics["requests"] += 1

    def record_response(self, response_time: float = None):
        """Record a response"""
        self.metrics["responses"] += 1
        if response_time:
            self.metrics["response_times"].append(response_time)

    def record_error(self):
        """Record an error"""
        self.metrics["errors"] += 1

    @property
    def success_rate(self) -> float:
        """Calculate success rate"""
        total = self.metrics["requests"]
        if total == 0:
            return 0.0
        return (total - self.metrics["errors"]) / total

    @property
    def avg_response_time(self) -> float:
        """Calculate average response time"""
        if not self.metrics["response_times"]:
            return 0.0
        return sum(self.metrics["response_times"]) / len(self.metrics["response_times"])

    def to_dict(self) -> Dict[str, Any]:
        """Convert metrics to dictionary"""
        return {
            **self.metrics,
            "success_rate": self.success_rate,
            "avg_response_time": self.avg_response_time,
            "duration": time.time() - self.metrics["start_time"]
        }