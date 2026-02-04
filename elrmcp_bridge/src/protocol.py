"""
A2A Protocol Translation Module

This module handles translation between MCP (Model Context Protocol) and A2A (Agent-to-Agent) protocols.
"""

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, Optional, Union


@dataclass
class ProtocolMessage:
    """Base protocol message class"""
    id: str
    type: str
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class MCPMessage:
    """MCP protocol message"""
    id: str
    type: str
    method: str
    timestamp: datetime = field(default_factory=datetime.now)
    params: Dict[str, Any] = field(default_factory=dict)
    result: Optional[Any] = None
    error: Optional[Dict[str, Any]] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "jsonrpc": "2.0",
            "id": self.id,
            "method": self.method,
            "params": self.params,
            "result": self.result,
            "error": self.error,
            "timestamp": self.timestamp.isoformat(),
            "type": self.type
        }


@dataclass
class A2AMessage:
    """A2A protocol message"""
    id: str
    type: str
    action: str
    timestamp: datetime = field(default_factory=datetime.now)
    data: Dict[str, Any] = field(default_factory=dict)
    version: str = "1.0"
    auth_token: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "type": self.type,
            "action": self.action,
            "data": self.data,
            "version": self.version,
            "timestamp": self.timestamp.isoformat(),
            "auth_token": self.auth_token
        }


class A2AProtocol:
    """Protocol translator between MCP and A2A"""

    def __init__(self, config=None):
        """Initialize protocol translator"""
        self.config = config or {}
        self.timeout = self.config.get("timeout", 30)
        self.max_retries = self.config.get("max_retries", 3)
        self.retry_delay = self.config.get("retry_delay", 1)

    def mcp_to_a2a(self, mcp_message: MCPMessage) -> A2AMessage:
        """Translate MCP message to A2A message"""
        if not self.validate_mcp_message(mcp_message):
            raise ValueError("Invalid MCP message")

        action = self._map_mcp_method_to_a2a_action(mcp_message.method)
        data = self._convert_mcp_payload_to_a2a(mcp_message.params)

        return A2AMessage(
            id=mcp_message.id,
            type="a2a_request",
            action=action,
            data=data,
            timestamp=mcp_message.timestamp
        )

    def a2a_to_mcp(self, a2a_message: A2AMessage) -> MCPMessage:
        """Translate A2A message to MCP message"""
        if not self.validate_a2a_message(a2a_message):
            raise ValueError("Invalid A2A message")

        method = self._map_a2a_action_to_mcp_method(a2a_message.action)
        params = self._convert_a2a_payload_to_mcp(a2a_message.data)

        return MCPMessage(
            id=a2a_message.id,
            type="mcp_request",
            method=method,
            params=params,
            timestamp=a2a_message.timestamp
        )

    async def translate_and_send(self, agent_id: str, mcp_message: MCPMessage) -> Dict[str, Any]:
        """Translate and send message to agent"""
        a2a_message = self.mcp_to_a2a(mcp_message)

        # This would normally send via transport layer
        # For now, return mock response
        return {
            "result": f"Message {mcp_message.id} translated to A2A and sent to {agent_id}",
            "a2a_message_id": a2a_message.id,
            "timestamp": datetime.now().isoformat()
        }

    def _map_mcp_method_to_a2a_action(self, method: str) -> str:
        """Map MCP method to A2A action"""
        mapping = {
            "tools/call": "execute_tool",
            "tools/create": "create_resource",
            "tools/list": "list_resources",
            "resources/read": "read_resource",
            "resources/write": "write_resource",
            "resources/list": "list_resources",
            "resources/delete": "delete_resource"
        }
        return mapping.get(method, "unknown_action")

    def _map_a2a_action_to_mcp_method(self, action: str) -> str:
        """Map A2A action to MCP method"""
        mapping = {
            "execute_tool": "tools/call",
            "create_resource": "tools/create",
            "list_resources": "tools/list",
            "read_resource": "resources/read",
            "write_resource": "resources/write",
            "delete_resource": "resources/delete"
        }
        return mapping.get(action, "unknown/method")

    def _convert_mcp_payload_to_a2a(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Convert MCP payload to A2A data format"""
        if not payload:
            return {}

        result = {}

        if "name" in payload:
            result["tool_name"] = payload["name"]

        if "arguments" in payload:
            result["parameters"] = payload["arguments"]

        if "input" in payload:
            result["input"] = payload["input"]

        if "output" in payload:
            result["output"] = payload["output"]

        return result

    def _convert_a2a_payload_to_mcp(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert A2A data to MCP payload format"""
        if not data:
            return {}

        result = {}

        if "tool_name" in data:
            result["name"] = data["tool_name"]

        if "parameters" in data:
            result["arguments"] = data["parameters"]

        if "input" in data:
            result["input"] = data["input"]

        if "output" in data:
            result["output"] = data["output"]

        return result

    def validate_mcp_message(self, message: MCPMessage) -> bool:
        """Validate MCP message"""
        if not message:
            return False

        if not message.id or not message.type or not message.method:
            return False

        return True

    def validate_a2a_message(self, message: A2AMessage) -> bool:
        """Validate A2A message"""
        if not message:
            return False

        if not message.id or not message.type or not message.action:
            return False

        return True

    def process_acknowledgement(self, response: Dict[str, Any]) -> Dict[str, Any]:
        """Process message acknowledgement"""
        if response.get("acknowledged", False):
            return {
                "status": "success",
                "message": response.get("message", "Message acknowledged"),
                "timestamp": response.get("timestamp")
            }
        else:
            return {
                "status": "error",
                "error": response.get("error", "Message not acknowledged"),
                "timestamp": response.get("timestamp")
            }

    def update_config(self, key: str, value: Any):
        """Update configuration"""
        self.config[key] = value


def generate_message_id(prefix: str = "") -> str:
    """Generate a unique message ID"""
    timestamp = int(datetime.now().timestamp() * 1000)
    unique_id = str(uuid.uuid4())[:8]
    return f"{prefix}_{timestamp}_{unique_id}" if prefix else f"{timestamp}_{unique_id}"