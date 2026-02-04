"""
Integration tests for the complete elrmcp_bridge system
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
import json
import time

from elrmcp_bridge.src.bridge import A2ABridge, BridgeState
from elrmcp_bridge.src.config import BridgeConfig
from elrmcp_bridge.src.protocol import A2AProtocol, MCPMessage, A2AMessage
from elrmcp_bridge.src.agents import AgentManager, Agent, AgentStatus
from elrmcp_bridge.src.workflows import WorkflowOrchestrator, WorkflowDefinition, TaskDefinition
from elrmcp_bridge.src.transport import TransportManager, TransportType
from elrmcp_bridge.src.api.server import APIServer
from elrmcp_bridge.src.metrics import MetricsCollector


class TestIntegration:
    """Integration tests for the complete system"""

    @pytest.fixture
    def complete_config(self):
        """Create complete configuration for integration test"""
        config = BridgeConfig(
            host="localhost",
            port=8001,
            debug=True,
            development=True,
            security=None,  # Will use default
            transport=None,  # Will use default
            agent=None,     # Will use default
            workflow=None,   # Will use default
            metrics=None,    # Will use default
            logging=None     # Will use default
        )
        return config

    @pytest.fixture
    def integration_test_setup(self):
        """Setup integration test components"""
        return {
            "bridge": None,
            "agent_manager": None,
            "workflow_orchestrator": None,
            "transport_manager": None,
            "api_server": None,
            "metrics_collector": None
        }

    @pytest.mark.asyncio
    async def test_system_initialization(self, complete_config, integration_test_setup):
        """Test complete system initialization"""
        # Create bridge with all components
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Verify all components are initialized
        assert bridge.config is not None
        assert bridge.protocol is not None
        assert bridge.transport is not None
        assert bridge.agent_manager is not None
        assert bridge.workflow_orchestrator is not None
        assert bridge.api_server is not None
        assert bridge.metrics_collector is not None

        # Verify state
        assert bridge.state == BridgeState.INITIALIZING

    @pytest.mark.asyncio
    async def test_system_lifecycle(self, complete_config, integration_test_setup):
        """Test complete system lifecycle"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()
        assert bridge.state == BridgeState.RUNNING

        # Verify components are started
        assert integration_test_setup["bridge"].transport.start.called
        assert integration_test_setup["bridge"].agent_manager.start.called
        assert integration_test_setup["bridge"].workflow_orchestrator.start.called
        assert integration_test_setup["bridge"].api_server.start.called
        assert integration_test_setup["bridge"].metrics_collector.start.called

        # Stop system
        await bridge.stop()
        assert bridge.state == BridgeState.STOPPED

        # Verify components are stopped
        assert integration_test_setup["bridge"].transport.stop.called
        assert integration_test_setup["bridge"].agent_manager.stop.called
        assert integration_test_setup["bridge"].workflow_orchestrator.stop.called
        assert integration_test_setup["bridge"].api_server.stop.called
        assert integration_test_setup["bridge"].metrics_collector.stop.called

    @pytest.mark.asyncio
    async def test_agent_communication_flow(self, complete_config, integration_test_setup):
        """Test complete agent communication flow"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Create test agent
        test_agent = Agent(
            agent_id="test-agent",
            name="Test Agent",
            version="1.0.0",
            capabilities=["file_operations", "data_processing"],
            endpoints={"a2a": "http://localhost:9090"},
            metadata={"type": "test"},
            status=AgentStatus.ACTIVE,
            last_seen=asyncio.get_event_loop().time()
        )

        # Register agent
        integration_test_setup["bridge"].agent_manager.register_agent(test_agent)

        # Test message flow
        mcp_message = MCPMessage(
            id="msg-123",
            method="tools/call",
            params={"name": "file_read", "arguments": {"path": "/tmp/test.txt"}}
        )

        # Send message to agent
        response = await bridge.send_to_agent("test-agent", mcp_message)

        # Verify message was processed
        assert response is not None
        assert "result" in response

        # Test agent status
        agent_status = await bridge.get_agent_status()
        assert "test-agent" in agent_status["agents"]

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_workflow_execution_flow(self, complete_config, integration_test_setup):
        """Test complete workflow execution flow"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Create test workflow
        workflow = WorkflowDefinition(
            workflow_id="test-workflow",
            name="Test Workflow",
            description="Integration test workflow",
            tasks=[
                TaskDefinition(
                    task_id="task-1",
                    name="collect_data",
                    type="agent",
                    parameters={"source": "test"}
                ),
                TaskDefinition(
                    task_id="task-2",
                    name="process_data",
                    type="agent",
                    parameters={"input": "{{task-1.result}}"},
                    dependencies=["task-1"]
                )
            ]
        )

        # Start workflow
        workflow_id = await bridge.start_workflow(workflow.to_dict())
        assert workflow_id is not None

        # Monitor workflow
        for _ in range(10):  # Max 10 checks
            status = await bridge.get_workflow_status(workflow_id)
            if status["status"] in ["completed", "failed"]:
                break
            await asyncio.sleep(1)

        # Verify workflow completed
        final_status = await bridge.get_workflow_status(workflow_id)
        assert final_status["status"] in ["completed", "failed"]

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_api_integration(self, complete_config, integration_test_setup):
        """Test API integration"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Test API endpoints
        # Health check
        health = await bridge.health_check()
        assert health["status"] in ["healthy", "unhealthy"]

        # Bridge status
        status = await bridge.get_bridge_status()
        assert "state" in status
        assert "uptime" in status

        # System info
        sys_info = await bridge.system_info()
        assert "platform" in sys_info

        # Configuration
        config = await bridge.get_config()
        assert "bridge" in config

        # System logs
        logs = await bridge.system_logs()
        assert "logs" in logs

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_metrics_integration(self, complete_config, integration_test_setup):
        """Test metrics integration"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Test metrics collection
        metrics = await bridge.get_bridge_metrics()
        assert "metrics" in metrics
        assert "uptime" in metrics

        # Test specific metrics
        assert "total_messages_processed" in metrics["metrics"]
        assert "total_workflows_completed" in metrics["metrics"]
        assert "total_agents_discovered" in metrics["metrics"]

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_concurrent_operations(self, complete_config, integration_test_setup):
        """Test concurrent operations"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Create multiple test agents
        agents = []
        for i in range(3):
            agent = Agent(
                agent_id=f"agent-{i}",
                name=f"Test Agent {i}",
                version="1.0.0",
                capabilities=[f"capability-{i}"],
                endpoints={},
                metadata={},
                status=AgentStatus.ACTIVE,
                last_seen=asyncio.get_event_loop().time()
            )
            agents.append(agent)
            integration_test_setup["bridge"].agent_manager.register_agent(agent)

        # Send messages concurrently
        messages = []
        for i in range(3):
            message = MCPMessage(
                id=f"msg-{i}",
                method="tools/call",
                params={"name": "test", "arguments": {"iteration": i}}
            )
            messages.append((f"agent-{i}", message))

        # Execute concurrent operations
        tasks = [bridge.send_to_agent(agent_id, msg) for agent_id, msg in messages]
        responses = await asyncio.gather(*tasks)

        # Verify all responses
        assert len(responses) == 3
        for response in responses:
            assert "result" in response

        # Create and start multiple workflows concurrently
        workflow_tasks = []
        for i in range(2):
            workflow = WorkflowDefinition(
                workflow_id=f"workflow-{i}",
                name=f"Workflow {i}",
                description="Concurrent workflow",
                tasks=[
                    TaskDefinition(
                        task_id=f"task-{i}",
                        name="simple_task",
                        type="agent",
                        parameters={"iteration": i}
                    )
                ]
            )
            workflow_tasks.append(bridge.start_workflow(workflow.to_dict()))

        workflow_ids = await asyncio.gather(*workflow_tasks)
        assert len(workflow_ids) == 2

        # Monitor all workflows
        monitor_tasks = []
        for workflow_id in workflow_ids:
            monitor_tasks.append(bridge.get_workflow_status(workflow_id))

        status_results = await asyncio.gather(*monitor_tasks)
        assert len(status_results) == 2

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_error_handling_integration(self, complete_config, integration_test_setup):
        """Test error handling across the system"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Test invalid workflow
        with pytest.raises(Exception):
            await bridge.start_workflow({})

        # Test message to non-existent agent
        with pytest.raises(Exception):
            await bridge.send_to_agent("non-existent", {"type": "test"})

        # Test invalid workflow ID
        with pytest.raises(Exception):
            await bridge.get_workflow_status("non-existent")

        # Test cancel non-existent workflow
        result = await bridge.cancel_workflow("non-existent")
        assert result is False

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_system_recovery(self, complete_config, integration_test_setup):
        """Test system recovery mechanisms"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Create test agent
        test_agent = Agent(
            agent_id="recovery-agent",
            name="Recovery Test Agent",
            version="1.0.0",
            capabilities=["test"],
            endpoints={},
            metadata={},
            status=AgentStatus.ACTIVE,
            last_seen=asyncio.get_event_loop().time()
        )
        integration_test_setup["bridge"].agent_manager.register_agent(test_agent)

        # Simulate agent going offline
        integration_test_setup["bridge"].agent_manager.update_agent_status("recovery-agent", AgentStatus.INACTIVE)

        # Test agent reconnection
        integration_test_setup["bridge"].agent_manager.reconnect_agent("recovery-agent")

        # Agent should be active again
        agent_status = await bridge.get_agent_status()
        assert agent_status["agents"]["recovery-agent"]["status"] == AgentStatus.ACTIVE.value

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_performance_integration(self, complete_config, integration_test_setup):
        """Test system performance"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Test message processing performance
        start_time = time.time()
        message_count = 100

        for i in range(message_count):
            message = MCPMessage(
                id=f"msg-{i}",
                method="test",
                params={"iteration": i}
            )
            await bridge.send_to_agent("recovery-agent", message)

        end_time = time.time()
        processing_time = end_time - start_time

        # Calculate messages per second
        messages_per_second = message_count / processing_time
        print(f"Processing rate: {messages_per_second:.2f} messages/second")

        # Verify metrics were collected
        metrics = await bridge.get_bridge_metrics()
        assert metrics["metrics"]["total_messages_processed"] >= message_count

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_configuration_hot_reload(self, complete_config, integration_test_setup):
        """Test configuration hot reload"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Get original config
        original_config = await bridge.get_config()

        # Update configuration
        await bridge.update_config("debug", True)

        # Verify config was updated
        updated_config = await bridge.get_config()
        assert updated_config["bridge"]["debug"] is True

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_system_stress_test(self, complete_config, integration_test_setup):
        """Test system under stress conditions"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Create many agents
        agent_count = 10
        agents = []
        for i in range(agent_count):
            agent = Agent(
                agent_id=f"stress-agent-{i}",
                name=f"Stress Agent {i}",
                version="1.0.0",
                capabilities=["stress_test"],
                endpoints={},
                metadata={},
                status=AgentStatus.ACTIVE,
                last_seen=asyncio.get_event_loop().time()
            )
            agents.append(agent)
            integration_test_setup["bridge"].agent_manager.register_agent(agent)

        # Create many workflows
        workflow_count = 5
        workflows = []
        for i in range(workflow_count):
            workflow = WorkflowDefinition(
                workflow_id=f"stress-workflow-{i}",
                name=f"Stress Workflow {i}",
                description="Stress test workflow",
                tasks=[
                    TaskDefinition(
                        task_id=f"stress-task-{i}",
                        name="stress_task",
                        type="agent",
                        parameters={"iteration": i}
                    )
                ]
            )
            workflows.append(workflow)

        # Start all workflows
        workflow_ids = []
        for workflow in workflows:
            workflow_id = await bridge.start_workflow(workflow.to_dict())
            workflow_ids.append(workflow_id)

        # Monitor all workflows
        for workflow_id in workflow_ids:
            for _ in range(30):  # Max 30 checks
                status = await bridge.get_workflow_status(workflow_id)
                if status["status"] in ["completed", "failed"]:
                    break
                await asyncio.sleep(1)

        # Verify system stability
        final_metrics = await bridge.get_bridge_metrics()
        assert final_metrics["metrics"]["total_workflows_completed"] >= 0
        assert final_metrics["metrics"]["total_messages_processed"] >= 0

        # Stop system
        await bridge.stop()

    @pytest.mark.asyncio
    async def test_data_consistency(self, complete_config, integration_test_setup):
        """Test data consistency across components"""
        bridge = A2ABridge(complete_config)
        integration_test_setup["bridge"] = bridge

        # Start system
        await bridge.start()

        # Register agent
        test_agent = Agent(
            agent_id="consistency-agent",
            name="Consistency Test Agent",
            version="1.0.0",
            capabilities=["test"],
            endpoints={},
            metadata={},
            status=AgentStatus.ACTIVE,
            last_seen=asyncio.get_event_loop().time()
        )
        integration_test_setup["bridge"].agent_manager.register_agent(test_agent)

        # Start workflow
        workflow = WorkflowDefinition(
            workflow_id="consistency-workflow",
            name="Consistency Test Workflow",
            description="Data consistency test",
            tasks=[
                TaskDefinition(
                    task_id="consistency-task",
                    name="consistency_test",
                    type="agent",
                    parameters={"test": "consistency"}
                )
            ]
        )
        workflow_id = await bridge.start_workflow(workflow.to_dict())

        # Verify consistency across components
        agent_status = await bridge.get_agent_status()
        workflow_status = await bridge.get_workflow_status(workflow_id)
        metrics = await bridge.get_bridge_metrics()

        # Check that metrics reflect actual state
        assert len(agent_status["agents"]) == integration_test_setup["bridge"].agent_manager.agents
        assert workflow_status["workflow_id"] == workflow_id
        assert metrics["metrics"]["total_workflows_completed"] >= 0

        # Stop system
        await bridge.stop()