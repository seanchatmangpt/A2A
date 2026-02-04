"""
Tests for A2A protocol translation functionality
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch

from elrmcp_bridge.src.protocol import A2AProtocol, MCPMessage, A2AMessage


class TestA2AProtocol:
    """Test A2A protocol translation class"""

    @pytest.fixture
    def protocol(self):
        """Create A2A protocol instance"""
        return A2AProtocol()

    @pytest.fixture
    def sample_mcp_message(self):
        """Create sample MCP message"""
        return MCPMessage(
            id="msg-123",
            method="tools/call",
            params={
                "name": "file_read",
                "arguments": {"path": "/tmp/test.txt"}
            }
        )

    @pytest.fixture
    def sample_a2a_message(self):
        """Create sample A2A message"""
        return A2AMessage(
            id="msg-123",
            type="a2a_request",
            action="execute_tool",
            data={
                "tool_name": "file_read",
                "parameters": {"path": "/tmp/test.txt"}
            }
        )

    def test_mcp_to_a2a_translation(self, protocol, sample_mcp_message, sample_a2a_message):
        """Test MCP to A2A message translation"""
        with patch.object(protocol, '_map_mcp_method_to_a2a_action') as mock_map, \
             patch.object(protocol, '_convert_mcp_payload_to_a2a') as mock_convert:

            mock_map.return_value = "execute_tool"
            mock_convert.return_value = {
                "tool_name": "file_read",
                "parameters": {"path": "/tmp/test.txt"}
            }

            result = protocol.mcp_to_a2a(sample_mcp_message)

            assert result.id == sample_mcp_message.id
            assert result.type == "a2a_request"
            assert result.action == "execute_tool"
            assert result.data == {
                "tool_name": "file_read",
                "parameters": {"path": "/tmp/test.txt"}
            }

    def test_a2a_to_mcp_translation(self, protocol, sample_mcp_message, sample_a2a_message):
        """Test A2A to MCP message translation"""
        with patch.object(protocol, '_map_a2a_action_to_mcp_method') as mock_map, \
             patch.object(protocol, '_convert_a2a_payload_to_mcp') as mock_convert:

            mock_map.return_value = "tools/call"
            mock_convert.return_value = {
                "name": "file_read",
                "arguments": {"path": "/tmp/test.txt"}
            }

            result = protocol.a2a_to_mcp(sample_a2a_message)

            assert result.id == sample_a2a_message.id
            assert result.method == "tools/call"
            assert result.params == {
                "name": "file_read",
                "arguments": {"path": "/tmp/test.txt"}
            }

    @pytest.mark.asyncio
    async def test_translate_and_send(self, protocol):
        """Test translate and send functionality"""
        mock_agent_manager = AsyncMock()
        mock_a2a_message = A2AMessage(id="msg-123", type="a2a_request", action="test", data={})
        mock_response = {"result": "success", "id": "msg-123"}

        protocol.mcp_to_a2a = Mock(return_value=mock_a2a_message)
        mock_agent_manager.send_message = AsyncMock(return_value=mock_response)

        protocol._agent_manager = mock_agent_manager

        mcp_message = MCPMessage(id="msg-123", method="test", params={})
        result = await protocol.translate_and_send("agent-1", mcp_message)

        assert result == mock_response
        protocol.mcp_to_a2a.assert_called_once_with(mcp_message)
        mock_agent_manager.send_message.assert_called_once_with("agent-1", mock_a2a_message)

    def test_map_mcp_method_to_a2a_action(self, protocol):
        """Test MCP method to A2A action mapping"""
        test_cases = [
            ("tools/call", "execute_tool"),
            ("tools/create", "create_resource"),
            ("tools/list", "list_resources"),
            ("resources/read", "read_resource"),
            ("resources/write", "write_resource"),
            ("resources/list", "list_resources"),
            ("unknown/method", "unknown_action")
        ]

        for mcp_method, expected_action in test_cases:
            result = protocol._map_mcp_method_to_a2a_action(mcp_method)
            assert result == expected_action, f"Failed for {mcp_method}"

    def test_map_a2a_action_to_mcp_method(self, protocol):
        """Test A2A action to MCP method mapping"""
        test_cases = [
            ("execute_tool", "tools/call"),
            ("create_resource", "tools/create"),
            ("list_resources", "tools/list"),
            ("read_resource", "resources/read"),
            ("write_resource", "resources/write"),
            ("unknown_action", "unknown/method")
        ]

        for a2a_action, expected_method in test_cases:
            result = protocol._map_a2a_action_to_mcp_method(a2a_action)
            assert result == expected_method, f"Failed for {a2a_action}"

    def test_convert_mcp_payload_to_a2a(self, protocol):
        """Test MCP payload to A2A data conversion"""
        mcp_payload = {
            "name": "file_read",
            "arguments": {
                "path": "/tmp/test.txt",
                "encoding": "utf-8"
            }
        }

        result = protocol._convert_mcp_payload_to_a2a(mcp_payload)

        assert result["tool_name"] == "file_read"
        assert result["parameters"]["path"] == "/tmp/test.txt"
        assert result["parameters"]["encoding"] == "utf-8"

    def test_convert_a2a_payload_to_mcp(self, protocol):
        """Test A2A data to MCP payload conversion"""
        a2a_data = {
            "tool_name": "file_read",
            "parameters": {
                "path": "/tmp/test.txt",
                "encoding": "utf-8"
            }
        }

        result = protocol._convert_a2a_payload_to_mcp(a2a_data)

        assert result["name"] == "file_read"
        assert result["arguments"]["path"] == "/tmp/test.txt"
        assert result["arguments"]["encoding"] == "utf-8"

    def test_validate_mcp_message(self, protocol):
        """Test MCP message validation"""
        # Valid message
        valid_message = MCPMessage(id="msg-123", method="test", params={})
        assert protocol.validate_mcp_message(valid_message) is True

        # Invalid message - missing id
        invalid_message = MCPMessage(method="test", params={})
        assert protocol.validate_mcp_message(invalid_message) is False

        # Invalid message - missing method
        invalid_message = MCPMessage(id="msg-123", params={})
        assert protocol.validate_mcp_message(invalid_message) is False

    def test_validate_a2a_message(self, protocol):
        """Test A2A message validation"""
        # Valid message
        valid_message = A2AMessage(id="msg-123", type="a2a_request", action="test", data={})
        assert protocol.validate_a2a_message(valid_message) is True

        # Invalid message - missing id
        invalid_message = A2AMessage(type="a2a_request", action="test", data={})
        assert protocol.validate_a2a_message(invalid_message) is False

        # Invalid message - missing type
        invalid_message = A2AMessage(id="msg-123", action="test", data={})
        assert protocol.validate_a2a_message(invalid_message) is False

    def test_message_error_handling(self, protocol):
        """Test message error handling"""
        # Test with None message
        with pytest.raises(ValueError):
            protocol.mcp_to_a2a(None)

        # Test with invalid message structure
        with pytest.raises(ValueError):
            protocol.mcp_to_a2a("invalid message")

        # Test translate and send with non-existent agent
        async def test_invalid_agent():
            protocol.mcp_to_a2a = Mock(return_value=A2AMessage(id="test", type="test", action="test", data={}))
            protocol._agent_manager = Mock()
            protocol._agent_manager.send_message = AsyncMock(side_effect=Exception("Agent not found"))

            mcp_message = MCPMessage(id="test", method="test", params={})
            with pytest.raises(Exception, match="Agent not found"):
                await protocol.translate_and_send("non-existent-agent", mcp_message)

        import asyncio
        asyncio.run(test_invalid_agent())

    def test_protocol_version_compatibility(self, protocol):
        """Test protocol version compatibility"""
        # Test different protocol versions
        mcp_message_v1 = MCPMessage(id="msg-123", method="tools/call", params={"name": "test"})
        mcp_message_v2 = MCPMessage(id="msg-124", method="tools/call", params={"name": "test", "version": "2"})

        # Both should be translatable
        result_v1 = protocol.mcp_to_a2a(mcp_message_v1)
        result_v2 = protocol.mcp_to_a2a(mcp_message_v2)

        assert result_v1 is not None
        assert result_v2 is not None
        assert result_v1.id != result_v2.id

    def test_message_id_generation(self, protocol):
        """Test message ID generation"""
        from elrmcp_bridge.src.protocol import generate_message_id

        id1 = generate_message_id()
        id2 = generate_message_id()

        # IDs should be unique
        assert id1 != id2
        # IDs should be strings
        assert isinstance(id1, str)
        # IDs should have reasonable length
        assert 10 <= len(id1) <= 50

    def test_message_acknowledgement(self, protocol):
        """Test message acknowledgement handling"""
        mock_response = {
            "result": "success",
            "id": "msg-123",
            "acknowledged": True,
            "timestamp": "2023-01-01T00:00:00Z"
        }

        # Test success response
        ack_result = protocol.process_acknowledgement(mock_response)
        assert ack_result["status"] == "success"
        assert ack_result["acknowledged"] is True

        # Test error response
        error_response = {
            "error": "Invalid message",
            "id": "msg-123",
            "acknowledged": False
        }

        ack_result = protocol.process_acknowledgement(error_response)
        assert ack_result["status"] == "error"
        assert ack_result["error"] == "Invalid message"

    @pytest.mark.asyncio
    async def test_batch_message_translation(self, protocol):
        """Test batch message translation"""
        mock_agent_manager = AsyncMock()
        protocol._agent_manager = mock_agent_manager

        # Create multiple MCP messages
        messages = [
            MCPMessage(id="msg-1", method="tools/call", params={"name": "test1"}),
            MCPMessage(id="msg-2", method="tools/create", params={"name": "test2"}),
            MCPMessage(id="msg-3", method="resources/read", params={"name": "test3"})
        ]

        mock_responses = [
            {"result": "success1", "id": "msg-1"},
            {"result": "success2", "id": "msg-2"},
            {"result": "success3", "id": "msg-3"}
        ]

        mock_agent_manager.send_message = AsyncMock(side_effect=mock_responses)

        results = await asyncio.gather(*[
            protocol.translate_and_send(f"agent-{i+1}", msg) for i, msg in enumerate(messages)
        ])

        assert len(results) == 3
        for i, result in enumerate(results):
            assert result["result"] == f"success{i+1}"
            assert result["id"] == f"msg-{i+1}"

    def test_protocol_configuration(self, protocol):
        """Test protocol configuration"""
        # Test default configuration
        assert protocol.config.timeout == 30
        assert protocol.config.max_retries == 3
        assert protocol.config.retry_delay == 1

        # Test configuration update
        protocol.config.timeout = 60
        protocol.config.max_retries = 5
        protocol.config.retry_delay = 2

        assert protocol.config.timeout == 60
        assert protocol.config.max_retries == 5
        assert protocol.config.retry_delay == 2