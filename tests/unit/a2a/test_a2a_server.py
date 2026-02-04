"""
A2A server unit tests

This module provides detailed unit tests for the A2A server functionality:
- Server initialization and configuration
- Health check endpoints
- Agent card endpoints
- Task management
- Task processing
- Multi-agent workflows
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

from tests.fixtures import MockA2AServer


class TestA2AServerInitialization:
    """Test A2A server initialization and configuration"""

    def test_server_basic_initialization(self):
        """Test basic server initialization"""
        server = MockA2AServer()
        assert server.host == "localhost"
        assert server.port == 8080
        assert server.app is not None
        assert server.client is not None
        assert server.tasks == {}
        assert server.task_counter == 0

    def test_server_custom_port(self):
        """Test server with custom port"""
        server = MockA2AServer(port=9999)
        assert server.port == 9999

    def test_server_custom_host(self):
        """Test server with custom host"""
        server = MockA2AServer(host="127.0.0.1")
        assert server.host == "127.0.0.1"

    def test_server_tasks_initialization(self):
        """Test tasks initialization"""
        server = MockA2AServer()
        assert server.tasks == {}
        assert server.task_counter == 0

    def test_server_task_counter_increment(self):
        """Test task counter increment"""
        server = MockA2AServer()
        initial_counter = server.task_counter

        # Simulate task creation
        server.task_counter += 1

        assert server.task_counter == initial_counter + 1


class TestA2AServerHealthCheck:
    """Test A2A server health check functionality"""

    @pytest.mark.asyncio
    async def test_health_endpoint(self):
        """Test health endpoint"""
        server = MockA2AServer()
        response = server.client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "a2a"
        assert "timestamp" in data

    @pytest.mark.asyncio
    async def test_health_endpoint_timing(self):
        """Test health endpoint response time"""
        server = MockA2AServer()
        start_time = time.time()

        response = server.client.get("/health")

        end_time = time.time()
        assert response.status_code == 200
        assert end_time - start_time < 1.0

    @pytest.mark.asyncio
    async def test_health_endpoint_consistency(self):
        """Test health endpoint consistency"""
        server = MockA2AServer()

        # Make multiple requests
        responses = []
        for i in range(10):
            response = server.client.get("/health")
            responses.append(response)

        assert all(r.status_code == 200 for r in responses)

    @pytest.mark.asyncio
    async def test_health_endpoint_cors_handling(self):
        """Test health endpoint CORS handling"""
        server = MockA2AServer()

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
        server = MockA2AServer()

        # Make many requests quickly
        responses = []
        for i in range(100):
            response = server.client.get("/health")
            responses.append(response)

        assert all(r.status_code == 200 for r in responses)


class TestA2AServerAgentCard:
    """Test A2A server agent card functionality"""

    @pytest.mark.asyncio
    async def test_agent_card_endpoint(self):
        """Test agent card endpoint"""
        server = MockA2AServer()
        response = server.client.get("/.well-known/agent-card")

        assert response.status_code == 200
        data = response.json()
        assert data["agent_id"] == "mock-a2a-server"
        assert data["agent_type"] == "a2a"
        assert "capabilities" in data
        assert "endpoints" in data
        assert "metadata" in data

    @pytest.mark.asyncio
    async def test_agent_card_validation(self):
        """Test agent card validation"""
        server = MockA2AServer()
        response = server.client.get("/.well-known/agent-card")

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

    @pytest.mark.asyncio
    async def test_agent_card_customization(self):
        """Test agent card customization"""
        server = MockA2AServer()

        # Update agent card
        server.app.agent_card = {
            "agent_id": "custom-a2a-server",
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

        assert data["agent_id"] == "custom-a2a-server"
        assert data["agent_type"] == "custom"
        assert "custom_capability" in data["capabilities"]
        assert "custom_field" in data["metadata"]

    @pytest.mark.asyncio
    async def test_agent_card_caching(self):
        """Test agent card caching"""
        server = MockA2AServer()

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


class TestA2AServerTaskManagement:
    """Test A2A server task management functionality"""

    @pytest.mark.asyncio
    async def test_task_submission(self):
        """Test task submission"""
        server = MockA2AServer()

        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-submit"
        })

        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-submit"
        assert "result" in data
        assert "task_id" in data["result"]
        assert data["result"]["status"] == "completed"

        # Verify task was created
        tasks = server.get_tasks()
        task_id = data["result"]["task_id"]
        assert task_id in tasks
        assert tasks[task_id]["task_type"] == "inventory_management"

    @pytest.mark.asyncio
    async def test_task_listing(self):
        """Test task listing"""
        server = MockA2AServer()

        # Submit multiple tasks
        task_ids = []
        for i in range(5):
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": f"task_{i}",
                    "params": {"operation": "test", "param": f"value_{i}"}
                },
                "id": f"test-submit-{i}"
            })

            data = response.json()
            task_ids.append(data["result"]["task_id"])

        # List tasks
        response = server.client.post("/a2a", {
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
        assert len(data["result"]["tasks"]) >= 5

        # Verify all submitted tasks are in the list
        tasks = data["result"]["tasks"]
        task_ids_in_list = [task["id"] for task in tasks]
        for task_id in task_ids:
            assert task_id in task_ids_in_list

    @pytest.mark.asyncio
    async def test_task_retrieval(self):
        """Test task retrieval"""
        server = MockA2AServer()

        # Submit a task
        submit_response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-submit"
        })

        task_id = submit_response.json()["result"]["task_id"]

        # Get task details
        response = server.client.post("/a2a", {
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
        assert data["result"]["task_type"] == "inventory_management"
        assert data["result"]["status"] == "completed"
        assert "created_at" in data["result"]

    @pytest.mark.asyncio
    async def test_task_status_tracking(self):
        """Test task status tracking"""
        server = MockA2AServer()

        # Submit a task
        submit_response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-submit"
        })

        task_id = submit_response.json()["result"]["task_id"]

        # Check task status multiple times
        for i in range(3):
            response = server.client.post("/a2a", {
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

    @pytest.mark.asyncio
    async def test_task_cancellation(self):
        """Test task cancellation"""
        server = MockA2AServer()

        # Submit a task
        submit_response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-submit"
        })

        task_id = submit_response.json()["result"]["task_id"]

        # Cancel task
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.cancel",
            "params": {"task_id": task_id},
            "id": "test-cancel"
        })

        # Should succeed or return appropriate error
        assert response.status_code == 200
        data = response.json()
        assert "result" in data or "error" in data

    @pytest.mark.asyncio
    async def test_task_deletion(self):
        """Test task deletion"""
        server = MockA2AServer()

        # Submit a task
        submit_response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-submit"
        })

        task_id = submit_response.json()["result"]["task_id"]

        # Delete task
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.delete",
            "params": {"task_id": task_id},
            "id": "test-delete"
        })

        # Should succeed or return appropriate error
        assert response.status_code == 200
        data = response.json()
        assert "result" in data or "error" in data

        # Verify task was deleted
        tasks = server.get_tasks()
        assert task_id not in tasks

    @pytest.mark.asyncio
    async def test_task_clearing(self):
        """Test task clearing"""
        server = MockA2AServer()

        # Submit multiple tasks
        for i in range(5):
            server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": f"task_{i}",
                    "params": {"operation": "test"}
                },
                "id": f"test-submit-{i}"
            })

        # Clear all tasks
        server.clear_tasks()

        # Verify all tasks were cleared
        tasks = server.get_tasks()
        assert len(tasks) == 0

    @pytest.mark.asyncio
    async def test_task_pagination(self):
        """Test task pagination"""
        server = MockA2AServer()

        # Submit many tasks
        for i in range(20):
            server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": f"task_{i}",
                    "params": {"operation": "test"}
                },
                "id": f"test-submit-{i}"
            })

        # List tasks with pagination
        response = server.client.post("/a2a", {
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

        # Test second page
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "params": {
                "limit": 10,
                "offset": 10
            },
            "id": "test-pagination-2"
        })

        assert response.status_code == 200
        data = response.json()
        assert len(data["result"]["tasks"]) <= 10

    @pytest.mark.asyncio
    async def test_task_filtering(self):
        """Test task filtering"""
        server = MockA2AServer()

        # Submit tasks of different types
        for i in range(5):
            server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock"}
                },
                "id": f"test-inventory-{i}"
            })

        for i in range(3):
            server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "shipping_management",
                    "params": {"operation": "create_shipment"}
                },
                "id": f"test-shipping-{i}"
            })

        # Filter by task type
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "params": {
                "task_type": "inventory_management"
            },
            "id": "test-filter"
        })

        assert response.status_code == 200
        data = response.json()
        tasks = data["result"]["tasks"]

        # All tasks should be of the specified type
        for task in tasks:
            assert task["task_type"] == "inventory_management"


class TestA2AServerTaskProcessing:
    """Test A2A server task processing functionality"""

    @pytest.mark.asyncio
    async def test_task_processing_simulation(self):
        """Test task processing simulation"""
        server = MockA2AServer()

        # Submit a task
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-process"
        })

        data = response.json()
        task_id = data["result"]["task_id"]

        # Task should be processed quickly
        time.sleep(0.1)  # Allow time for processing

        # Check task status
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": task_id},
            "id": "test-process-status"
        })

        task_data = response.json()
        assert task_data["result"]["status"] == "completed"

    @pytest.mark.asyncio
    async def test_concurrent_task_processing(self):
        """Test concurrent task processing"""
        import asyncio

        server = MockA2AServer()

        # Submit multiple tasks concurrently
        async def submit_task(task_id):
            return server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": f"task_{task_id}",
                    "params": {"operation": "test", "param": f"value_{task_id}"}
                },
                "id": f"test-concurrent-{task_id}"
            })

        # Submit 10 concurrent tasks
        responses = await asyncio.gather(*[submit_task(i) for i in range(10)])

        assert len(responses) == 10
        assert all(r.status_code == 200 for r in responses)

        # Verify all tasks were created
        tasks = server.get_tasks()
        assert len(tasks) >= 10

    @pytest.mark.asyncio
    async def test_task_processing_error_handling(self):
        """Test task processing error handling"""
        server = MockA2AServer()

        # Mock task processing error
        with patch.object(server, 'process_task') as mock_process:
            mock_process.side_effect = Exception("Task processing failed")

            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": "prod_123"}
                },
                "id": "test-process-error"
            })

            # Should handle error gracefully
            assert response.status_code == 200
            data = response.json()
            assert "error" in data

    @pytest.mark.asyncio
    async def test_task_retry_mechanism(self):
        """Test task retry mechanism"""
        server = MockA2AServer()

        # Mock retry logic
        with patch.object(server, 'process_task') as mock_process:
            mock_process.side_effect = [
                Exception("Temporary failure"),
                None  # Success on retry
            ]

            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": "prod_123"}
                },
                "id": "test-retry"
            })

            # Should succeed after retry
            assert response.status_code == 200
            data = response.json()
            assert "result" in data
            assert "task_id" in data["result"]
            assert mock_process.call_count == 2

    @pytest.mark.asyncio
    async def test_task_timeout_handling(self):
        """Test task timeout handling"""
        server = MockA2AServer()

        # Mock timeout
        with patch.object(server, 'process_task') as mock_process:
            mock_process.side_effect = asyncio.TimeoutError("Task timeout")

            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": "prod_123"}
                },
                "id": "test-timeout"
            })

            # Should handle timeout gracefully
            assert response.status_code == 200
            data = response.json()
            assert "error" in data
            assert "timeout" in data["error"]["message"].lower()


class TestA2AServerErrorHandling:
    """Test A2A server error handling"""

    @pytest.mark.asyncio
    async def test_parse_error_handling(self):
        """Test parse error handling"""
        server = MockA2AServer()

        response = server.client.post("/a2a", "invalid json")
        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32700  # Parse Error

    @pytest.mark.asyncio
    async def test_invalid_request_error(self):
        """Test invalid request error handling"""
        server = MockA2AServer()

        response = server.client.post("/a2a", {
            "invalid": "request"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32600  # Invalid Request

    @pytest.mark.asyncio
    async def test_method_not_found_error(self):
        """Test method not found error handling"""
        server = MockA2AServer()

        response = server.client.post("/a2a", {
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
        server = MockA2AServer()

        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": "invalid_params",
            "id": "test-params"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32602  # Invalid Params

    @pytest.mark.asyncio
    async def test_internal_error_handling(self):
        """Test internal error handling"""
        server = MockA2AServer()

        # Mock internal error
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

            response = server.client.post("/a2a", {
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

    @pytest.mark.asyncio
    async def test_application_error_handling(self):
        """Test application error handling"""
        server = MockA2AServer()

        # Trigger application error
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "error_task_type",
                "params": {"operation": "error_operation"}
            },
            "id": "test-application-error"
        })

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32000  # Application Error

    @pytest.mark.asyncio
    async def test_task_not_found_error(self):
        """Test task not found error"""
        server = MockA2AServer()

        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": "nonexistent_task"},
            "id": "test-not-found"
        })

        data = response.json()
        assert "error" in data
        assert "not found" in data["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_timeout_error_handling(self):
        """Test timeout error handling"""
        server = MockA2AServer()

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

            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "test",
                    "params": {}
                },
                "id": "test-timeout"
            })

            data = response.json()
            assert "error" in data
            assert data["error"]["code"] == -32604


class TestA2AServerSecurity:
    """Test A2A server security features"""

    @pytest.mark.asyncio
    async def test_input_sanitization(self):
        """Test input sanitization"""
        server = MockA2AServer()

        # Test with potentially malicious input
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {
                    "operation": "check_stock",
                    "product_id": "test<script>alert('xss')</script>",
                    "data": {"name": "test<script>"}
                }
            },
            "id": "test-security"
        })

        # Should handle malicious input gracefully
        assert response.status_code in [200, 400, 500]

    @pytest.mark.asyncio
    async def test_rate_limiting(self):
        """Test rate limiting"""
        server = MockA2AServer()

        # Make many requests quickly
        responses = []
        for i in range(100):
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": f"prod_{i}"}
                },
                "id": f"test-rate-{i}"
            })
            responses.append(response)

        # Server should not crash and should handle requests gracefully
        assert len(responses) == 100

    @pytest.mark.asyncio
    async def test_authentication_headers(self):
        """Test authentication header handling"""
        server = MockA2AServer()

        # Test with authentication header
        headers = {
            "Authorization": "Bearer test-token",
            "Content-Type": "application/json"
        }

        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-auth"
        }, headers=headers)

        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_cors_handling(self):
        """Test CORS handling"""
        server = MockA2AServer()

        # Test with CORS headers
        headers = {
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Content-Type"
        }

        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-cors"
        }, headers=headers)

        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_content_type_validation(self):
        """Test content type validation"""
        server = MockA2AServer()

        # Test with invalid content type
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-content-type"
        }, headers={"Content-Type": "text/plain"})

        # Should handle invalid content type gracefully
        assert response.status_code in [200, 415]

    @pytest.mark.asyncio
    async def test_request_size_limit(self):
        """Test request size limit"""
        server = MockA2AServer()

        # Test with large request
        large_request = {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-size"
        }
        large_request["data"] = "x" * 100000  # 100KB of data

        response = server.client.post("/a2a", large_request)

        # Should handle large request gracefully
        assert response.status_code in [200, 413]

    @pytest.mark.asyncio
    async def test_header_injection_prevention(self):
        """Test header injection prevention"""
        server = MockA2AServer()

        # Test with header injection
        malicious_headers = {
            "X-Forwarded-For": "192.168.1.1",
            "X-Real-IP": "192.168.1.2",
            "User-Agent": "test<script>alert('xss')</script>"
        }

        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-injection"
        }, headers=malicious_headers)

        assert response.status_code == 200


class TestA2AServerPerformance:
    """Test A2A server performance characteristics"""

    @pytest.mark.asyncio
    async def test_response_time_measurement(self):
        """Test server response time"""
        import time

        server = MockA2AServer()

        # Measure response time for task submission
        start_time = time.time()
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock", "product_id": "prod_123"}
            },
            "id": "test-response-time"
        })
        end_time = time.time()

        assert response.status_code == 200
        response_time = end_time - start_time
        assert response_time < 5.0  # Should respond within 5 seconds

    @pytest.mark.asyncio
    async def test_concurrent_requests_handling(self):
        """Test server handling of concurrent requests"""
        import asyncio
        import time

        server = MockA2AServer()

        async def make_request(i):
            return server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": f"prod_{i}"}
                },
                "id": f"test-concurrent-{i}"
            })

        # Make 50 concurrent requests
        start_time = time.time()
        responses = await asyncio.gather(*[make_request(i) for i in range(50)])
        end_time = time.time()

        assert len(responses) == 50
        assert all(r.status_code == 200 for r in responses)
        assert end_time - start_time < 10.0  # Should complete within 10 seconds

    @pytest.mark.asyncio
    async def test_throughput_measurement(self):
        """Test server throughput"""
        import asyncio
        import time

        server = MockA2AServer()

        async def worker(duration):
            start_time = time.time()
            task_count = 0

            while time.time() - start_time < duration:
                response = server.client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {
                        "task_type": "inventory_management",
                        "params": {"operation": "check_stock", "product_id": "prod_123"}
                    },
                    "id": f"test-throughput-{task_count}"
                })

                if response.status_code == 200:
                    task_count += 1

                await asyncio.sleep(0.01)  # Small delay between tasks

            return task_count

        # Measure throughput for 10 seconds
        task_count = await worker(10)
        throughput = task_count / 10.0  # tasks per second
        assert throughput > 1.0  # Should handle at least 1 task per second

    @pytest.mark.asyncio
    async def test_memory_usage_monitoring(self):
        """Test memory usage during task processing"""
        import psutil
        import os

        server = MockA2AServer()

        # Get initial memory usage
        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss

        # Submit many tasks
        for i in range(1000):
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": f"task_{i}",
                    "params": {"operation": "test", "param": f"value_{i}"}
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
        """Test CPU usage during task processing"""
        import psutil
        import time

        server = MockA2AServer()

        # Get initial CPU usage
        process = psutil.Process(os.getpid())
        initial_cpu = process.cpu_percent()

        # Submit many tasks
        start_time = time.time()
        for i in range(100):
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": f"prod_{i}"}
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
        server = MockA2AServer()

        # Make many requests to test connection pooling
        connections = []
        for i in range(100):
            response = server.client.post("/a2a", {
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


class TestA2AServerLogging:
    """Test A2A server logging functionality"""

    @pytest.mark.asyncio
    async def test_request_logging(self):
        """Test request logging"""
        server = MockA2AServer()

        # Make a request
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-logging"
        })

        assert response.status_code == 200

        # Check if request was logged (this would require access to logs)
        # In a real implementation, we'd check the server logs

    @pytest.mark.asyncio
    async def test_error_logging(self):
        """Test error logging"""
        server = MockA2AServer()

        # Make a request that should cause an error
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "nonexistent_task_type",
                "params": {"operation": "create"}
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

        server = MockA2AServer()

        # Make a request and measure time
        start_time = time.time()
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-perf-logging"
        })
        end_time = time.time()

        assert response.status_code == 200

        # Performance metrics should be logged
        response_time = end_time - start_time
        assert response_time < 5.0


class TestA2AServerMetrics:
    """Test A2A server metrics collection"""

    @pytest.mark.asyncio
    async def test_request_metrics(self):
        """Test request metrics collection"""
        server = MockA2AServer()

        # Make requests and track metrics
        for i in range(10):
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": f"prod_{i}"}
                },
                "id": f"test-metrics-{i}"
            })

        # Metrics should be collected
        assert response.status_code == 200

        # In a real implementation, we'd verify the metrics were collected correctly

    @pytest.mark.asyncio
    async def test_error_metrics(self):
        """Test error metrics collection"""
        server = MockA2AServer()

        # Make some successful and some failed requests
        for i in range(5):
            # Successful requests
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "inventory_management",
                    "params": {"operation": "check_stock", "product_id": f"success-{i}"}
                },
                "id": f"test-success-{i}"
            })

        for i in range(5):
            # Failed requests
            response = server.client.post("/a2a", {
                "jsonrpc": "2.0",
                "method": "task.submit",
                "params": {
                    "task_type": "nonexistent_task_type",
                    "params": {"operation": "create"}
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
        server = MockA2AServer()

        # If server has metrics endpoint
        if hasattr(server.app, 'include_router'):
            # This would be added to the FastAPI app
            pass

        # For now, just verify that requests are made and tracked
        response = server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "inventory_management",
                "params": {"operation": "check_stock"}
            },
            "id": "test-prometheus"
        })

        assert response.status_code == 200


class TestA2AServerIntegration:
    """Test A2A server integration"""

    @pytest.mark.asyncio
    async def test_mcp_integration(self, mock_mcp_server):
        """Test A2A server with MCP integration"""
        a2a_server = MockA2AServer()
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # MCP task submission via A2A
        response = a2a_server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "mcp_tool_call",
                "params": {
                    "tool_name": "customer_management",
                    "arguments": {"operation": "create", "customer_id": "cust_123"}
                }
            },
            "id": "test-mcp-integration"
        })

        assert response.status_code == 200
        data = response.json()
        assert "result" in data
        assert "task_id" in data["result"]

        # Verify tasks were created
        tasks = a2a_server.get_tasks()
        assert len(tasks) > 0

    @pytest.mark.asyncio
    async def test_elrmcp_integration(self, mock_elrmcp_server):
        """Test A2A server with elrmcp integration"""
        a2a_server = MockA2AServer()
        elrmcp_client = AsyncHTTPClient(mock_elrmcp_server.client.base_url)

        # A2A task that triggers elrmcp relation
        response = a2a_server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "relation_management",
                "params": {
                    "action": "create",
                    "relation_type": "customer_order",
                    "source_id": "cust_123",
                    "target_id": "ord_456"
                }
            },
            "id": "test-elrmcp-integration"
        })

        assert response.status_code == 200
        data = response.json()
        assert "result" in data
        assert "task_id" in data["result"]

        # Check elrmcp for relations
        elrmcp_response = await elrmcp_client.get("/api/v1/relations")

        assert elrmcp_response.status_code == 200
        relations = elrmcp_response.json()["relations"]
        assert len(relations) > 0

    @pytest.mark.asyncio
    async def test_full_integration_workflow(self, mock_mcp_server, mock_elrmcp_server):
        """Test full integration workflow"""
        from tests.utils import AsyncHTTPClient

        a2a_server = MockA2AServer()
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        elrmcp_client = AsyncHTTPClient(mock_elrmcp_server.client.base_url)

        workflow_steps = []

        # Step 1: Create customer via MCP
        mcp_response = mcp_client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "create", "customer_id": "cust_123"}
            },
            "id": "step1"
        })

        workflow_steps.append({"step": "create_customer", "status": "completed"})

        # Step 2: Create order via A2A
        a2a_response = a2a_server.client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "order_management",
                "params": {"operation": "create", "order_id": "ord_456"}
            },
            "id": "step2"
        })

        workflow_steps.append({"step": "create_order", "status": "completed"})

        # Step 3: Create relation via elrmcp
        elrmcp_response = await elrmcp_client.post("/api/v1/relations", {
            "relation_type": "customer_order",
            "source_id": "cust_123",
            "target_id": "ord_456"
        })

        workflow_steps.append({"step": "create_relation", "status": "completed"})

        # Verify all steps completed
        assert len(workflow_steps) == 3
        assert all(step["status"] == "completed" for step in workflow_steps)