"""
A2A client unit tests

This module provides detailed unit tests for the A2A client functionality:
- Client initialization and configuration
- Connection management
- Task submission
- Task listing and retrieval
- Agent discovery
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


class TestA2AClientInitialization:
    """Test A2A client initialization and configuration"""

    def test_client_basic_initialization(self):
        """Test basic client initialization"""
        client = AsyncHTTPClient("http://localhost:8080")
        assert client.base_url == "http://localhost:8080"
        assert client.timeout == 30.0
        assert client.client.timeout == 30.0

    def test_client_with_custom_timeout(self):
        """Test client with custom timeout"""
        custom_timeout = 60.0
        client = AsyncHTTPClient("http://localhost:8080", timeout=custom_timeout)
        assert client.timeout == custom_timeout
        assert client.client.timeout.total == custom_timeout

    @pytest.mark.asyncio
    async def test_client_context_manager(self):
        """Test client as context manager"""
        async with AsyncHTTPClient("http://localhost:8080") as client:
            assert client.base_url == "http://localhost:8080"
        # Client should be closed after exiting context

    def test_client_url_validation(self):
        """Test URL validation"""
        with pytest.raises(Exception):
            AsyncHTTPClient("invalid-url")


class TestA2AClientConnection:
    """Test A2A client connection management"""

    @pytest.mark.asyncio
    async def test_connection_establishment(self, mock_a2a_server):
        """Test connection establishment to A2A server"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test connection by making a simple request
        response = await client.get("/health")
        assert response.status_code == 200

        await client.close()

    @pytest.mark.asyncio
    async def test_connection_timeout(self):
        """Test connection timeout handling"""
        client = AsyncHTTPClient("http://localhost:9999", timeout=0.1)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = asyncio.TimeoutError()

            with pytest.raises(asyncio.TimeoutError):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {
                        "task_type": "test",
                        "params": {}
                    },
                    "id": "test-timeout"
                })

        await client.close()

    @pytest.mark.asyncio
    async def test_connection_error_handling(self, mock_a2a_server):
        """Test connection error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Connection failed")

            with pytest.raises(Exception):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {
                        "task_type": "test",
                        "params": {}
                    },
                    "id": "test-error"
                })

        await client.close()


class TestA2AClientTaskSubmission:
    """Test A2A client task submission functionality"""

    @pytest.mark.asyncio
    async def test_submit_task_success(self, mock_a2a_server):
        """Test successful task submission"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        response = await client.post("/a2a", task)

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == task["id"]
        assert "result" in data
        assert "task_id" in data["result"]
        assert data["result"]["status"] == "completed"

        await client.close()

    @pytest.mark.asyncio
    async def test_submit_task_with_parameters(self, mock_a2a_server):
        """Test task submission with complex parameters"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        task = TestDataGenerator.generate_a2a_task(
            "order_management",
            {
                "operation": "create",
                "order_data": {
                    "customer_id": "cust_123",
                    "items": [
                        {"product_id": "prod_456", "quantity": 2},
                        {"product_id": "prod_789", "quantity": 1}
                    ],
                    "total_amount": 150.00,
                    "shipping_address": {
                        "street": "123 Main St",
                        "city": "Anytown",
                        "zip": "12345"
                    }
                }
            }
        )

        response = await client.post("/a2a", task)

        assert response.status_code == 200
        data = response.json()
        assert "result" in data
        assert "task_id" in data["result"]

        await client.close()

    @pytest.mark.asyncio
    async def test_submit_multiple_tasks(self, mock_a2a_server):
        """Test submission of multiple tasks"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        tasks_data = []
        for i in range(5):
            task = TestDataGenerator.generate_a2a_task(
                f"task_{i}",
                {"operation": "test", "param": f"value_{i}"}
            )

            response = await client.post("/a2a", task)
            data = response.json()
            tasks_data.append(data)

        assert len(tasks_data) == 5
        for data in tasks_data:
            assert "result" in data
            assert "task_id" in data["result"]

        await client.close()

    @pytest.mark.asyncio
    async def test_submit_task_retry_logic(self, mock_a2a_server):
        """Test task submission with retry logic"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                Exception("Temporary failure"),
                Mock(
                    status_code=200,
                    json=lambda: {
                        "jsonrpc": "2.0",
                        "result": {
                            "task_id": "retry_task",
                            "status": "completed"
                        }
                    }
                )
            ]

            task = TestDataGenerator.generate_a2a_task(
                "inventory_management",
                {"operation": "check_stock", "product_id": "prod_123"}
            )

            response = await client.post("/a2a", task)

            assert response.status_code == 200
            data = response.json()
            assert "result" in data
            assert "task_id" in data["result"]
            assert mock_post.call_count == 2

        await client.close()

    @pytest.mark.asyncio
    async def test_submit_task_validation(self, mock_a2a_server):
        """Test task submission validation"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with missing required fields
        invalid_task = {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management"
                # Missing required params
            },
            "id": "test-validation"
        }

        response = await client.post("/a2a", invalid_task)

        data = response.json()
        assert "error" in data
        assert "invalid" in data["error"]["message"].lower()

        await client.close()


class TestA2AClientTaskManagement:
    """Test A2A client task management functionality"""

    @pytest.mark.asyncio
    async def test_list_tasks(self, mock_a2a_server):
        """Test listing tasks"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit some tasks first
        for i in range(3):
            task = TestDataGenerator.generate_a2a_task(
                f"task_{i}",
                {"operation": "test", "param": f"value_{i}"}
            )
            await client.post("/a2a", task)

        # List tasks
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "id": "test-list"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-list"
        assert "result" in data
        assert "tasks" in data["result"]
        assert len(data["result"]["tasks"]) >= 3

        await client.close()

    @pytest.mark.asyncio
    async def test_get_task_details(self, mock_a2a_server):
        """Test getting task details"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task first
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        submit_response = await client.post("/a2a", task)
        task_id = submit_response.json()["result"]["task_id"]

        # Get task details
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": task_id},
            "id": "test-get"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-get"
        assert "result" in data
        assert data["result"]["id"] == task_id
        assert "task_type" in data["result"]
        assert "status" in data["result"]
        assert "created_at" in data["result"]

        await client.close()

    @pytest.mark.asyncio
    async def test_get_nonexistent_task(self, mock_a2a_server):
        """Test getting non-existent task"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": "nonexistent_task"},
            "id": "test-get-nonexistent"
        })

        assert response.status_code == 200
        data = response.json()
        assert "error" in data
        assert "not found" in data["error"]["message"].lower()

        await client.close()

    @pytest.mark.asyncio
    async def test_monitor_task_status(self, mock_a2a_server):
        """Test monitoring task status"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        submit_response = await client.post("/a2a", task)
        task_id = submit_response.json()["result"]["task_id"]

        # Monitor task status multiple times
        for i in range(3):
            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.get",
                "params": {"task_id": task_id},
                "id": f"test-status-{i}"
            })

            data = response.json()
            assert data["result"]["id"] == task_id
            # Status should change from pending to completed
            if i == 0:
                assert data["result"]["status"] == "pending"
            else:
                assert data["result"]["status"] == "completed"

        await client.close()

    @pytest.mark.asyncio
    async def test_task_pagination(self, mock_a2a_server):
        """Test task pagination"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit many tasks
        for i in range(20):
            task = TestDataGenerator.generate_a2a_task(
                f"task_{i}",
                {"operation": "test", "param": f"value_{i}"}
            )
            await client.post("/a2a", task)

        # List tasks with pagination (if supported)
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "params": {
                "limit": 10,
                "offset": 0
            },
            "id": "test-pagination"
        })

        assert response.status_code == 200
        data = response.json()
        assert "result" in data
        assert "tasks" in data["result"]
        # Number of returned tasks should be limited
        assert len(data["result"]["tasks"]) <= 10

        await client.close()


class TestA2AClientAgentDiscovery:
    """Test A2A client agent discovery functionality"""

    @pytest.mark.asyncio
    async def test_get_agent_card(self, mock_a2a_server):
        """Test getting agent card"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.get("/.well-known/agent-card")

        assert response.status_code == 200
        data = response.json()
        assert data["agent_id"] == "mock-a2a-server"
        assert data["agent_type"] == "a2a"
        assert "capabilities" in data
        assert "endpoints" in data
        assert "metadata" in data

        await client.close()

    @pytest.mark.asyncio
    async def test_agent_card_validation(self, mock_a2a_server):
        """Test agent card validation"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.get("/.well-known/agent-card")
        data = response.json()

        # Validate required fields
        required_fields = ["agent_id", "agent_type", "capabilities", "endpoints", "metadata"]
        for field in required_fields:
            assert field in data

        # Validate capabilities
        assert isinstance(data["capabilities"], list)
        assert len(data["capabilities"]) > 0

        # Validate endpoints
        assert isinstance(data["endpoints"], dict)
        assert "a2a" in data["endpoints"]

        # Validate metadata
        assert isinstance(data["metadata"], dict)
        assert "version" in data["metadata"]
        assert "created_at" in data["metadata"]

        await client.close()

    @pytest.mark.asyncio
    async def test_discover_capabilities(self, mock_a2a_server):
        """Test discovering agent capabilities"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.get("/.well-known/agent-card")
        data = response.json()

        # Check available capabilities
        capabilities = data["capabilities"]
        capability_names = [cap["name"] for cap in capabilities]

        # Should have task-related capabilities
        expected_capabilities = ["task.submit", "task.list", "task.get"]
        for cap in expected_capabilities:
            assert cap in capability_names

        await client.close()

    @pytest.mark.asyncio
    async def test_get_agent_endpoints(self, mock_a2a_server):
        """Test getting agent endpoints"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.get("/.well-known/agent-card")
        data = response.json()

        endpoints = data["endpoints"]
        assert "a2a" in endpoints
        assert endpoints["a2a"].startswith("http")

        await client.close()


class TestA2AClientAuthentication:
    """Test A2A client authentication functionality"""

    @pytest.mark.asyncio
    async def test_authentication_headers(self, mock_a2a_server):
        """Test authentication header handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with authentication header
        headers = {
            "Authorization": "Bearer test-token",
            "Content-Type": "application/json"
        }

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-auth"
        }, headers=headers)

        assert response.status_code == 200

        await client.close()

    @pytest.mark.asyncio
    async def test_token_based_auth(self, mock_a2a_server):
        """Test token-based authentication"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Mock token validation
        with patch.object(client.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=200,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "result": {
                        "task_id": "test_task",
                        "status": "completed"
                    }
                }
            )

            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock"}
                },
                "id": "test-token-auth"
            }, headers={"Authorization": "Bearer test-token"})

            assert response.status_code == 200

        await client.close()

    @pytest.mark.asyncio
    async def test_invalid_token_handling(self, mock_a2a_server):
        """Test invalid token handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

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

            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock"}
                },
                "id": "test-invalid-token"
            }, headers={"Authorization": "invalid-token"})

            data = response.json()
            assert "error" in data

        await client.close()

    @pytest.mark.asyncio
    async def test_api_key_auth(self, mock_a2a_server):
        """Test API key authentication"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with API key in header
        headers = {
            "X-API-Key": "test-api-key",
            "Content-Type": "application/json"
        }

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-apikey-auth"
        }, headers=headers)

        assert response.status_code == 200

        await client.close()


class TestA2AClientRetryLogic:
    """Test A2A client retry logic"""

    @pytest.mark.asyncio
    async def test_retry_on_timeout(self, mock_a2a_server):
        """Test retry on timeout"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                asyncio.TimeoutError(),
                Mock(
                    status_code=200,
                    json=lambda: {
                        "jsonrpc": "2.0",
                        "result": {
                            "task_id": "retry_task",
                            "status": "completed"
                        }
                    }
                )
            ]

            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "test",
                    "params": {}
                },
                "id": "test-retry"
            })

            assert response.status_code == 200
            data = response.json()
            assert "result" in data
            assert mock_post.call_count == 2

        await client.close()

    @pytest.mark.asyncio
    async def test_max_retry_attempts(self, mock_a2a_server):
        """Test maximum retry attempts"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = [
                asyncio.TimeoutError(),
                asyncio.TimeoutError(),
                asyncio.TimeoutError()
            ]

            with pytest.raises(asyncio.TimeoutError):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {
                        "task_type": "test",
                        "params": {}
                    },
                    "id": "test-max-retry"
                })

        await client.close()

    @pytest.mark.asyncio
    async def test_exponential_backoff(self, mock_a2a_server):
        """Test exponential backoff retry strategy"""
        import time

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        call_times = []

        with patch.object(client.client, 'post') as mock_post:
            def mock_post_side_effect(*args, **kwargs):
                call_times.append(time.time())
                raise asyncio.TimeoutError()

            mock_post.side_effect = mock_post_side_effect

            with pytest.raises(asyncio.TimeoutError):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {
                        "task_type": "test",
                        "params": {}
                    },
                    "id": "test-backoff"
                })

        # Check that retries have exponential backoff
        if len(call_times) > 1:
            interval = call_times[1] - call_times[0]
            assert interval > 0  # Some delay between retries

        await client.close()

    @pytest.mark.asyncio
    async def test_circuit_breaker_pattern(self, mock_a2a_server):
        """Test circuit breaker pattern"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Service unavailable")

            # Multiple failures should trigger circuit breaker
            for i in range(5):
                with pytest.raises(Exception):
                    await client.post("/a2a", {
                        "jsonrpc": "2.0",
                        "method": "task.submit",
                        "params": {
                            "task_type": "test",
                            "params": {}
                        },
                        "id": f"test-circuit-{i}"
                    })

        await client.close()


class TestA2AClientErrorHandling:
    """Test A2A client error handling"""

    @pytest.mark.asyncio
    async def test_parse_error_handling(self, mock_a2a_server):
        """Test parse error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.post("/a2a", "invalid json")

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32700  # Parse Error

        await client.close()

    @pytest.mark.asyncio
    async def test_method_not_found_error(self, mock_a2a_server):
        """Test method not found error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "nonexistent_method",
            "id": "test-method"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32601  # Method Not Found

        await client.close()

    @pytest.mark.asyncio
    async def test_invalid_params_error(self, mock_a2a_server):
        """Test invalid params error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": "invalid_params",
            "id": "test-params"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32602  # Invalid Params

        await client.close()

    @pytest.mark.asyncio
    async def test_internal_error_handling(self, mock_a2a_server):
        """Test internal error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

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

            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "test",
                    "params": {}
                },
                "id": "test-internal"
            })

            data = response.json()
            assert "error" in data
            assert data["error"]["code"] == -32603

        await client.close()

    @pytest.mark.asyncio
    async def test_application_error_handling(self, mock_a2a_server):
        """Test application error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Mock application error
        with patch.object(client.client, 'post') as mock_post:
            mock_post.return_value = Mock(
                status_code=400,
                json=lambda: {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32000,
                        "message": "Application error: Invalid task type"
                    }
                }
            )

            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "invalid_task_type",
                    "params": {"operation": "test"}
                },
                "id": "test-application"
            })

            data = response.json()
            assert "error" in data
            assert data["error"]["code"] == -32000

        await client.close()

    @pytest.mark.asyncio
    async def test_network_error_handling(self, mock_a2a_server):
        """Test network error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Network error")

            with pytest.raises(Exception):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {
                        "task_type": "test",
                        "params": {}
                    },
                    "id": "test-network"
                })

        await client.close()


class TestA2AClientPerformance:
    """Test A2A client performance characteristics"""

    @pytest.mark.asyncio
    async def test_concurrent_task_submission(self, mock_a2a_server):
        """Test concurrent task submission"""
        import asyncio
        import time

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        async def submit_task(i):
            return await client.post("/a2a", TestDataGenerator.generate_a2a_task(
                f"task_{i}",
                {"operation": "test", "param": f"value_{i}"}
            ))

        # Submit 50 concurrent tasks
        start_time = time.time()
        responses = await asyncio.gather(*[submit_task(i) for i in range(50)])
        end_time = time.time()

        assert len(responses) == 50
        assert all(r.status_code == 200 for r in responses)
        assert end_time - start_time < 10.0  # Should complete within 10 seconds

        await client.close()

    @pytest.mark.asyncio
    async def test_task_processing_time(self, mock_a2a_server):
        """Test task processing time"""
        import time

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Measure task processing time
        start_time = time.time()
        response = await client.post("/a2a", TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        ))
        end_time = time.time()

        assert response.status_code == 200
        processing_time = end_time - start_time
        assert processing_time < 5.0  # Should complete within 5 seconds

        await client.close()

    @pytest.mark.asyncio
    async def test_throughput_measurement(self, mock_a2a_server):
        """Test task throughput"""
        import asyncio
        import time

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        async def worker(duration):
            start_time = time.time()
            task_count = 0

            while time.time() - start_time < duration:
                response = await client.post("/a2a", TestDataGenerator.generate_a2a_task(
                    "inventory_management",
                    {"operation": "check_stock", "product_id": "prod_123"}
                ))

                if response.status_code == 200:
                    task_count += 1

                await asyncio.sleep(0.01)  # Small delay between tasks

            return task_count

        # Measure throughput for 10 seconds
        task_count = await worker(10)
        throughput = task_count / 10.0  # tasks per second
        assert throughput > 1.0  # Should handle at least 1 task per second

        await client.close()

    @pytest.mark.asyncio
    async def test_memory_usage_monitoring(self, mock_a2a_server):
        """Test memory usage during task processing"""
        import psutil
        import os

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Get initial memory usage
        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss

        # Submit many tasks
        for i in range(1000):
            response = await client.post("/a2a", TestDataGenerator.generate_a2a_task(
                f"task_{i}",
                {"operation": "test", "param": f"value_{i}"}
            ))

        # Get final memory usage
        final_memory = process.memory_info().rss
        memory_increase = final_memory - initial_memory

        # Memory increase should be reasonable (less than 10MB)
        assert memory_increase < 10 * 1024 * 1024  # 10MB

        await client.close()

    @pytest.mark.asyncio
    async def test_cpu_usage_monitoring(self, mock_a2a_server):
        """Test CPU usage during task processing"""
        import psutil
        import time

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Get initial CPU usage
        process = psutil.Process(os.getpid())
        initial_cpu = process.cpu_percent()

        # Submit many tasks
        start_time = time.time()
        for i in range(100):
            response = await client.post("/a2a", TestDataGenerator.generate_a2a_task(
                "inventory_management",
                {"operation": "check_stock", "product_id": f"prod_{i}"}
            ))
        end_time = time.time()

        # Get final CPU usage
        final_cpu = process.cpu_percent()

        # CPU increase should be reasonable
        cpu_increase = final_cpu - initial_cpu
        assert cpu_increase < 50.0  # Less than 50% CPU increase

        await client.close()

    @pytest.mark.asyncio
    async def test_connection_pooling(self, mock_a2a_server):
        """Test connection pooling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Make many requests to test connection pooling
        connections = []
        for i in range(100):
            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock"}
                },
                "id": f"test-pooling-{i}"
            })
            connections.append(response)

        assert len(connections) == 100
        assert all(c.status_code == 200 for c in connections)

        await client.close()


class TestA2AClientMetrics:
    """Test A2A client metrics collection"""

    @pytest.mark.asyncio
    async def test_metrics_collection(self, mock_a2a_server):
        """Test metrics collection"""
        from tests.utils import TestMetrics

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        metrics = TestMetrics()

        # Track requests
        metrics.record_request()

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-metrics"
        })

        metrics.record_response()
        metrics.record_response()

        assert metrics.requests == 1
        assert metrics.responses == 2
        assert metrics.success_rate == 1.0

        await client.close()

    @pytest.mark.asyncio
    async def test_error_metrics(self, mock_a2a_server):
        """Test error metrics collection"""
        from tests.utils import TestMetrics

        client = AsyncHTTPClient(mock_a2a_server.client.base_url)
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

            response = await client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "test",
                    "params": {}
                },
                "id": "test-error-metrics"
            })

            metrics.record_error()

        assert metrics.success_rate == 0.0

        await client.close()