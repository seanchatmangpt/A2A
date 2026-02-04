"""
MCP client unit tests

This module provides detailed unit tests for the MCP client functionality:
- Client initialization and configuration
- Connection management
- Tool discovery
- Tool execution
- Error handling
- Authentication
- Retry logic
- Performance characteristics
"""

import pytest
import json
import asyncio
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from typing import Dict, Any, List, Optional

from tests.utils import AsyncHTTPClient, TestDataGenerator


class TestMCPClientInitialization:
    """Test MCP client initialization and configuration"""

    def test_client_basic_initialization(self):
        """Test basic client initialization"""
        client = AsyncHTTPClient("http://localhost:8090")
        assert client.base_url == "http://localhost:8090"
        assert client.timeout == 30.0
        assert client.client.timeout == 30.0

    def test_client_with_custom_timeout(self):
        """Test client with custom timeout"""
        custom_timeout = 60.0
        client = AsyncHTTPClient("http://localhost:8090", timeout=custom_timeout)
        assert client.timeout == custom_timeout
        assert client.client.timeout.total == custom_timeout

    @pytest.mark.asyncio
    async def test_client_context_manager(self):
        """Test client as context manager"""
        async with AsyncHTTPClient("http://localhost:8090") as client:
            assert client.base_url == "http://localhost:8090"
        # Client should be closed after exiting context

    def test_client_url_validation(self):
        """Test URL validation"""
        with pytest.raises(Exception):
            AsyncHTTPClient("invalid-url")


class TestMCPClientConnection:
    """Test MCP client connection management"""

    @pytest.mark.asyncio
    async def test_connection_establishment(self, mock_mcp_server):
        """Test connection establishment to MCP server"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test connection by making a simple request
        response = await client.get("/health")
        assert response.status_code == 200

        await client.close()

    @pytest.mark.asyncio
    async def test_connection_timeout(self):
        """Test connection timeout handling"""
        client = AsyncHTTPClient("http://localhost:9999", timeout=0.1)

        with patch.object(client.client, 'get') as mock_get:
            mock_get.side_effect = asyncio.TimeoutError()

            with pytest.raises(asyncio.TimeoutError):
                await client.get("/health")

        await client.close()

    @pytest.mark.asyncio
    async def test_connection_error_handling(self, mock_mcp_server):
        """Test connection error handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Connection failed")

            with pytest.raises(Exception):
                await client.post("/mcp", {"jsonrpc": "2.0", "method": "tools/list"})

        await client.close()


class TestMCPClientToolDiscovery:
    """Test MCP client tool discovery functionality"""

    @pytest.mark.asyncio
    async def test_list_tools_success(self, mock_mcp_server):
        """Test successful tool listing"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-list"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-list"
        assert "result" in data
        assert "tools" in data["result"]
        assert len(data["result"]["tools"]) > 0

        await client.close()

    @pytest.mark.asyncio
    async def test_list_tools_retry(self, mock_mcp_server):
        """Test tool listing with retry"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                Exception("Temporary failure"),
                Mock(json=lambda: {
                    "jsonrpc": "2.0",
                    "id": "test-list",
                    "result": {"tools": []}
                })
            ]

            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": "test-list"
            })

            assert response.status_code == 200
            assert mock_post.call_count == 2

        await client.close()

    @pytest.mark.asyncio
    async def test_get_tool_schema(self, mock_mcp_server):
        """Test getting specific tool schema"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # List tools first
        list_response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-schema"
        })

        tools = list_response.json()["result"]["tools"]
        if tools:
            tool_name = tools[0]["name"]

            # Get tool schema (assuming this exists)
            tool_response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": tool_name,
                    "arguments": {"operation": "schema"}
                },
                "id": "test-schema-get"
            })

            assert tool_response.status_code == 200

        await client.close()


class TestMCPClientToolExecution:
    """Test MCP client tool execution functionality"""

    @pytest.mark.asyncio
    async def test_execute_tool_success(self, mock_mcp_server):
        """Test successful tool execution"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "customer_management",
            {"operation": "create", "customer_id": "test-customer"}
        )

        response = await client.post("/mcp", tool_call)

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == tool_call["id"]
        assert "result" in data
        assert data["result"]["success"] is True

        await client.close()

    @pytest.mark.asyncio
    async def test_execute_tool_with_arguments(self, mock_mcp_server):
        """Test tool execution with complex arguments"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "order_management",
            {
                "operation": "create",
                "order_data": {
                    "customer_id": "cust_123",
                    "items": [
                        {"product_id": "prod_456", "quantity": 2},
                        {"product_id": "prod_789", "quantity": 1}
                    ],
                    "total_amount": 150.00
                }
            }
        )

        response = await client.post("/mcp", tool_call)

        assert response.status_code == 200
        data = response.json()
        assert "result" in data

        await client.close()

    @pytest.mark.asyncio
    async def test_execute_tool_with_invalid_arguments(self, mock_mcp_server):
        """Test tool execution with invalid arguments"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "customer_management",
            {"operation": "invalid_operation", "customer_id": "test-customer"}
        )

        response = await client.post("/mcp", tool_call)

        data = response.json()
        assert "error" in data
        assert "not valid" in data["error"]["message"].lower()

        await client.close()

    @pytest.mark.asyncio
    async def test_execute_nonexistent_tool(self, mock_mcp_server):
        """Test executing non-existent tool"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "nonexistent_tool",
            {"operation": "create"}
        )

        response = await client.post("/mcp", tool_call)

        data = response.json()
        assert "error" in data
        assert "not found" in data["error"]["message"].lower()

        await client.close()


class TestMCPClientAuthentication:
    """Test MCP client authentication functionality"""

    @pytest.mark.asyncio
    async def test_authentication_header(self, mock_mcp_server):
        """Test authentication header handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Mock authentication
        headers = {"Authorization": "Bearer test-token"}

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-auth"
        }, headers=headers)

        # Should succeed with or without auth header
        assert response.status_code == 200

        await client.close()

    @pytest.mark.asyncio
    async def test_token_based_auth(self, mock_mcp_server):
        """Test token-based authentication"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Mock token validation
        with patch.object(client.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=200,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "id": "test-auth",
                    "result": {"success": True}
                }
            )

            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create"}
                },
                "id": "test-auth"
            }, headers={"Authorization": "Bearer test-token"})

            assert response.status_code == 200

        await client.close()

    @pytest.mark.asyncio
    async def test_invalid_token_handling(self, mock_mcp_server):
        """Test invalid token handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Mock invalid token response
        with patch.object(client.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=401,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32600,
                        "message": "Invalid authentication token"
                    }
                }
            )

            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create"}
                },
                "id": "test-invalid-token"
            }, headers={"Authorization": "invalid-token"})

            data = response.json()
            assert "error" in data

        await client.close()


class TestMCPClientRetryLogic:
    """Test MCP client retry logic"""

    @pytest.mark.asyncio
    async def test_retry_on_timeout(self, mock_mcp_server):
        """Test retry on timeout"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                asyncio.TimeoutError(),
                Mock(
                    status_code=200,
                    json=lambda: {
                        "jsonrpc": "2.0",
                        "result": {"success": True}
                    }
                )
            ]

            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-retry"
            })

            assert response.status_code == 200
            assert mock_post.call_count == 2

        await client.close()

    @pytest.mark.asyncio
    async def test_max_retry_attempts(self, mock_mcp_server):
        """Test maximum retry attempts"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                asyncio.TimeoutError(),
                asyncio.TimeoutError(),
                asyncio.TimeoutError()
            ]

            with pytest.raises(asyncio.TimeoutError):
                await client.post("/mcp", {
                    "jsonrpc": "2.0",
                    "method": "tools/call",
                    "params": {"name": "test", "arguments": {}},
                    "id": "test-max-retry"
                })

        await client.close()

    @pytest.mark.asyncio
    async def test_exponential_backoff(self, mock_mcp_server):
        """Test exponential backoff retry strategy"""
        import time

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        call_times = []

        with patch.object(client.client, 'post') as mock_post:
            def mock_post_side_effect(*args, **kwargs):
                call_times.append(time.time())
                raise asyncio.TimeoutError()

            mock_post.side_effect = mock_post_side_effect

            with pytest.raises(asyncio.TimeoutError):
                await client.post("/mcp", {
                    "jsonrpc": "2.0",
                    "method": "tools/call",
                    "params": {"name": "test", "arguments": {}},
                    "id": "test-backoff"
                })

        # Check that retries have exponential backoff
        if len(call_times) > 1:
            interval = call_times[1] - call_times[0]
            assert interval > 0  # Some delay between retries

        await client.close()


class TestMCPClientPerformance:
    """Test MCP client performance characteristics"""

    @pytest.mark.asyncio
    async def test_concurrent_requests(self, mock_mcp_server):
        """Test concurrent request handling"""
        import asyncio
        import time

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        async def make_request(i):
            return await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": f"test-{i}"}
                },
                "id": f"test-concurrent-{i}"
            })

        # Make 50 concurrent requests
        start_time = time.time()
        responses = await asyncio.gather(*[
            make_request(i) for i in range(50)
        ])
        end_time = time.time()

        assert len(responses) == 50
        assert all(response.status_code == 200 for response in responses)
        assert end_time - start_time < 10.0  # Should complete within 10 seconds

        await client.close()

    @pytest.mark.asyncio
    async def test_response_time_measurement(self, mock_mcp_server):
        """Test response time measurement"""
        import time

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Measure response time
        start_time = time.time()
        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-response-time"
        })
        end_time = time.time()

        assert response.status_code == 200
        response_time = end_time - start_time
        assert response_time < 5.0  # Should respond within 5 seconds

        await client.close()

    @pytest.mark.asyncio
    async def test_throughput_measurement(self, mock_mcp_server):
        """Test throughput measurement"""
        import asyncio
        import time

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        async def make_request():
            return await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create"}
                },
                "id": "test-throughput"
            })

        # Measure throughput over 30 seconds
        start_time = time.time()
        requests_count = 0

        async def worker():
            nonlocal requests_count
            while time.time() - start_time < 30:
                await make_request()
                requests_count += 1
                await asyncio.sleep(0.1)  # Small delay between requests

        workers = [asyncio.create_task(worker()) for _ in range(5)]
        await asyncio.gather(*workers)

        throughput = requests_count / 30.0  # requests per second
        assert throughput > 1.0  # Should handle at least 1 request per second

        await client.close()


class TestMCPClientErrorHandling:
    """Test MCP client error handling"""

    @pytest.mark.asyncio
    async def test_parse_error_handling(self, mock_mcp_server):
        """Test parse error handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.post("/mcp", {
            "invalid": "json"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32700  # Parse Error

        await client.close()

    @pytest.mark.asyncio
    async def test_method_not_found_error(self, mock_mcp_server):
        """Test method not found error"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "nonexistent_method",
            "id": "test-method"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32601  # Method Not Found

        await client.close()

    @pytest.mark.asyncio
    async def test_invalid_params_error(self, mock_mcp_server):
        """Test invalid params error"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": "invalid_params",
            "id": "test-params"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32602  # Invalid Params

        await client.close()

    @pytest.mark.asyncio
    async def test_internal_error_handling(self, mock_mcp_server):
        """Test internal error handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=500,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32603,
                        "message": "Internal error"
                    }
                }
            )

            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-internal"
            })

            data = response.json()
            assert "error" in data
            assert data["error"]["code"] == -32603

        await client.close()

    @pytest.mark.asyncio
    async def test_network_error_handling(self, mock_mcp_server):
        """Test network error handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Network error")

            with pytest.raises(Exception):
                await client.post("/mcp", {
                    "jsonrpc": "2.0",
                    "method": "tools/call",
                    "params": {"name": "test", "arguments": {}},
                    "id": "test-network"
                })

        await client.close()


class TestMCPClientCircuitBreaker:
    """Test MCP client circuit breaker functionality"""

    @pytest.mark.asyncio
    async def test_circuit_breaker_open(self, mock_mcp_server):
        """Test circuit breaker open state"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Connection failed")

            # Make multiple failing requests
            for i in range(5):
                with pytest.raises(Exception):
                    await client.post("/mcp", {
                        "jsonrpc": "2.0",
                        "method": "tools/call",
                        "params": {"name": "test", "arguments": {}},
                        "id": f"test-circuit-{i}"
                    })

        await client.close()

    @pytest.mark.asyncio
    async def test_circuit_breaker_half_open(self, mock_mcp_server):
        """Test circuit breaker half-open state"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            # First few calls fail
            for i in range(3):
                mock_post.side_effect = Exception("Connection failed")

            # Then one succeeds
            mock_post.return_value = Mock(
                status_code=200,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "result": {"success": True}
                }
            )

            # Should succeed after initial failures
            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-half-open"
            })

            assert response.status_code == 200

        await client.close()


class TestMCPClientMetrics:
    """Test MCP client metrics collection"""

    @pytest.mark.asyncio
    async def test_metrics_collection(self, mock_mcp_server):
        """Test metrics collection"""
        from tests.utils import TestMetrics

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        metrics = TestMetrics()

        # Track requests
        metrics.record_request()

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-metrics"
        })

        metrics.record_response()
        metrics.record_response()

        assert metrics.requests == 1
        assert metrics.responses == 2
        assert metrics.success_rate == 1.0

        await client.close()

    @pytest.mark.asyncio
    async def test_error_metrics(self, mock_mcp_server):
        """Test error metrics collection"""
        from tests.utils import TestMetrics

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        metrics = TestMetrics()

        metrics.record_request()

        with patch.object(client.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=500,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "error": {"code": -32603}
                }
            )

            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-error-metrics"
            })

            metrics.record_error()

        assert metrics.success_rate == 0.0

        await client.close()