"""
Tests for A2ABridge core functionality
"""

import asyncio
import pytest
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime

from elrmcp_bridge.src.bridge import A2ABridge, BridgeState
from elrmcp_bridge.src.config import BridgeConfig


class TestA2ABridge:
    """Test A2ABridge main orchestrator class"""

    @pytest.fixture
    def mock_config(self):
        """Create mock bridge configuration"""
        config = Mock(spec=BridgeConfig)
        config.host = "localhost"
        config.port = 8001
        config.debug = True
        config.development = True
        config.transport_type = "websocket"
        config.api_enabled = True
        config.metrics_enabled = True
        config.discovery_interval = 60
        return config

    @pytest.fixture
    def mock_protocol(self):
        """Create mock protocol handler"""
        return Mock()

    @pytest.fixture
    def mock_transport(self):
        """Create mock transport manager"""
        transport = Mock()
        transport.start = AsyncMock()
        transport.stop = AsyncMock()
        return transport

    @pytest.fixture
    def mock_agent_manager(self):
        """Create mock agent manager"""
        agent_manager = Mock()
        agent_manager.start = AsyncMock()
        agent_manager.stop = AsyncMock()
        agent_manager.discover_agents = AsyncMock(return_value={"agents": []})
        return agent_manager

    @pytest.fixture
    def mock_workflow_orchestrator(self):
        """Create mock workflow orchestrator"""
        workflow_orchestrator = Mock()
        workflow_orchestrator.start = AsyncMock()
        workflow_orchestrator.stop = AsyncMock()
        return workflow_orchestrator

    @pytest.fixture
    def mock_api_server(self):
        """Create mock API server"""
        api_server = Mock()
        api_server.start = AsyncMock()
        api_server.stop = AsyncMock()
        return api_server

    @pytest.fixture
    def mock_metrics_collector(self):
        """Create mock metrics collector"""
        metrics_collector = Mock()
        metrics_collector.start = AsyncMock()
        metrics_collector.stop = AsyncMock()
        return metrics_collector

    @pytest.fixture
    def bridge(self, mock_config, mock_protocol, mock_transport,
               mock_agent_manager, mock_workflow_orchestrator,
               mock_api_server, mock_metrics_collector):
        """Create A2ABridge instance with mocked dependencies"""
        with patch('elrmcp_bridge.src.bridge.A2AProtocol', return_value=mock_protocol), \
             patch('elrmcp_bridge.src.bridge.TransportManager', return_value=mock_transport), \
             patch('elrmcp_bridge.src.bridge.AgentManager', return_value=mock_agent_manager), \
             patch('elrmcp_bridge.src.bridge.WorkflowOrchestrator', return_value=mock_workflow_orchestrator), \
             patch('elrmcp_bridge.src.bridge.APIServer', return_value=mock_api_server), \
             patch('elrmcp_bridge.src.bridge.MetricsCollector', return_value=mock_metrics_collector):

            bridge = A2ABridge(mock_config)
            return bridge

    @pytest.mark.asyncio
    async def test_bridge_initialization(self, bridge):
        """Test bridge initialization"""
        assert bridge.state == BridgeState.INITIALIZING
        assert bridge.config is not None
        assert bridge.protocol is not None
        assert bridge.transport is not None
        assert bridge.agent_manager is not None
        assert bridge.workflow_orchestrator is not None
        assert bridge.api_server is not None
        assert bridge.metrics_collector is not None

    @pytest.mark.asyncio
    async def test_bridge_start_success(self, bridge):
        """Test successful bridge start"""
        await bridge.start()

        assert bridge.state == BridgeState.RUNNING
        bridge.transport.start.assert_called_once()
        bridge.agent_manager.start.assert_called_once()
        bridge.workflow_orchestrator.start.assert_called_once()
        bridge.api_server.start.assert_called_once()
        bridge.metrics_collector.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_bridge_start_transport_failure(self, bridge):
        """Test bridge start when transport fails"""
        bridge.transport.start.side_effect = Exception("Transport failed")

        with pytest.raises(Exception, match="Transport failed"):
            await bridge.start()

        assert bridge.state == BridgeState.ERROR

    @pytest.mark.asyncio
    async def test_bridge_stop_success(self, bridge):
        """Test successful bridge stop"""
        bridge.state = BridgeState.RUNNING

        await bridge.stop()

        assert bridge.state == BridgeState.STOPPED
        bridge.transport.stop.assert_called_once()
        bridge.agent_manager.stop.assert_called_once()
        bridge.workflow_orchestrator.stop.assert_called_once()
        bridge.api_server.stop.assert_called_once()
        bridge.metrics_collector.stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_bridge_get_bridge_metrics(self, bridge):
        """Test getting bridge metrics"""
        mock_metrics = {
            "metrics": {
                "total_messages_processed": 10,
                "total_workflows_completed": 5,
                "total_agents_discovered": 3
            },
            "uptime": 30.5
        }
        bridge.metrics_collector.get_metrics = AsyncMock(return_value=mock_metrics)

        result = await bridge.get_bridge_metrics()

        assert result == mock_metrics
        bridge.metrics_collector.get_metrics.assert_called_once()

    @pytest.mark.asyncio
    async def test_bridge_get_agent_status(self, bridge):
        """Test getting agent status"""
        mock_status = {
            "agents": {
                "agent-1": {"status": "active", "last_seen": "2023-01-01T00:00:00Z"}
            }
        }
        bridge.agent_manager.get_agent_status = AsyncMock(return_value=mock_status)

        result = await bridge.get_agent_status()

        assert result == mock_status
        bridge.agent_manager.get_agent_status.assert_called_once()

    @pytest.mark.asyncio
    async def test_bridge_send_to_agent_success(self, bridge):
        """Test sending message to agent successfully"""
        mock_response = {"result": "success", "id": "msg-123"}
        bridge.protocol.translate_and_send = AsyncMock(return_value=mock_response)

        message = {"type": "test", "data": "test"}
        agent_id = "agent-1"

        result = await bridge.send_to_agent(agent_id, message)

        assert result == mock_response
        bridge.protocol.translate_and_send.assert_called_once_with(agent_id, message)

    @pytest.mark.asyncio
    async def test_bridge_send_to_agent_failure(self, bridge):
        """Test sending message to agent fails"""
        bridge.protocol.translate_and_send = AsyncMock(side_effect=Exception("Agent not found"))

        message = {"type": "test", "data": "test"}
        agent_id = "non-existent-agent"

        with pytest.raises(Exception, match="Agent not found"):
            await bridge.send_to_agent(agent_id, message)

    @pytest.mark.asyncio
    async def test_bridge_start_workflow_success(self, bridge):
        """Test starting workflow successfully"""
        workflow_config = {
            "workflow_id": "test-workflow",
            "tasks": []
        }
        mock_workflow_id = "workflow-123"
        bridge.workflow_orchestrator.start_workflow = AsyncMock(return_value=mock_workflow_id)

        result = await bridge.start_workflow(workflow_config)

        assert result == mock_workflow_id
        bridge.workflow_orchestrator.start_workflow.assert_called_once_with(workflow_config)

    @pytest.mark.asyncio
    async def test_bridge_start_workflow_invalid_config(self, bridge):
        """Test starting workflow with invalid config"""
        workflow_config = {}  # Invalid config

        with pytest.raises(ValueError, match="Invalid workflow configuration"):
            await bridge.start_workflow(workflow_config)

    @pytest.mark.asyncio
    async def test_bridge_get_workflow_status(self, bridge):
        """Test getting workflow status"""
        mock_status = {
            "status": "running",
            "tasks": {"task-1": {"status": "completed"}}
        }
        bridge.workflow_orchestrator.get_workflow_status = AsyncMock(return_value=mock_status)

        workflow_id = "workflow-123"

        result = await bridge.get_workflow_status(workflow_id)

        assert result == mock_status
        bridge.workflow_orchestrator.get_workflow_status.assert_called_once_with(workflow_id)

    @pytest.mark.asyncio
    async def test_bridge_cancel_workflow(self, bridge):
        """Test cancelling workflow"""
        bridge.workflow_orchestrator.cancel_workflow = AsyncMock(return_value=True)

        workflow_id = "workflow-123"

        result = await bridge.cancel_workflow(workflow_id)

        assert result is True
        bridge.workflow_orchestrator.cancel_workflow.assert_called_once_with(workflow_id)

    @pytest.mark.asyncio
    async def test_bridge_get_bridge_status(self, bridge):
        """Test getting bridge status"""
        mock_status = {
            "state": BridgeState.RUNNING.value,
            "uptime": 60.0,
            "metrics": {
                "total_messages_processed": 10,
                "total_workflows_completed": 5
            }
        }

        # Mock the metrics collector
        bridge.metrics_collector.get_metrics = AsyncMock(return_value={
            "total_messages_processed": 10,
            "total_workflows_completed": 5,
            "uptime": 60.0
        })

        result = await bridge.get_bridge_status()

        assert result["state"] == BridgeState.RUNNING.value
        assert result["uptime"] == 60.0
        assert result["metrics"]["total_messages_processed"] == 10
        assert result["metrics"]["total_workflows_completed"] == 5

    @pytest.mark.asyncio
    async def test_bridge_health_check(self, bridge):
        """Test bridge health check"""
        bridge.transport.check_connection = AsyncMock(return_value=True)

        result = await bridge.health_check()

        assert result == {"status": "healthy", "timestamp": result["timestamp"]}
        bridge.transport.check_connection.assert_called_once()

    @pytest.mark.asyncio
    async def test_bridge_health_check_failed(self, bridge):
        """Test bridge health check when unhealthy"""
        bridge.transport.check_connection = AsyncMock(return_value=False)

        result = await bridge.health_check()

        assert result["status"] == "unhealthy"
        assert "timestamp" in result
        bridge.transport.check_connection.assert_called_once()

    @pytest.mark.asyncio
    async def test_bridge_error_handling(self, bridge):
        """Test bridge error handling"""
        bridge.state = BridgeState.RUNNING

        # Simulate error in metrics collection
        bridge.metrics_collector.get_metrics = AsyncMock(side_effect=Exception("Metrics error"))

        result = await bridge.get_bridge_status()

        # Should still return basic status even if metrics fail
        assert result["state"] == BridgeState.RUNNING.value
        assert "metrics" in result  # Should be present but potentially empty or partial

    @pytest.mark.asyncio
    async def test_bridge_concurrent_operations(self, bridge):
        """Test handling concurrent operations"""
        bridge.state = BridgeState.RUNNING

        # Mock successful operations
        bridge.send_to_agent = AsyncMock(return_value={"result": "success"})
        bridge.start_workflow = AsyncMock(return_value="workflow-123")
        bridge.get_workflow_status = AsyncMock(return_value={"status": "running"})

        # Execute multiple operations concurrently
        tasks = [
            bridge.send_to_agent("agent-1", {"type": "test"}),
            bridge.start_workflow({"workflow_id": "test", "tasks": []}),
            bridge.get_workflow_status("workflow-123")
        ]

        results = await asyncio.gather(*tasks)

        assert len(results) == 3
        assert all(result["result"] == "success" or "status" in result for result in results)

    @pytest.mark.asyncio
    async def test_bridge_state_transition(self, bridge):
        """Test bridge state transitions"""
        # Test initialization state
        assert bridge.state == BridgeState.INITIALIZING

        # Start bridge
        await bridge.start()
        assert bridge.state == BridgeState.RUNNING

        # Stop bridge
        await bridge.stop()
        assert bridge.state == BridgeState.STOPPED

        # Try to start stopped bridge
        await bridge.start()
        assert bridge.state == BridgeState.RUNNING

    @pytest.mark.asyncio
    async def test_bridge_configuration_validation(self, bridge):
        """Test bridge configuration validation"""
        # Test with valid config
        assert bridge.config.host is not None
        assert bridge.config.port > 0
        assert bridge.config.port < 65536

        # Test invalid port configuration
        bridge.config.port = -1
        with pytest.raises(ValueError, match="Invalid port"):
            await bridge.start()

    @pytest.mark.asyncio
    async def test_bridge_graceful_shutdown(self, bridge):
        """Test graceful shutdown with active connections"""
        bridge.state = BridgeState.RUNNING

        # Mock components that need cleanup
        bridge.transport.stop = AsyncMock()
        bridge.agent_manager.stop = AsyncMock()
        bridge.workflow_orchestrator.stop = AsyncMock()
        bridge.api_server.stop = AsyncMock()
        bridge.metrics_collector.stop = AsyncMock()

        # Simulate some delay in shutdown
        bridge.transport.stop.side_effect = asyncio.sleep(0.1)

        await bridge.stop()

        # All components should be stopped
        assert bridge.transport.stop.called
        assert bridge.agent_manager.stop.called
        assert bridge.workflow_orchestrator.stop.called
        assert bridge.api_server.stop.called
        assert bridge.metrics_collector.stop.called