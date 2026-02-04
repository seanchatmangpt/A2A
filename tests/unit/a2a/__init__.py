"""
A2A agent unit tests for Craftplan MCP + A2A Integration

This module provides unit tests for A2A agent components:
- A2A protocol compliance
- Task management
- Agent discovery
- Multi-agent workflows
- Error handling
- Client functionality
- Server functionality
"""

import pytest
import json
import asyncio
from typing import Dict, Any, List, Optional
from unittest.mock import Mock, AsyncMock, patch

from tests.utils import AsyncHTTPClient, TestDataGenerator


class TestA2AProtocol:
    """A2A protocol compliance tests"""

    @pytest.mark.asyncio
    async def test_a2a_version_compliance(self, mock_a2a_server):
        """Test A2A version compliance"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test health check
        response = await client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "a2a"

    @pytest.mark.asyncio
    async def test_a2a_task_submission_format(self, mock_a2a_server):
        """Test A2A task submission format compliance"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test task submission
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

    @pytest.mark.asyncio
    async def test_a2a_task_listing_format(self, mock_a2a_server):
        """Test A2A task listing format compliance"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task first
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        await client.post("/a2a", task)

        # List tasks
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "id": "test-list"
        })

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-list"
        assert "result" in data
        assert "tasks" in data["result"]
        assert len(data["result"]["tasks"]) > 0

    @pytest.mark.asyncio
    async def test_a2a_task_retrieval_format(self, mock_a2a_server):
        """Test A2A task retrieval format compliance"""
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

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-get"
        assert "result" in data
        assert data["result"]["id"] == task_id

    @pytest.mark.asyncio
    async def test_a2a_agent_card_format(self, mock_a2a_server):
        """Test A2A agent card format compliance"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.get("/.well-known/agent-card")

        assert response.status_code == 200
        data = response.json()
        assert data["agent_id"] == "mock-a2a-server"
        assert data["agent_type"] == "a2a"
        assert "capabilities" in data
        assert "endpoints" in data
        assert "metadata" in data


class TestA2AAgentDiscovery:
    """A2A agent discovery tests"""

    @pytest.mark.asyncio
    async def test_agent_card_retrieval(self, mock_a2a_server):
        """Test agent card retrieval"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.get("/.well-known/agent-card")

        assert response.status_code == 200
        data = response.json()

        # Verify agent card structure
        assert "agent_id" in data
        assert "agent_type" in data
        assert "capabilities" in data
        assert "endpoints" in data
        assert "metadata" in data

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

        # Validate capabilities structure
        for capability in data["capabilities"]:
            assert "name" in capability
            assert "description" in capability

        # Validate endpoints
        assert isinstance(data["endpoints"], dict)
        assert "a2a" in data["endpoints"]

        # Validate metadata
        assert isinstance(data["metadata"], dict)
        assert "version" in data["metadata"]
        assert "created_at" in data["metadata"]

    @pytest.mark.asyncio
    async def test_agent_discovery_integration(self, mock_a2a_server, mock_mcp_server):
        """Test agent discovery integration"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Get MCP server agent card
        mcp_card = await mcp_client.get("/.well-known/agent-card")
        a2a_card = await a2a_client.get("/.well-known/agent-card")

        assert mcp_card.status_code == 200
        assert a2a_card.status_code == 200

        # Verify agents can discover each other
        mcp_data = mcp_card.json()
        a2a_data = a2a_card.json()

        assert "endpoints" in mcp_data
        assert "endpoints" in a2a_data
        assert mcp_data["agent_id"] != a2a_data["agent_id"]


class TestA2ATaskManagement:
    """A2A task management tests"""

    @pytest.mark.asyncio
    async def test_task_submission(self, mock_a2a_server):
        """Test task submission"""
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

        # Verify task was created
        tasks = mock_a2a_server.get_tasks()
        task_id = data["result"]["task_id"]
        assert task_id in tasks

    @pytest.mark.asyncio
    async def test_task_listing(self, mock_a2a_server):
        """Test task listing"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit multiple tasks
        tasks_data = []
        for i in range(5):
            task = TestDataGenerator.generate_a2a_task(
                f"task_{i}",
                {"operation": "test", "param": f"value_{i}"}
            )

            submit_response = await client.post("/a2a", task)
            tasks_data.append(submit_response.json())

        # List tasks
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.list",
            "id": "test-list"
        })

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-list"
        assert "result" in data
        assert "tasks" in data["result"]
        assert len(data["result"]["tasks"]) >= 5

    @pytest.mark.asyncio
    async def test_task_retrieval(self, mock_a2a_server):
        """Test task retrieval"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task
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

        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "test-get"
        assert "result" in data
        assert data["result"]["id"] == task_id
        assert data["result"]["task_type"] == "inventory_management"
        assert data["result"]["status"] in ["pending", "completed"]

    @pytest.mark.asyncio
    async def test_task_status_tracking(self, mock_a2a_server):
        """Test task status tracking"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        submit_response = await client.post("/a2a", task)
        task_id = submit_response.json()["result"]["task_id"]

        # Check task status multiple times
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

    @pytest.mark.asyncio
    async def test_task_cancellation(self, mock_a2a_server):
        """Test task cancellation"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        submit_response = await client.post("/a2a", task)
        task_id = submit_response.json()["result"]["task_id"]

        # Cancel task (if supported)
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.cancel",
            "params": {"task_id": task_id},
            "id": "test-cancel"
        })

        data = response.json()
        assert "result" in data or "error" in data

    @pytest.mark.asyncio
    async def test_task_deletion(self, mock_a2a_server):
        """Test task deletion"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit a task
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        submit_response = await client.post("/a2a", task)
        task_id = submit_response.json()["result"]["task_id"]

        # Delete task (if supported)
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.delete",
            "params": {"task_id": task_id},
            "id": "test-delete"
        })

        data = response.json()
        assert "result" in data or "error" in data

        # Verify task was deleted
        tasks = mock_a2a_server.get_tasks()
        assert task_id not in tasks


class TestA2AMultiAgentWorkflows:
    """A2A multi-agent workflow tests"""

    @pytest.mark.asyncio
    async def test_agent_to_agent_communication(self, mock_a2a_server, mock_mcp_server):
        """Test agent-to-agent communication"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # MCP agent submits task to A2A agent
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        response = await a2a_client.post("/a2a", task)

        data = response.json()
        assert "result" in data
        assert "task_id" in data["result"]

        # A2A agent processes the task
        task_id = data["result"]["task_id"]

        # Get task details
        response = await a2a_client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": task_id},
            "id": "test-get-task"
        })

        task_data = response.json()
        assert task_data["result"]["status"] == "completed"

    @pytest.mark.asyncio
    async def test_task_delegation(self, mock_a2a_server, mock_mcp_server):
        """Test task delegation between agents"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Get agent cards for both agents
        mcp_card = await mcp_client.get("/.well-known/agent-card")
        a2a_card = await a2a_client.get("/.well-known/agent-card")

        mcp_data = mcp_card.json()
        a2a_data = a2a_card.json()

        # Verify agents can find each other
        assert mcp_data["agent_id"] != a2a_data["agent_id"]

        # MCP agent delegates task to A2A agent
        task = TestDataGenerator.generate_a2a_task(
            "shipping_management",
            {"operation": "create_shipment", "order_id": "ord_123"}
        )

        response = await a2a_client.post("/a2a", task)

        data = response.json()
        assert "result" in data
        assert "task_id" in data["result"]

    @pytest.mark.asyncio
    async def test_multi_agent_coordination(self, mock_a2a_server, mock_mcp_server):
        """Test multi-agent coordination"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Simulate multi-agent workflow
        workflow_steps = []

        # Step 1: MCP creates customer
        mcp_task = TestDataGenerator.generate_mcp_tool_call(
            "customer_management",
            {"operation": "create", "customer_id": "cust_123", "customer_data": {"name": "Test Customer"}}
        )

        mcp_response = await mcp_client.post("/mcp", mcp_task)
        workflow_steps.append({"step": "create_customer", "status": "completed"})

        # Step 2: A2A processes order
        a2a_task = TestDataGenerator.generate_a2a_task(
            "order_management",
            {"operation": "create", "order_id": "ord_123", "customer_id": "cust_123"}
        )

        a2a_response = await a2a_client.post("/a2a", a2a_task)
        workflow_steps.append({"step": "create_order", "status": "completed"})

        # Step 3: A2A processes shipping
        shipping_task = TestDataGenerator.generate_a2a_task(
            "shipping_management",
            {"operation": "create_shipment", "order_id": "ord_123"}
        )

        shipping_response = await a2a_client.post("/a2a", shipping_task)
        workflow_steps.append({"step": "create_shipment", "status": "completed"})

        # Verify all steps completed successfully
        assert len(workflow_steps) == 3
        assert all(step["status"] == "completed" for step in workflow_steps)

    @pytest.mark.asyncio
    async def test_agent_discovery_and_registration(self, mock_a2a_server, mock_mcp_server):
        """Test agent discovery and registration"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Get agent cards
        mcp_card = await mcp_client.get("/.well-known/agent-card")
        a2a_card = await a2a_client.get("/.well-known/agent-card")

        mcp_data = mcp_card.json()
        a2a_data = a2a_card.json()

        # Verify agent discovery
        agents = {
            mcp_data["agent_id"]: mcp_data,
            a2a_data["agent_id"]: a2a_data
        }

        # Test that agents can find each other
        assert len(agents) == 2
        for agent_id, agent_data in agents.items():
            assert "agent_id" in agent_data
            assert "capabilities" in agent_data
            assert "endpoints" in agent_data

    @pytest.mark.asyncio
    async def test_orchestrator_pattern(self, mock_a2a_server, mock_mcp_server):
        """Test orchestrator pattern for complex workflows"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)

        # Simulate orchestrated workflow
        workflow_id = f"workflow_{int(time.time())}"
        workflow_steps = []

        # Step 1: Create order via MCP
        order_task = TestDataGenerator.generate_mcp_tool_call(
            "order_management",
            {"operation": "create", "order_id": workflow_id, "items": []}
        )

        mcp_response = await mcp_client.post("/mcp", order_task)
        workflow_steps.append({"step": "create_order", "status": "completed"})

        # Step 2: Process payment via A2A
        payment_task = TestDataGenerator.generate_a2a_task(
            "payment_management",
            {"operation": "process_payment", "order_id": workflow_id}
        )

        payment_response = await a2a_client.post("/a2a", payment_task)
        payment_task_id = payment_response.json()["result"]["task_id"]

        # Step 3: Check payment status
        payment_status_response = await a2a_client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": payment_task_id},
            "id": "payment-status"
        })

        payment_status = payment_status_response.json()["result"]["status"]
        workflow_steps.append({"step": "process_payment", "status": payment_status})

        # Step 4: Update inventory via MCP
        inventory_task = TestDataGenerator.generate_mcp_tool_call(
            "inventory_management",
            {"operation": "update", "order_id": workflow_id}
        )

        inventory_response = await mcp_client.post("/mcp", inventory_task)
        workflow_steps.append({"step": "update_inventory", "status": "completed"})

        # Verify workflow completion
        assert len(workflow_steps) == 4
        assert all(step["status"] in ["completed", "success"] for step in workflow_steps)


class TestA2AErrorHandling:
    """A2A error handling tests"""

    @pytest.mark.asyncio
    async def test_invalid_task_submission(self, mock_a2a_server):
        """Test invalid task submission"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with invalid task type
        task = {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "invalid_task_type",
                "params": {"operation": "test"}
            },
            "id": "test-invalid-task"
        }

        response = await client.post("/a2a", task)

        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == -32601  # Method Not Found

    @pytest.mark.asyncio
    async def test_missing_task_id(self, mock_a2a_server):
        """Test missing task ID in response"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Submit task and check for task ID
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {"operation": "check_stock", "product_id": "prod_123"}
        )

        response = await client.post("/a2a", task)

        data = response.json()
        assert "result" in data
        assert "task_id" in data["result"]

    @pytest.mark.asyncio
    async def test_task_not_found(self, mock_a2a_server):
        """Test task not found error"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Try to get non-existent task
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.get",
            "params": {"task_id": "nonexistent_task"},
            "id": "test-not-found"
        })

        data = response.json()
        assert "error" in data
        assert "not found" in data["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_invalid_jsonrpc(self, mock_a2a_server):
        """Test invalid JSON-RPC format"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with invalid JSON-RPC version
        response = await client.post("/a2a", {
            "jsonrpc": "1.0",
            "method": "task.submit",
            "params": {"task_type": "test", "params": {}},
            "id": "test-invalid-version"
        })

        data = response.json()
        assert "error" in data

    @pytest.mark.asyncio
    async def test_missing_method(self, mock_a2a_server):
        """Test missing method in request"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "params": {"task_type": "test", "params": {}},
            "id": "test-missing-method"
        })

        data = response.json()
        assert "error" in data
        assert "method" in data["error"]["message"]

    @pytest.mark.asyncio
    async def test_invalid_params(self, mock_a2a_server):
        """Test invalid parameters"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with missing required params
        response = await client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {"task_type": "test"},  # Missing required params
            "id": "test-invalid-params"
        })

        data = response.json()
        assert "error" in data
        assert "invalid" in data["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_timeout_handling(self, mock_a2a_server):
        """Test timeout handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Mock timeout scenario
        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = asyncio.TimeoutError()

            with pytest.raises(asyncio.TimeoutError):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {"task_type": "test", "params": {}},
                    "id": "test-timeout"
                })

    @pytest.mark.asyncio
    async def test_connection_error(self, mock_a2a_server):
        """Test connection error handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        with patch.object(client.client, 'post') as mock_post:
            mock_post.side_effect = Exception("Connection failed")

            with pytest.raises(Exception):
                await client.post("/a2a", {
                    "jsonrpc": "2.0",
                    "method": "task.submit",
                    "params": {"task_type": "test", "params": {}},
                    "id": "test-connection-error"
                })


class TestA2APerformance:
    """A2A performance tests"""

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

    @pytest.mark.asyncio
    async def test_memory_usage(self, mock_a2a_server):
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


class TestA2ASecurity:
    """A2A security tests"""

    @pytest.mark.asyncio
    async def test_input_sanitization(self, mock_a2a_server):
        """Test input sanitization"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with potentially malicious input
        task = TestDataGenerator.generate_a2a_task(
            "inventory_management",
            {
                "operation": "check_stock",
                "product_id": "test<script>alert('xss')</script>",
                "data": {"name": "test<script>"}
            }
        )

        response = await client.post("/a2a", task)

        # Should handle malicious input gracefully
        assert response.status_code in [200, 400, 500]

    @pytest.mark.asyncio
    async def test_rate_limiting(self, mock_a2a_server):
        """Test rate limiting"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Make many requests quickly
        responses = []
        for i in range(100):
            response = await client.post("/a2a", TestDataGenerator.generate_a2a_task(
                "inventory_management",
                {"operation": "check_stock", "product_id": f"prod_{i}"}
            ))
            responses.append(response)

        # Server should not crash and should handle requests gracefully
        assert len(responses) == 100

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

    @pytest.mark.asyncio
    async def test_cors_handling(self, mock_a2a_server):
        """Test CORS handling"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with CORS headers
        headers = {
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Content-Type"
        }

        response = await client.post("/a2a", {
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
    async def test_content_type_validation(self, mock_a2a_server):
        """Test content type validation"""
        client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # Test with invalid content type
        response = await client.post("/a2a", {
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


class TestA2AIntegration:
    """A2A integration tests"""

    @pytest.mark.asyncio
    async def test_mcp_a2a_integration(self, mock_mcp_server, mock_a2a_server):
        """Test MCP to A2A integration"""
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)

        # MCP tool call that triggers A2A task
        mcp_response = await mcp_client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "order_management",
                "arguments": {
                    "operation": "create",
                    "order_data": {
                        "customer_id": "cust_123",
                        "items": [{"product_id": "prod_456", "quantity": 2}]
                    }
                }
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
        tasks = a2a_response.json()["result"]["tasks"]
        assert len(tasks) > 0

    @pytest.mark.asyncio
    async def test_elrmcp_integration(self, mock_a2a_server, mock_elrmcp_server):
        """Test A2A to elrmcp integration"""
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        elrmcp_client = AsyncHTTPClient(mock_elrmcp_server.client.base_url)

        # A2A task that triggers elrmcp relation
        a2a_response = await a2a_client.post("/a2a", {
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

        assert a2a_response.status_code == 200

        # Check elrmcp for relations
        elrmcp_response = await elrmcp_client.get("/api/v1/relations")

        assert elrmcp_response.status_code == 200
        relations = elrmcp_response.json()["relations"]
        assert len(relations) > 0

    @pytest.mark.asyncio
    async def test_full_integration_workflow(self, mock_mcp_server, mock_a2a_server, mock_elrmcp_server):
        """Test full integration workflow"""
        mcp_client = AsyncHTTPClient(mock_mcp_server.client.base_url)
        a2a_client = AsyncHTTPClient(mock_a2a_server.client.base_url)
        elrmcp_client = AsyncHTTPClient(mock_elrmcp_server.client.base_url)

        workflow_steps = []

        # Step 1: Create customer via MCP
        mcp_response = await mcp_client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "customer_management",
                "arguments": {"operation": "create", "customer_id": "cust_123"}
            },
            "id": "step1"
        })

        workflow_steps.append({"step": "create_customer", "status": "completed"})

        # Step 2: Create order via MCP
        mcp_response = await mcp_client.post("/mcp", {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "order_management",
                "arguments": {"operation": "create", "order_id": "ord_456"}
            },
            "id": "step2"
        })

        workflow_steps.append({"step": "create_order", "status": "completed"})

        # Step 3: Process payment via A2A
        a2a_response = await a2a_client.post("/a2a", {
            "jsonrpc": "2.0",
            "method": "task.submit",
            "params": {
                "task_type": "payment_management",
                "params": {"operation": "process", "order_id": "ord_456"}
            },
            "id": "step3"
        })

        workflow_steps.append({"step": "process_payment", "status": "completed"})

        # Step 4: Create relation via elrmcp
        elrmcp_response = await elrmcp_client.post("/api/v1/relations", {
            "relation_type": "customer_order",
            "source_id": "cust_123",
            "target_id": "ord_456"
        })

        workflow_steps.append({"step": "create_relation", "status": "completed"})

        # Verify all steps completed
        assert len(workflow_steps) == 4
        assert all(step["status"] == "completed" for step in workflow_steps)