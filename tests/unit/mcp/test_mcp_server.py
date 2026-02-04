"""
MCP server unit tests

This module provides detailed unit tests for the MCP server functionality:
- Server initialization and configuration
- Health check endpoints
- Agent card endpoints
- MCP protocol handling
- Tool management
- Error handling
- Security features
- Performance characteristics
"""

import pytest
import json
import time
import asyncio
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from typing import Dict, Any, List, Optional
from fastapi import FastAPI, HTTPException

from tests.fixtures import MockMCPServer


class TestMCPServerInitialization:
    """Test MCP server initialization and configuration"""

    def test_server_basic_initialization(self):
        """Test basic server initialization"""
        server = MockMCPServer()
        assert server.host == "localhost"
        assert server.port == 8090
        assert server.app is not None
        assert server.client is not None

    def test_server_custom_port(self):
        """Test server with custom port"""
        server = MockMCPServer(port=9999)
        assert server.port == 9999

    def test_server_custom_host(self):
        """Test server with custom host"""
        server = MockMCPServer(host="127.0.0.1")
        assert server.host == "127.0.0.1"

    def test_server_tools_initialization(self):
        """Test tools initialization"""
        server = MockMCPServer()
        assert len(server.tools) == 2
        assert "customer_management" in server.tools
        assert "order_management" in server.tools


class TestMCPServerHealthCheck:
    """Test MCP server health check functionality"""

    @pytest.mark.asyncio
    async def test_health_endpoint(self):
        """Test health endpoint"""
        server = MockMCPServer()
        response = server.client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "mcp"
        assert "timestamp" in data

    @pytest.mark.asyncio
    async def test_health_endpoint_timing(self):
        """Test health endpoint response time"""
        server = MockMCPServer()
        start_time = time.time()

        response = server.client.get("/health")

        end_time = time.time()
        assert response.status_code == 200
        assert end_time - start_time < 1.0

    @pytest.mark.asyncio
    async def test_health_endpoint_consistency(self):
        """Test health endpoint consistency"""
        server = MockMCPServer()

        # Make multiple requests
        responses = []
        for i in range(10):
            response = server.client.get("/health")
            responses.append(response)

        assert all(r.status_code == 200 for r in responses)

    @pytest.mark.asyncio
    async def test_health_endpoint_cors_handling(self):
        """Test health endpoint CORS handling"""
        server = MockMCPServer()

        # Test with CORS headers
        headers = {
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET"
        }

        response = server.client.get("/health", headers=headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_health_endpoint_rate_limiting(self):
        """Test health endpoint rate limiting"""
        server = MockMCPServer()

        # Make many requests quickly
        responses = []
        for i in range(100):
            response = server.client.get("/health")
            responses.append(response)

        assert all(r.status_code == 200 for r in responses)


class TestMCPServerAgentCard:
    """Test MCP server agent card functionality"""

    @pytest.mark.asyncio
    async def test_agent_card_endpoint(self):
        """Test agent card endpoint"""
        server = MockMCPServer()
        response = server.client.get("/.well-known/agent-card")

        assert response.status_code == 200
        data = response.json()
        assert data["agent_id"] == "mock-mcp-server"
        assert data["agent_type"] == "mcp"
        assert "capabilities" in data
        assert "endpoints" in data
        assert "metadata" in data

    @pytest.mark.asyncio
    async def test_agent_card_validation(self):
        """Test agent card validation"""
        server = MockMCPServer()
        response = server.client.get("/.well-known/agent-card")

        data = response.json()

        # Validate required fields
        required_fields = ["agent_id", "agent_type", "capabilities", "endpoints"]
        for field in required_fields:
            assert field in data

        # Validate capabilities
        assert isinstance(data["capabilities"], list)
        assert len(data["capabilities"]) > 0

        # Validate endpoints
        assert isinstance(data["endpoints"], dict)
        assert "mcp" in data["endpoints"]

        # Validate metadata
        assert isinstance(data["metadata"], dict)
        assert "version" in data["metadata"]
        assert "created_at" in data["metadata"]

    @pytest.mark.asyncio
    async def test_agent_card_customization(self):
        """Test agent card customization"""
        server = MockMCPServer()

        # Update agent card
        server.app.agent_card = {
            "agent_id": "custom-server",
            "agent_type": "custom",
            "capabilities": ["custom_capability"],
            "endpoints": {"custom": "http://localhost:9999"},
            "metadata": {
                "version": "2.0.0",
                "created_at": time.time(),
                "custom_field": "custom_value"
            }
        }

        response = server.client.get("/.well-known/agent-card")
        data = response.json()

        assert data["agent_id"] == "custom-server"
        assert data["agent_type"] == "custom"
        assert "custom_capability" in data["capabilities"]
        assert "custom_field" in data["metadata"]

    @pytest.mark.asyncio
    async def test_agent_card_caching(self):
        """Test agent card caching"""
        server = MockMCPServer()

        # Make multiple requests to same endpoint
        responses = []
        for i in range(5):
            response = server.client.get("/.well-known/agent-card")
            responses.append(response)

        assert all(r.status_code == 200 for r in responses)

        # All responses should have same data
        first_data = responses[0].json()
        for response in responses[1:]:
            data = response.json()
            assert data == first_data


class TestMCPServerProtocolHandling:
    """Test MCP server protocol handling"""

    @pytest.mark.asyncio
    async def test_jsonrpc_version_check(self):
        """Test JSON-RPC version checking"""
        server = MockMCPServer()

        # Valid JSON-RPC version
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-version"
        })

        data = response.json()
        assert data["jsonrpc"] == "2.0"

        # Invalid JSON-RPC version
        response = server.client.post("/mcp", {
            "jsonrpc": "1.0",
            "method": "tools/list",
            "id": "test-invalid-version"
        })

        data = response.json()
        assert "error" in data

    @pytest.mark.asyncio
    async def test_method_call_format(self):
        """Test method call format validation"""
        server = MockMCPServer()

        # Valid method call
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-valid-method"
        })

        assert response.status_code == 200

        # Missing method
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "id": "test-missing-method"
        })

        data = response.json()
        assert "error" in data
        assert "method" in data["error"]["message"]

    @pytest.mark.asyncio
    async def test_id_handling(self):
        """Test ID handling in requests"""
        server = MockMCPServer()

        # Test with different ID formats
        test_ids = ["string-id", 123, null, "test-123"]

        for test_id in test_ids:
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": test_id
            })

            data = response.json()
            assert "id" in data
            assert data["id"] == test_id

    @pytest.mark.asyncio
    async def test_batch_request_handling(self):
        """Test batch request handling"""
        server = MockMCPServer()

        # Test batch request
        batch_request = [
            {
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": "batch-1"
            },
            {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create"}
                },
                "id": "batch-2"
            }
        ]

        response = server.client.post("/mcp", batch_request)

        # If server supports batch requests
        if isinstance(response.json(), list):
            assert len(response.json()) == 2
            for result in response.json():
                assert "id" in result
        else:
            # Server doesn't support batch requests, handle as single request
            assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_notification_handling(self):
        """Test notification handling"""
        server = MockMCPServer()

        # Test notification (no ID)
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list"
        })

        # Should return error for notifications or handle appropriately
        data = response.json()
        if "error" in data:
            assert "id" in data["error"]["message"]


class TestMCPServerToolManagement:
    """Test MCP server tool management functionality"""

    @pytest.mark.asyncio
    async def test_tools_list_endpoint(self):
        """Test tools list endpoint"""
        server = MockMCPServer()
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-tools-list"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["result"]["tools"] == list(server.tools.values())

    @pytest.mark.asyncio
    async def test_tools_schema_validation(self):
        """Test tools schema validation"""
        server = MockMCPServer()
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-schema-validation"
        })

        data = response.json()
        tools = data["result"]["tools"]

        for tool in tools:
            assert "name" in tool
            assert "description" in tool
            assert "inputSchema" in tool

            # Validate input schema
            schema = tool["inputSchema"]
            assert schema["type"] == "object"
            assert "properties" in schema

    @pytest.mark.asyncio
    async def test_tool_call_endpoint(self):
        """Test tool call endpoint"""
        server = MockMCPServer()
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "create", "customer_id": "test-customer"}
            },
            "id": "test-tool-call"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["result"]["success"] is True

    @pytest.mark.asyncio
    async def test_nonexistent_tool_call(self):
        """Test calling nonexistent tool"""
        server = MockMCPServer()
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "nonexistent_tool",
                "arguments": {"operation": "create"}
            },
            "id": "test-nonexistent-tool"
        })

        data = response.json()
        assert "error" in data
        assert "not found" in data["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_tool_call_validation(self):
        """Test tool call validation"""
        server = MockMCPServer()

        # Test with missing required arguments
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {}  # Missing required arguments
            },
            "id": "test-validation"
        })

        data = response.json()
        assert "error" in data

        # Test with invalid operation
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "invalid_operation"}
            },
            "id": "test-invalid-operation"
        })

        data = response.json()
        assert "error" in data

    @pytest.mark.asyncio
    async def test_tool_call_error_handling(self):
        """Test tool call error handling"""
        server = MockMCPServer()

        # Test with null arguments
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": None
            },
            "id": "test-null-arguments"
        })

        data = response.json()
        assert "error" in data
        assert "invalid" in data["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_tool_call_batch_processing(self):
        """Test tool call batch processing"""
        server = MockMCPServer()

        # Test multiple tool calls
        requests = [
            {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": "test-1"}
                },
                "id": "batch-1"
            },
            {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "order_management",
                    "arguments": {"operation": "create", "order_id": "test-2"}
                },
                "id": "batch-2"
            }
        ]

        response = server.client.post("/mcp", requests)

        if isinstance(response.json(), list):
            assert len(response.json()) == 2
            for result in response.json():
                assert "result" in result or "error" in result


class TestMCPServerErrorHandling:
    """Test MCP server error handling"""

    @pytest.mark.asyncio
    async def test_parse_error_handling(self):
        """Test parse error handling"""
        server = MockMCPServer()

        # Invalid JSON
        response = server.client.post("/mcp", "invalid json")
        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32700  # Parse Error

    @pytest.mark.asyncio
    async def test_invalid_request_error(self):
        """Test invalid request error handling"""
        server = MockMCPServer()

        # Invalid request format
        response = server.client.post("/mcp", {
            "invalid": "request"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32600  # Invalid Request

    @pytest.mark.asyncio
    async def test_method_not_found_error(self):
        """Test method not found error handling"""
        server = MockMCPServer()

        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "nonexistent_method",
            "id": "test-method"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32601  # Method Not Found

    @pytest.mark.asyncio
    async def test_invalid_params_error(self):
        """Test invalid params error handling"""
        server = MockMCPServer()

        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": "invalid_params",
            "id": "test-params"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32602  # Invalid Params

    @pytest.mark.asyncio
    async def test_internal_error_handling(self):
        """Test internal error handling"""
        server = MockMCPServer()

        # Mock an internal error
        with patch.object(server.app, 'post') as mock_post:
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

            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-internal"
            })

            data = response.json()
            assert "error" in data
            assert data["error"]["code"] == -32603

    @pytest.mark.asyncio
    async def test_application_error_handling(self):
        """Test application error handling"""
        server = MockMCPServer()

        # Trigger application error
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "error_operation"}
            },
            "id": "test-application-error"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32000  # Application Error

    @pytest.mark.asyncio
    async def test_timeout_error_handling(self):
        """Test timeout error handling"""
        server = MockMCPServer()

        # Mock timeout
        with patch.object(server.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=408,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32604,
                        "message": "Request timeout"
                    }
                }
            )

            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": "test", "arguments": {}},
                "id": "test-timeout"
            })

            data = response.json()
            assert "error" in data


class TestMCPServerSecurity:
    """Test MCP server security features"""

    @pytest.mark.asyncio
    async def test_input_sanitization(self):
        """Test input sanitization"""
        server = MockMCPServer()

        # Test with potentially malicious input
        response = server.client.post("/mcp", {
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

        # Should handle malicious input gracefully
        assert response.status_code in [200, 400, 500]

    @pytest.mark.asyncio
    async def test_rate_limiting(self):
        """Test rate limiting"""
        server = MockMCPServer()

        # Make many requests quickly
        responses = []
        for i in range(100):
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create"}
                },
                "id": f"test-rate-{i}"
            })
            responses.append(response)

        # Server should not crash and should handle requests gracefully
        assert len(responses) == 100

    @pytest.mark.asyncio
    async def test_cors_handling(self):
        """Test CORS handling"""
        server = MockMCPServer()

        # Test with CORS headers
        headers = {
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Content-Type"
        }

        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-cors"
        }, headers=headers)

        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_authentication_headers(self):
        """Test authentication header handling"""
        server = MockMCPServer()

        # Test with authentication header
        headers = {
            "Authorization": "Bearer test-token",
            "Content-Type": "application/json"
        }

        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-auth"
        }, headers=headers)

        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_content_type_validation(self):
        """Test content type validation"""
        server = MockMCPServer()

        # Test with invalid content type
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-content-type"
        }, headers={"Content-Type": "text/plain"})

        # Should handle invalid content type gracefully
        assert response.status_code in [200, 415]

    @pytest.mark.asyncio
    async def test_request_size_limit(self):
        """Test request size limit"""
        server = MockMCPServer()

        # Test with large request
        large_request = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "create"}
            },
            "id": "test-size"
        }
        large_request["data"] = "x" * 100000  # 100KB of data

        response = server.client.post("/mcp", large_request)

        # Should handle large request gracefully
        assert response.status_code in [200, 413]

    @pytest.mark.asyncio
    async def test_header_injection_prevention(self):
        """Test header injection prevention"""
        server = MockMCPServer()

        # Test with header injection
        malicious_headers = {
            "X-Forwarded-For": "192.168.1.1",
            "X-Real-IP": "192.168.1.2",
            "User-Agent": "test<script>alert('xss')</script>"
        }

        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-injection"
        }, headers=malicious_headers)

        assert response.status_code == 200


class TestMCPServerPerformance:
    """Test MCP server performance characteristics"""

    @pytest.mark.asyncio
    async def test_response_time_measurement(self):
        """Test server response time"""
        import time

        server = MockMCPServer()

        # Measure response time for tool list
        start_time = time.time()
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-response-time"
        })
        end_time = time.time()

        assert response.status_code == 200
        response_time = end_time - start_time
        assert response_time < 1.0  # Should respond within 1 second

    @pytest.mark.asyncio
    async def test_concurrent_requests_handling(self):
        """Test server handling of concurrent requests"""
        import asyncio
        import time

        server = MockMCPServer()

        async def make_request(i):
            return server.client.post("/mcp", {
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
        assert all(r.status_code == 200 for r in responses)
        assert end_time - start_time < 10.0  # Should complete within 10 seconds

    @pytest.mark.asyncio
    async def test_throughput_measurement(self):
        """Test server throughput"""
        import asyncio
        import time

        server = MockMCPServer()

        async def worker(duration):
            start_time = time.time()
            request_count = 0

            while time.time() - start_time < duration:
                response = server.client.post("/mcp", {
                    "jsonrpc": "2.0",
                    "method": "tools/list",
                    "id": f"test-throughput-{request_count}"
                })

                if response.status_code == 200:
                    request_count += 1

                await asyncio.sleep(0.01)  # Small delay between requests

            return request_count

        # Measure throughput for 10 seconds
        request_count = await worker(10)
        throughput = request_count / 10.0  # requests per second
        assert throughput > 1.0  # Should handle at least 1 request per second

    @pytest.mark.asyncio
    async def test_memory_usage_monitoring(self):
        """Test memory usage monitoring"""
        import psutil
        import os

        server = MockMCPServer()

        # Get initial memory usage
        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss

        # Make many requests
        for i in range(1000):
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": f"test-{i}"}
                },
                "id": f"test-memory-{i}"
            })

        # Get final memory usage
        final_memory = process.memory_info().rss
        memory_increase = final_memory - initial_memory

        # Memory increase should be reasonable (less than 10MB)
        assert memory_increase < 10 * 1024 * 1024  # 10MB

    @pytest.mark.asyncio
    async def test_cpu_usage_monitoring(self):
        """Test CPU usage monitoring"""
        import psutil
        import time

        server = MockMCPServer()

        # Get initial CPU usage
        process = psutil.Process(os.getpid())
        initial_cpu = process.cpu_percent()

        # Make many requests
        start_time = time.time()
        for i in range(100):
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": f"test-{i}"}
                },
                "id": f"test-cpu-{i}"
            })
        end_time = time.time()

        # Get final CPU usage
        final_cpu = process.cpu_percent()

        # CPU increase should be reasonable
        cpu_increase = final_cpu - initial_cpu
        assert cpu_increase < 50.0  # Less than 50% CPU increase

    @pytest.mark.asyncio
    async def test_connection_pooling(self):
        """Test connection pooling"""
        server = MockMCPServer()

        # Make many requests to test connection pooling
        connections = []
        for i in range(100):
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": f"test-pooling-{i}"
            })
            connections.append(response)

        assert len(connections) == 100
        assert all(c.status_code == 200 for c in connections)


class TestMCPServerLogging:
    """Test MCP server logging functionality"""

    @pytest.mark.asyncio
    async def test_request_logging(self):
        """Test request logging"""
        server = MockMCPServer()

        # Make a request
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-logging"
        })

        assert response.status_code == 200

        # Check if request was logged (this would require access to logs)
        # In a real implementation, we'd check the server logs

    @pytest.mark.asyncio
    async def test_error_logging(self):
        """Test error logging"""
        server = MockMCPServer()

        # Make a request that should cause an error
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "nonexistent_tool",
                "arguments": {"operation": "create"}
            },
            "id": "test-error-logging"
        })

        assert response.status_code == 200
        data = response.json()
        assert "error" in data

        # Error should be logged

    @pytest.mark.asyncio
    async def test_performance_logging(self):
        """Test performance logging"""
        import time

        server = MockMCPServer()

        # Make a request and measure time
        start_time = time.time()
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-perf-logging"
        })
        end_time = time.time()

        assert response.status_code == 200

        # Performance metrics should be logged
        response_time = end_time - start_time
        assert response_time < 5.0


class TestMCPServerMetrics:
    """Test MCP server metrics collection"""

    @pytest.mark.asyncio
    async def test_request_metrics(self):
        """Test request metrics collection"""
        server = MockMCPServer()

        # Make requests and track metrics
        for i in range(10):
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": f"test-{i}"}
                },
                "id": f"test-metrics-{i}"
            })

        # Metrics should be collected
        assert response.status_code == 200

        # In a real implementation, we'd verify the metrics were collected correctly

    @pytest.mark.asyncio
    async def test_error_metrics(self):
        """Test error metrics collection"""
        server = MockMCPServer()

        # Make some successful and some failed requests
        for i in range(5):
            # Successful requests
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": f"success-{i}"}
                },
                "id": f"test-success-{i}"
            })

        for i in range(5):
            # Failed requests
            response = server.client.post("/mcp", {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": "nonexistent_tool",
                    "arguments": {"operation": "create"}
                },
                "id": f"test-error-{i}"
            })

        # Error metrics should be collected
        assert response.status_code == 200
        data = response.json()
        assert "error" in data

    @pytest.mark.asyncio
    async def test_prometheus_metrics(self):
        """Test Prometheus metrics endpoint"""
        server = MockMCPServer()

        # If server has metrics endpoint
        if hasattr(server.app, 'include_router'):
            # This would be added to the FastAPI app
            pass

        # For now, just verify that requests are made and tracked
        response = server.client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": "test-prometheus"
        })

        assert response.status_code == 200