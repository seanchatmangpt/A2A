"""A2A Integration Module for elrmcp + Craftplan Agent Communication

This module provides a comprehensive bridge between elrmcp and Craftplan A2A agents,
enabling seamless agent-to-agent communication with enterprise-grade features.

Architecture:
    ├── elrmcp_bridge/
    │   ├── src/
    │   │   ├── __init__.py
    │   │   ├── bridge.py          # Main bridge orchestrator
    │   │   ├── protocol.py       # A2A protocol adapters
    │   │   ├── agents.py         # Agent management and discovery
    │   │   ├── transport.py      # WebSocket/SSE transport layer
    │   │   ├── workflows.py      # Multi-agent workflow orchestration
    │   │   ├── api/              # Management API
    │   │   ├── metrics.py        # Metrics and observability
    │   │   └── config.py        # Configuration management
    │   ├── test/                 # Comprehensive test suite
    │   └── examples/            # Usage examples and demos

Features:
    - JSON-RPC 2.0 A2A protocol implementation
    - Real-time SSE updates
    - Agent discovery and registration
    - Multi-agent task delegation
    - Cross-agent communication
    - Workflow orchestration
    - Comprehensive metrics and logging
    - Enterprise-grade security and monitoring

Integration Points:
    - elrmcp → A2A agent communication
    - A2A agent → elrmcp MCP calls
    - Agent discovery and capabilities exchange
    - Task lifecycle management
    - Real-time event streaming
    - Multi-agent collaboration workflows
"""

__version__ = "0.1.0"
__author__ = "A2A Integration Team"
__email__ = "a2a@example.com"

from .bridge import A2ABridge
from .protocol import A2AProtocol
from .agents import AgentManager
from .transport import TransportManager
from .workflows import WorkflowOrchestrator

__all__ = [
    "A2ABridge",
    "A2AProtocol",
    "AgentManager",
    "TransportManager",
    "WorkflowOrchestrator"
]