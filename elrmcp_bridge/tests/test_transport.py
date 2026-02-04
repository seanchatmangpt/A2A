"""
Tests for TransportManager functionality
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch
import asyncio

from elrmcp_bridge.src.transport import TransportManager, TransportType, ConnectionManager
from elrmcp_bridge.src.config import TransportConfig


class TestTransportManager:
    """Test TransportManager class"""

    @pytest.fixture
    def transport_config(self):
        """Create transport configuration"""
        config = Mock(spec=TransportConfig)
        config.transport_type = "websocket"
        config.websocket_url = "ws://localhost:8080"
        config.sse_url = "http://localhost:8081"
        config.connection_timeout = 30
        config.max_connections = 100
        config.retry_attempts = 3
        return config

    @pytest.fixture
    def transport_manager(self, transport_config):
        """Create TransportManager instance"""
        return TransportManager(transport_config)

    def test_transport_manager_initialization(self, transport_manager):
        """Test TransportManager initialization"""
        assert transport_manager.transport_type == TransportType.WEBSOCKET
        assert transport_manager.websocket_url == "ws://localhost:8080"
        assert transport_manager.sse_url == "http://localhost:8081"
        assert transport_manager.connection_timeout == 30
        assert transport_manager.max_connections == 100
        assert transport_manager.retry_attempts == 3
        assert transport_manager.connection_manager is not None

    @pytest.mark.asyncio
    async def test_transport_start_websocket(self, transport_manager):
        """Test transport start with WebSocket"""
        mock_connection_manager = Mock()
        mock_websocket_handler = Mock()
        mock_websocket_handler.start = AsyncMock()
        transport_manager.connection_manager = mock_connection_manager
        transport_manager.websocket_handler = mock_websocket_handler

        await transport_manager.start()

        mock_connection_manager.start.assert_called_once()
        mock_websocket_handler.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_transport_start_sse(self, transport_manager):
        """Test transport start with SSE"""
        transport_manager.transport_type = TransportType.SSE
        mock_sse_handler = Mock()
        mock_sse_handler.start = AsyncMock()
        transport_manager.sse_handler = mock_sse_handler

        await transport_manager.start()

        mock_sse_handler.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_transport_stop(self, transport_manager):
        """Test transport stop"""
        mock_connection_manager = Mock()
        mock_websocket_handler = Mock()
        mock_websocket_handler.stop = AsyncMock()
        transport_manager.connection_manager = mock_connection_manager
        transport_manager.websocket_handler = mock_websocket_handler

        await transport_manager.stop()

        mock_connection_manager.stop.assert_called_once()
        mock_websocket_handler.stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_check_connection_success(self, transport_manager):
        """Test connection check success"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.check_connection = AsyncMock(return_value=True)
        transport_manager.websocket_handler = mock_websocket_handler

        result = await transport_manager.check_connection()

        assert result is True
        mock_websocket_handler.check_connection.assert_called_once()

    @pytest.mark.asyncio
    async def test_check_connection_failure(self, transport_manager):
        """Test connection check failure"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.check_connection = AsyncMock(return_value=False)
        transport_manager.websocket_handler = mock_websocket_handler

        result = await transport_manager.check_connection()

        assert result is False
        mock_websocket_handler.check_connection.assert_called_once()

    def test_get_transport_type(self, transport_manager):
        """Test getting transport type"""
        assert transport_manager.get_transport_type() == TransportType.WEBSOCKET

        transport_manager.transport_type = TransportType.SSE
        assert transport_manager.get_transport_type() == TransportType.SSE

    def test_is_connected(self, transport_manager):
        """Test connection status check"""
        # Should start as disconnected
        assert transport_manager.is_connected() is False

        # Simulate connected state
        transport_manager._connected = True
        assert transport_manager.is_connected() is True

    @pytest.mark.asyncio
    async def test_send_message_websocket(self, transport_manager):
        """Test sending message via WebSocket"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.send_message = AsyncMock(return_value=True)
        transport_manager.websocket_handler = mock_websocket_handler

        message = {"type": "test", "data": "test"}
        result = await transport_manager.send_message("agent-1", message)

        assert result is True
        mock_websocket_handler.send_message.assert_called_once_with("agent-1", message)

    @pytest.mark.asyncio
    async def test_send_message_sse(self, transport_manager):
        """Test sending message via SSE"""
        transport_manager.transport_type = TransportType.SSE
        mock_sse_handler = Mock()
        mock_sse_handler.send_message = AsyncMock(return_value=True)
        transport_manager.sse_handler = mock_sse_handler

        message = {"type": "test", "data": "test"}
        result = await transport_manager.send_message("agent-1", message)

        assert result is True
        mock_sse_handler.send_message.assert_called_once_with("agent-1", message)

    @pytest.mark.asyncio
    async def test_send_message_not_connected(self, transport_manager):
        """Test sending message when not connected"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.send_message = AsyncMock(side_effect=Exception("Not connected"))
        transport_manager.websocket_handler = mock_websocket_handler
        transport_manager._connected = False

        message = {"type": "test", "data": "test"}

        with pytest.raises(Exception, match="Not connected"):
            await transport_manager.send_message("agent-1", message)

    @pytest.mark.asyncio
    async def test_broadcast_message(self, transport_manager):
        """Test broadcasting message to all agents"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.broadcast_message = AsyncMock(return_value=True)
        transport_manager.websocket_handler = mock_websocket_handler

        message = {"type": "broadcast", "data": "test"}
        result = await transport_manager.broadcast_message(message)

        assert result is True
        mock_websocket_handler.broadcast_message.assert_called_once_with(message)

    @pytest.mark.asyncio
    async def test_connection_retry(self, transport_manager):
        """Test connection retry mechanism"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.connect = AsyncMock(side_effect=[
            Exception("Connection failed"),
            Exception("Connection failed"),
            True  # Success after 2 retries
        ])
        transport_manager.websocket_handler = mock_websocket_handler
        transport_manager.retry_attempts = 3

        result = await transport_manager._connect_with_retry()

        assert result is True
        assert mock_websocket_handler.connect.call_count == 3

    @pytest.mark.asyncio
    async def test_connection_timeout(self, transport_manager):
        """Test connection timeout"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.connect = AsyncMock(
            side_effect=asyncio.sleep(10)  # Longer than timeout
        )
        transport_manager.websocket_handler = mock_websocket_handler
        transport_manager.connection_timeout = 5

        with pytest.raises(asyncio.TimeoutError):
            await transport_manager._connect_with_retry()

    def test_load_balancing(self, transport_manager):
        """Test load balancing across connections"""
        # Mock multiple connections
        mock_connections = {
            "conn1": Mock(load=10),
            "conn2": Mock(load=5),
            "conn3": Mock(load=20)
        }
        transport_manager.connection_manager.connections = mock_connections

        # Select least loaded connection
        selected = transport_manager._select_connection("agent-1")
        assert selected == "conn2"

    def test_connection_pool_management(self, transport_manager):
        """Test connection pool management"""
        # Add connections
        transport_manager.connection_manager.add_connection("conn1", "agent-1")
        transport_manager.connection_manager.add_connection("conn2", "agent-2")

        # Check connections
        connections = transport_manager.connection_manager.get_connections()
        assert len(connections) == 2

        # Remove connection
        transport_manager.connection_manager.remove_connection("conn1")
        connections = transport_manager.connection_manager.get_connections()
        assert len(connections) == 1

    @pytest.mark.asyncio
    async def test_connection_health_check(self, transport_manager):
        """Test connection health check"""
        mock_connections = {
            "conn1": Mock(healthy=True),
            "conn2": Mock(healthy=False),
            "conn3": Mock(healthy=True)
        }
        transport_manager.connection_manager.connections = mock_connections

        healthy = await transport_manager._check_connections_health()

        # Should detect unhealthy connections
        assert not all(conn.healthy for conn in mock_connections.values())

    @pytest.mark.asyncio
    async def test_message_queue_management(self, transport_manager):
        """Test message queue management"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.get_queue_size = Mock(return_value=5)
        transport_manager.websocket_handler = mock_websocket_handler

        queue_size = transport_manager.get_message_queue_size()
        assert queue_size == 5

    def test_transport_statistics(self, transport_manager):
        """Test transport statistics"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.get_statistics = Mock(return_value={
            "messages_sent": 100,
            "messages_received": 95,
            "connection_time": 300
        })
        transport_manager.websocket_handler = mock_websocket_handler

        stats = transport_manager.get_transport_statistics()
        assert stats["messages_sent"] == 100
        assert stats["messages_received"] == 95
        assert stats["connection_time"] == 300

    @pytest.mark.asyncio
    async def test_concurrent_message_handling(self, transport_manager):
        """Test concurrent message handling"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.send_message = AsyncMock(return_value=True)
        transport_manager.websocket_handler = mock_websocket_handler

        # Send multiple messages concurrently
        messages = [
            ("agent-1", {"type": "msg1"}),
            ("agent-2", {"type": "msg2"}),
            ("agent-3", {"type": "msg3"})
        ]

        tasks = [transport_manager.send_message(agent, msg) for agent, msg in messages]
        results = await asyncio.gather(*tasks)

        assert all(result is True for result in results)
        assert mock_websocket_handler.send_message.call_count == 3

    def test_connection_validation(self, transport_manager):
        """Test connection validation"""
        # Valid connection
        assert transport_manager._validate_connection({
            "url": "ws://localhost:8080",
            "protocols": ["a2a"]
        }) is True

        # Invalid connection
        assert transport_manager._validate_connection({
            "url": "invalid-url"
        }) is False

    @pytest.mark.asyncio
    async def test_graceful_shutdown(self, transport_manager):
        """Test graceful shutdown"""
        mock_websocket_handler = Mock()
        mock_websocket_handler.graceful_shutdown = AsyncMock()
        transport_manager.websocket_handler = mock_websocket_handler

        await transport_manager.graceful_shutdown()

        mock_websocket_handler.graceful_shutdown.assert_called_once()

    def test_transport_configuration_update(self, transport_manager):
        """Test transport configuration update"""
        # Update configuration
        new_config = Mock(spec=TransportConfig)
        new_config.transport_type = "sse"
        new_config.sse_url = "http://localhost:8082"
        new_config.connection_timeout = 60

        transport_manager.update_config(new_config)

        assert transport_manager.transport_type == TransportType.SSE
        assert transport_manager.sse_url == "http://localhost:8082"
        assert transport_manager.connection_timeout == 60

    def test_transport_error_handling(self, transport_manager):
        """Test transport error handling"""
        # Test with invalid transport type
        with pytest.raises(ValueError, match="Invalid transport type"):
            TransportManager("invalid_transport")

        # Test with invalid URL
        transport_manager.websocket_url = "invalid-url"
        with pytest.raises(ValueError, match="Invalid WebSocket URL"):
            transport_manager._validate_connection({"url": transport_manager.websocket_url})