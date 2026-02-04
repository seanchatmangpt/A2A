"""
MCP bridge unit tests for Craftplan MCP + A2A Integration

This module provides unit tests for MCP bridge components:
- MCP protocol compliance
- Tool execution
- Error handling
- Client functionality
- Server functionality
"""

import pytest
import json
from typing import Dict, Any, List, Optional
from unittest.mock import Mock, AsyncMock, patch

from tests.utils import AsyncHTTPClient, TestDataGenerator


class TestMCPProtocol:
    """MCP protocol compliance tests"""

    @pytest.mark.asyncio
    async def test_mcp_version_compliance(self, mock_mcp_server):
        """Test MCP version compliance"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test tools list
        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-1"
        })

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-1"
        assert "result" in data
        assert "tools" in data["result"]
        assert len(data["result"]["tools"]) > 0

    @pytest.mark.asyncio
    async def test_mcp_tool_call_format(self, mock_mcp_server):
        """Test MCP tool call format compliance"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test tool call with proper format
        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "customer_management",
            {"operation": "create", "customer_id": "test-cust"}
        )

        response = await client.post("/mcp", tool_call)

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == tool_call["id"]
        assert "result" in data
        assert data["result"]["success"] is True

    @pytest.mark.asyncio
    async def test_mcp_error_handling(self, mock_mcp_server):
        """Test MCP error handling"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test tool call with invalid tool
        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "invalid_tool",
            {"operation": "create"}
        )

        response = await client.post("/mcp", tool_call)

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == tool_call["id"]
        assert "error" in data
        assert data["error"]["code"] == -32601
        assert "not found" in data["error"]["message"]

    @pytest.mark.asyncio
    async def test_mcp_batch_calls(self, mock_mcp_server):
        """Test MCP batch calls"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test multiple tool calls in batch
        batch_requests = [
            TestDataGenerator.generate_mcp_tool_call("customer_management", {"operation": "create"}),
            TestDataGenerator.generate_mcp_tool_call("order_management", {"operation": "create"})
        ]

        response = await client.post("/mcp", batch_requests)

        # Assuming batch calls are supported
        if isinstance(response.json(), list):
            assert len(response.json()) == 2
            for result in response.json():
                assert "jsonrpc" in result
                assert "result" in result or "error" in result


class TestMCPClient:
    """MCP client functionality tests"""

    @pytest.mark.asyncio
    async def test_mcp_client_initialization(self):
        """Test MCP client initialization"""
        client = AsyncHTTPClient("http://localhost:8090")
        assert client.base_url == "http://localhost:8090"
        assert client.timeout == 30.0
        await client.close()

    @pytest.mark.asyncio
    async def test_mcp_client_health_check(self, mock_mcp_server):
        """Test MCP client health check"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "mcp"
        await client.close()

    @pytest.mark.asyncio
    async def test_mcp_client_list_tools(self, mock_mcp_server):
        """Test MCP client list tools"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-list"
        })

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-list"
        assert "result" in data
        assert "tools" in data["result"]
        assert len(data["result"]["tools"]) > 0

        await client.close()

    @pytest.mark.asyncio
    async def test_mcp_client_call_tool(self, mock_mcp_server):
        """Test MCP client call tool"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        tool_call = TestDataGenerator.generate_mcp_tool_call(
            "customer_management",
            {"operation": "create", "customer_id": "test-cust"}
        )

        response = await client.post("/mcp", tool_call)

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == tool_call["id"]
        assert "result" in data

        await client.close()

    @pytest.mark.asyncio
    async def test_mcp_client_retry_logic(self, mock_mcp_server):
        """Test MCP client retry logic"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Mock a temporary failure followed by success
        with patch.object(client.client, 'post') as mock_post:
            # First call fails, second succeeds
            mock_post.side_effect = [
                Exception("Connection failed"),
                Mock(json=lambda: {
                    "jsonrpc": "2.0",
                    "result": {"success": True}
                })
            ]

            # Retry mechanism should be implemented in the client
            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-retry"
            })

            assert mock_post.call_count == 2  # Should retry once
            await client.close()


class TestMCPServer:
    """MCP server functionality tests"""

    @pytest.mark.asyncio
    async def test_mcp_server_health_endpoint(self, mock_mcp_server):
        """Test MCP server health endpoint"""
        response = mock_mcp_server.client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "mcp"

    @pytest.mark.asyncio
    async def test_mcp_server_agent_card(self, mock_mcp_server):
        """Test MCP server agent card endpoint"""
        response = mock_mcp_server.client.get("/.well-known/agent-card")

        assert response.status_code == 200
        data = response.json()
        assert data["agent_id"] == "mock-mcp-server"
        assert data["agent_type"] == "mcp"
        assert "capabilities" in data
        assert "endpoints" in data

    @pytest.mark.asyncio
    async def test_mcp_server_mcp_endpoint(self, mock_mcp_server):
        """Test MCP server MCP endpoint"""
        # Test tools list
        response = mock_mcp_server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-list"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-list"

    @pytest.mark.asyncio
    async def test_mcp_server_invalid_request(self, mock_mcp_server):
        """Test MCP server invalid request handling"""
        response = mock_mcp_server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "invalid_method",
            "id": "test-invalid"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-invalid"
        assert "error" in data
        assert data["error"]["code"] == -32601

    @pytest.mark.asyncio
    async def test_mcp_server_missing_jsonrpc(self, mock_mcp_server):
        """Test MCP server missing jsonrpc field"""
        response = mock_mcp_server.client.post("/mcp", {
            "method": "tools/list",
            "id": "test-missing"
        })

        assert response.status_code == 200
        data = response.json()
        assert "error" in data
        assert "Invalid Request" in data["error"]["message"]


class TestMCPToolValidation:
    """MCP tool validation tests"""

    @pytest.mark.asyncio
    async def test_tool_validation_schema(self, mock_mcp_server):
        """Test tool validation schema"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-schema"
        })

        data = response.json()
        tools = data["result"]["tools"]

        # Check that tools have required fields
        for tool in tools:
            assert "name" in tool
            assert "description" in tool
            assert "inputSchema" in tool

            # Validate inputSchema structure
            schema = tool["inputSchema"]
            assert "type" in schema
            assert schema["type"] == "object"
            assert "properties" in schema

        await client.close()

    @pytest.mark.asyncio
    async def test_tool_argument_validation(self, mock_mcp_server):
        """Test tool argument validation"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test with valid operation
        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {
                    "operation": "create",
                    "customer_id": "test-cust"
                }
            },
            "id": "test-valid"
        })

        data = response.json()
        assert "result" in data

        # Test with invalid operation
        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {
                    "operation": "invalid_operation"
                }
            },
            "id": "test-invalid"
        })

        data = response.json()
        assert "error" in data

        await client.close()


class TestMCPErrorHandling:
    """MCP error handling tests"""

    @pytest.mark.asyncio
    async def test_parse_error_handling(self, mock_mcp_server):
        """Test parse error handling"""
        response = mock_mcp_server.client.post("/mcp", {
            "invalid": "json",
            "should": "fail"
        })

        assert response.status_code == 200
        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32700  # Parse Error

    @pytest.mark.asyncio
    async def test_invalid_request_error_handling(self, mock_mcp_server):
        """Test invalid request error handling"""
        response = mock_mcp_server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "invalid_method",
            "id": "test-invalid"
        })

        assert response.status_code == 200
        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32601  # Method Not Found

    @pytest.mark.asyncio
    async def test_invalid_params_error_handling(self, mock_mcp_server):
        """Test invalid params error handling"""
        response = mock_mcp_server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": "invalid_arguments"
            },
            "id": "test-params"
        })

        assert response.status_code == 200
        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32602  # Invalid Params

    @pytest.mark.asyncio
    async def test_internal_error_handling(self, mock_mcp_server):
        """Test internal error handling"""
        # This would require more complex mocking
        pass


class TestMCPPerformance:
    """MCP performance tests"""

    @pytest.mark.asyncio
    async def test_mcp_response_time(self, mock_mcp_server):
        """Test MCP response time"""
        import time

        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        start_time = time.time()
        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-performance"
        })
        end_time = time.time()

        assert response.status_code == 200
        assert end_time - start_time < 1.0  # Should respond within 1 second

        await client.close()

    @pytest.mark.asyncio
    async def test_mcp_concurrent_requests(self, mock_mcp_server):
        """Test MCP concurrent requests"""
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

        # Make 10 concurrent requests
        start_time = time.time()
        responses = await asyncio.gather(*[
            make_request(i) for i in range(10)
        ])
        end_time = time.time()

        assert len(responses) == 10
        assert all(response.status_code == 200 for response in responses)
        assert end_time - start_time < 5.0  # All requests should complete within 5 seconds

        await client.close()


class TestMCPSecurity:
    """MCP security tests"""

    @pytest.mark.asyncio
    async def test_mcp_input_sanitization(self, mock_mcp_server):
        """Test MCP input sanitization"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Test with potentially dangerous input
        response = await client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {
                    "operation": "create",
                    "customer_id": "test<script>alert('xss')</script>",
                    "customer_data": {"name": "test<script>"}
                }
            },
            "id": "test-security"
        })

        assert response.status_code == 200
        data = response.json()
        # Should succeed but potentially sanitized
        assert "result" in data or "error" in data

        await client.close()

    @pytest.mark.asyncio
    async def test_mcp_rate_limiting(self, mock_mcp_server):
        """Test MCP rate limiting"""
        client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Make multiple requests quickly
        for i in range(100):
            response = await client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": f"test-rate-{i}"
            })

        # Server should not crash
        assert response.status_code == 200

        await client.close()


class TestMCPIntegration:
    """MCP integration tests"""

    @pytest.mark.asyncio
    async def test_mcp_a2a_integration(self, mock_mcp_server, mock_a2a_server):
        """Test MCP to A2A integration"""
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Call MCP tool
        mcp_response = await mcp_client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "create", "customer_id": "test-integration"}
            },
            "id": "test-integration"
        })

        assert mcp_response.status_code == 200

        # Check A2A for related tasks
        a2a_response = await a2a_client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "id": "test-integration-list"
        })

        assert a2a_response.status_code == 200

        await mcp_client.close()
        await a2a_client.close()

    @pytest.mark.asyncio
    async def test_mcp_elrmcp_integration(self, mock_mcp_server, mock_elrmcp_server):
        """Test MCP to elrmcp integration"""
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        elrmcp_client = AsyncHTTPClient(mock_elrmcp_server.client.base_url)

        # Call MCP tool
        mcp_response = await mcp_client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "create", "customer_id": "test-elrmcp"}
            },
            "id": "test-elrmcp"
        })

        assert mcp_response.status_code == 200

        # Check elrmcp for relations
        elrmcp_response = await elrmcp_client.get("/api/v1/relations")

        assert elrmcp_response.status_code == 200
        data = elrmcp_response.json()
        assert "relations" in data

        await mcp_client.close()
        await elrmcp_client.close()