"""
Tests for AgentManager functionality
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime, timedelta

from elrmcp_bridge.src.agents import AgentManager, Agent, AgentStatus
from elrmcp_bridge.src.config import AgentConfig


class TestAgentManager:
    """Test AgentManager class"""

    @pytest.fixture
    def agent_config(self):
        """Create mock agent configuration"""
        return Mock(spec=AgentConfig)

    @pytest.fixture
    def sample_agent(self):
        """Create sample agent"""
        return Agent(
            agent_id="agent-1",
            name="Test Agent",
            version="1.0.0",
            capabilities=["file_operations", "data_processing"],
            endpoints={
                "a2a": "http://localhost:9090",
                "websocket": "ws://localhost:9090/ws"
            },
            metadata={"type": "test", "purpose": "testing"},
            status=AgentStatus.ACTIVE,
            last_seen=datetime.now()
        )

    @pytest.fixture
    def agent_manager(self, agent_config):
        """Create AgentManager instance"""
        with patch('elrmcp_bridge.src.agents.AgentDiscoveryService'), \
             patch('elrmcp_bridge.src.agents.AgentHealthMonitor'), \
             patch('elrmcp_bridge.src.agents.AgentMessageRouter'):

            return AgentManager(discovery_interval=60, agent_config=agent_config)

    def test_agent_manager_initialization(self, agent_manager):
        """Test AgentManager initialization"""
        assert agent_manager.discovery_interval == 60
        assert agent_manager.agents == {}
        assert agent_manager.discovery_service is not None
        assert agent_manager.health_monitor is not None
        assert agent_manager.message_router is not None

    @pytest.mark.asyncio
    async def test_register_agent_success(self, agent_manager, sample_agent):
        """Test successful agent registration"""
        agent_manager.register_agent(sample_agent)

        assert "agent-1" in agent_manager.agents
        assert agent_manager.agents["agent-1"].name == "Test Agent"
        assert agent_manager.agents["agent-1"].status == AgentStatus.ACTIVE

    @pytest.mark.asyncio
    async def test_register_agent_duplicate(self, agent_manager, sample_agent):
        """Test registering duplicate agent"""
        agent_manager.register_agent(sample_agent)

        # Modify the agent
        sample_agent.capabilities = ["new_capability"]

        # Register again - should update
        agent_manager.register_agent(sample_agent)

        assert agent_manager.agents["agent-1"].capabilities == ["new_capability"]

    def test_unregister_agent(self, agent_manager, sample_agent):
        """Test agent unregistration"""
        agent_manager.register_agent(sample_agent)
        agent_manager.unregister_agent("agent-1")

        assert "agent-1" not in agent_manager.agents

    def test_unregister_nonexistent_agent(self, agent_manager):
        """Test unregistering non-existent agent"""
        # Should not raise exception
        agent_manager.unregister_agent("non-existent-agent")

    def test_get_agent(self, agent_manager, sample_agent):
        """Test getting agent by ID"""
        agent_manager.register_agent(sample_agent)

        result = agent_manager.get_agent("agent-1")

        assert result is not None
        assert result.agent_id == "agent-1"
        assert result.name == "Test Agent"

    def test_get_nonexistent_agent(self, agent_manager):
        """Test getting non-existent agent"""
        result = agent_manager.get_agent("non-existent-agent")
        assert result is None

    def test_list_agents(self, agent_manager, sample_agent):
        """Test listing all agents"""
        agent_manager.register_agent(sample_agent)

        agents = agent_manager.list_agents()

        assert len(agents) == 1
        assert agents["agent-1"].name == "Test Agent"

    def test_list_agents_by_capability(self, agent_manager, sample_agent):
        """Test listing agents by capability"""
        agent_manager.register_agent(sample_agent)

        agents = agent_manager.list_agents_by_capability("file_operations")
        assert len(agents) == 1

        agents = agent_manager.list_agents_by_capability("nonexistent")
        assert len(agents) == 0

    def test_list_agents_by_status(self, agent_manager, sample_agent):
        """Test listing agents by status"""
        agent_manager.register_agent(sample_agent)

        agents = agent_manager.list_agents_by_status(AgentStatus.ACTIVE)
        assert len(agents) == 1

        agents = agent_manager.list_agents_by_status(AgentStatus.INACTIVE)
        assert len(agents) == 0

    def test_update_agent_status(self, agent_manager, sample_agent):
        """Test updating agent status"""
        agent_manager.register_agent(sample_agent)

        agent_manager.update_agent_status("agent-1", AgentStatus.INACTIVE)

        assert agent_manager.agents["agent-1"].status == AgentStatus.INACTIVE

    def test_update_agent_status_nonexistent(self, agent_manager):
        """Test updating status of non-existent agent"""
        # Should not raise exception
        agent_manager.update_agent_status("non-existent-agent", AgentStatus.INACTIVE)

    @pytest.mark.asyncio
    async def test_discover_agents(self, agent_manager, sample_agent):
        """Test agent discovery"""
        mock_discovery = AsyncMock()
        mock_discovery.return_value = [sample_agent]
        agent_manager.discovery_service.discover = mock_discovery

        agents = await agent_manager.discover_agents()

        assert len(agents) == 1
        assert agents[0].agent_id == "agent-1"

    @pytest.mark.asyncio
    async def test_start_health_monitoring(self, agent_manager):
        """Test starting health monitoring"""
        mock_monitor = AsyncMock()
        agent_manager.health_monitor.start_monitoring = mock_monitor

        await agent_manager.start_health_monitoring()

        mock_monitor.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_health_monitoring(self, agent_manager):
        """Test stopping health monitoring"""
        mock_monitor = AsyncMock()
        agent_manager.health_monitor.stop_monitoring = mock_monitor

        await agent_manager.stop_health_monitoring()

        mock_monitor.assert_called_once()

    @pytest.mark.asyncio
    async def test_send_message_to_agent(self, agent_manager, sample_agent):
        """Test sending message to agent"""
        agent_manager.register_agent(sample_agent)

        mock_message_router = AsyncMock()
        mock_response = {"result": "success", "id": "msg-123"}
        mock_message_router.return_value = mock_response
        agent_manager.message_router.send_message = mock_message_router

        message = {"type": "test", "data": "test"}
        response = await agent_manager.send_message_to_agent("agent-1", message)

        assert response == mock_response

    @pytest.mark.asyncio
    async def test_send_message_to_nonexistent_agent(self, agent_manager):
        """Test sending message to non-existent agent"""
        with pytest.raises(Exception, match="Agent not found"):
            await agent_manager.send_message_to_agent("non-existent-agent", {"type": "test"})

    @pytest.mark.asyncio
    async def test_send_message_to_inactive_agent(self, agent_manager, sample_agent):
        """Test sending message to inactive agent"""
        agent_manager.register_agent(sample_agent)
        agent_manager.update_agent_status("agent-1", AgentStatus.INACTIVE)

        with pytest.raises(Exception, match="Agent is inactive"):
            await agent_manager.send_message_to_agent("agent-1", {"type": "test"})

    def test_agent_status_transitions(self, agent_manager, sample_agent):
        """Test agent status transitions"""
        # Initial status
        assert sample_agent.status == AgentStatus.ACTIVE

        # Update to inactive
        agent_manager.register_agent(sample_agent)
        agent_manager.update_agent_status("agent-1", AgentStatus.INACTIVE)
        assert agent_manager.agents["agent-1"].status == AgentStatus.INACTIVE

        # Update back to active
        agent_manager.update_agent_status("agent-1", AgentStatus.ACTIVE)
        assert agent_manager.agents["agent-1"].status == AgentStatus.ACTIVE

    def test_agent_status_timeout(self, agent_manager, sample_agent):
        """Test agent status timeout"""
        # Set agent with old timestamp
        old_time = datetime.now() - timedelta(minutes=5)
        sample_agent.last_seen = old_time

        agent_manager.register_agent(sample_agent)
        agent_manager.update_agent_status("agent-1", AgentStatus.TIMEOUT)
        assert agent_manager.agents["agent-1"].status == AgentStatus.TIMEOUT

    def test_agent_health_check(self, agent_manager, sample_agent):
        """Test agent health check"""
        agent_manager.register_agent(sample_agent)

        # Test healthy agent
        healthy = agent_manager.check_agent_health("agent-1")
        assert healthy is True

        # Test inactive agent
        agent_manager.update_agent_status("agent-1", AgentStatus.INACTIVE)
        healthy = agent_manager.check_agent_health("agent-1")
        assert healthy is False

    def test_agent_capability_matching(self, agent_manager, sample_agent):
        """Test agent capability matching"""
        agent_manager.register_agent(sample_agent)

        # Test exact match
        agents = agent_manager.find_agents_with_capability("file_operations")
        assert len(agents) == 1

        # Test partial match
        agents = agent_manager.find_agents_with_capability("file")
        assert len(agents) == 1

        # Test no match
        agents = agent_manager.find_agents_with_capability("nonexistent")
        assert len(agents) == 0

    def test_agent_metadata_filtering(self, agent_manager, sample_agent):
        """Test agent metadata filtering"""
        agent_manager.register_agent(sample_agent)

        # Filter by metadata
        agents = agent_manager.find_agents_by_metadata("type", "test")
        assert len(agents) == 1

        agents = agent_manager.find_agents_by_metadata("purpose", "nonexistent")
        assert len(agents) == 0

    def test_agent_endpoint_validation(self, agent_manager, sample_agent):
        """Test agent endpoint validation"""
        agent_manager.register_agent(sample_agent)

        # Test valid endpoint
        endpoints = agent_manager.get_agent_endpoints("agent-1")
        assert "a2a" in endpoints
        assert "websocket" in endpoints

        # Test invalid endpoint
        endpoints = agent_manager.get_agent_endpoints("non-existent-agent")
        assert endpoints == {}

    @pytest.mark.asyncio
    async def test_agent_discovery_service_failure(self, agent_manager):
        """Test discovery service failure handling"""
        mock_discovery = AsyncMock(side_effect=Exception("Discovery failed"))
        agent_manager.discovery_service.discover = mock_discovery

        agents = await agent_manager.discover_agents()
        assert len(agents) == 0  # Should handle failure gracefully

    @pytest.mark.asyncio
    async def test_agent_message_timeout(self, agent_manager, sample_agent):
        """Test message timeout handling"""
        agent_manager.register_agent(sample_agent)

        mock_message_router = AsyncMock(side_effect=asyncio.TimeoutError("Message timeout"))
        agent_manager.message_router.send_message = mock_message_router

        message = {"type": "test", "data": "test"}

        with pytest.raises(asyncio.TimeoutError, match="Message timeout"):
            await agent_manager.send_message_to_agent("agent-1", message, timeout=1)

    def test_agent_statistics(self, agent_manager, sample_agent):
        """Test agent statistics"""
        agent_manager.register_agent(sample_agent)

        # Test with one active agent
        stats = agent_manager.get_agent_statistics()
        assert stats["total_agents"] == 1
        assert stats["active_agents"] == 1
        assert stats["inactive_agents"] == 0

        # Add inactive agent
        inactive_agent = Agent(
            agent_id="agent-2",
            name="Inactive Agent",
            version="1.0.0",
            capabilities=[],
            endpoints={},
            metadata={},
            status=AgentStatus.INACTIVE,
            last_seen=datetime.now()
        )
        agent_manager.register_agent(inactive_agent)

        stats = agent_manager.get_agent_statistics()
        assert stats["total_agents"] == 2
        assert stats["active_agents"] == 1
        assert stats["inactive_agents"] == 1

    @pytest.mark.asyncio
    async def test_agent_reconnection(self, agent_manager, sample_agent):
        """Test agent reconnection handling"""
        agent_manager.register_agent(sample_agent)

        # Simulate agent going offline
        agent_manager.update_agent_status("agent-1", AgentStatus.INACTIVE)

        # Mock successful reconnection
        mock_discovery = AsyncMock(return_value=[sample_agent])
        agent_manager.discovery_service.discover = mock_discovery

        # Try to reconnect
        await agent_manager.reconnect_agent("agent-1")

        # Agent should be active again
        assert agent_manager.agents["agent-1"].status == AgentStatus.ACTIVE

    def test_agent_serialization(self, agent_manager, sample_agent):
        """Test agent serialization/deserialization"""
        agent_manager.register_agent(sample_agent)

        # Serialize agent
        serialized = agent_manager.serialize_agent("agent-1")
        assert "agent_id" in serialized
        assert "name" in serialized
        assert "capabilities" in serialized

        # Deserialize agent
        deserialized = agent_manager.deserialize_agent(serialized)
        assert deserialized.agent_id == "agent-1"
        assert deserialized.name == "Test Agent"

    @pytest.mark.asyncio
    async def test_agent_batch_operations(self, agent_manager):
        """Test batch agent operations"""
        # Create multiple agents
        agents = []
        for i in range(3):
            agent = Agent(
                agent_id=f"agent-{i+1}",
                name=f"Agent {i+1}",
                version="1.0.0",
                capabilities=[f"capability_{i+1}"],
                endpoints={},
                metadata={},
                status=AgentStatus.ACTIVE,
                last_seen=datetime.now()
            )
            agents.append(agent)
            agent_manager.register_agent(agent)

        # Send messages to multiple agents
        mock_message_router = AsyncMock()
        mock_message_router.return_value = {"result": "success", "id": "msg-123"}
        agent_manager.message_router.send_message = mock_message_router

        messages = [{"type": "test", "data": f"test_{i}"} for i in range(3)]
        tasks = [agent_manager.send_message_to_agent(f"agent-{i+1}", messages[i]) for i in range(3)]
        results = await asyncio.gather(*tasks)

        assert len(results) == 3
        assert all(result["result"] == "success" for result in results)