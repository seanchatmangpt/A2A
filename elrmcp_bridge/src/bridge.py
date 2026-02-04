"""A2A Bridge - Main Integration Orchestrator

This module provides the main bridge between elrmcp and Craftplan A2A agents,
orchestrating communication, protocol translation, and multi-agent coordination.

Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │                    A2A Bridge                                │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ MCP Client  │◄──►│  Protocol   │◄──►│ Agent Mgmt  │      │
    │  │  (elrmcp)   │    │  Adapter    │    │   & Discov  │      │
    │  └─────────────┘    └─────────────┘    └─────────────┘      │
    │           │               │               │                 │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ Transport  │    │ Workflows   │    │ Metrics &   │      │
    │  │ (WebSocket  │    │ Orchestrator│    │ Monitoring  │      │
    │  │   / SSE)    │    └─────────────┘    └─────────────┘      │
    │  └─────────────┘                                             │
    └─────────────────────────────────────────────────────────────┘

Key Features:
    - Protocol translation: MCP ↔ A2A
    - Agent discovery and registration
    - Multi-agent task delegation
    - Real-time event streaming
    - Comprehensive error handling
    - Metrics and observability
"""

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional, Set, Type
from enum import Enum

from .protocol import A2AProtocol
from .agents import AgentManager, AgentInfo
from .transport import TransportManager
from .workflows import WorkflowOrchestrator
from .api import APIServer
from .metrics import MetricsCollector


class BridgeState(Enum):
    """Bridge operational states"""
    INITIALIZING = "initializing"
    READY = "ready"
    CONNECTING = "connecting"
    DEGRADED = "degraded"
    ERROR = "error"
    STOPPING = "stopping"


@dataclass
class BridgeConfig:
    """Configuration for A2A Bridge"""
    # MCP Server Configuration
    mcp_server_url: str = "http://localhost:8080"
    mcp_server_timeout: int = 30

    # A2A Agent Configuration
    a2a_agent_url: str = "http://localhost:9090"
    a2a_agent_timeout: int = 30

    # Transport Configuration
    transport_type: str = "websocket"  # websocket, sse, hybrid
    websocket_url: str = "ws://localhost:8090"
    sse_url: str = "http://localhost:9090/events"

    # Agent Discovery
    discovery_interval: int = 60  # seconds
    heartbeat_interval: int = 30  # seconds

    # Workflows
    max_concurrent_workflows: int = 10
    workflow_timeout: int = 300  # seconds

    # Metrics
    metrics_enabled: bool = True
    metrics_port: int = 8000

    # API
    api_enabled: bool = True
    api_port: int = 8001

    # Logging
    log_level: str = "INFO"
    log_format: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"


@dataclass
class BridgeMetrics:
    """Bridge operational metrics"""
    total_messages_processed: int = 0
    total_workflows_completed: int = 0
    total_agents_discovered: int = 0
    uptime_seconds: int = 0
    last_error_time: Optional[datetime] = None
    error_count: int = 0


class A2ABridge:
    """Main A2A Bridge orchestrator"""

    def __init__(self, config: BridgeConfig):
        self.config = config
        self.state = BridgeState.INITIALIZING
        self.logger = logging.getLogger(__name__)
        self.metrics = BridgeMetrics()

        # Initialize components
        self.protocol = A2AProtocol()
        self.transport = TransportManager(config.transport_type)
        self.agent_manager = AgentManager(config.discovery_interval)
        self.workflow_orchestrator = WorkflowOrchestrator(
            max_concurrent_workflows=config.max_concurrent_workflows,
            workflow_timeout=config.workflow_timeout
        )

        # API Server
        self.api_server = APIServer(
            port=config.api_port,
            bridge=self
        ) if config.api_enabled else None

        # Metrics
        self.metrics_collector = MetricsCollector(
            port=config.metrics_port
        ) if config.metrics_enabled else None

        # Event handlers
        self._event_handlers: Dict[str, List] = {}

        # Start time
        self.start_time = datetime.now()

    async def start(self):
        """Start the A2A Bridge"""
        self.logger.info("Starting A2A Bridge...")
        self.state = BridgeState.INITIALIZING

        try:
            # Initialize components
            await self._initialize_components()

            # Start transport
            await self.transport.start()

            # Start agent discovery
            await self.agent_manager.start_discovery()

            # Start workflow orchestrator
            await self.workflow_orchestrator.start()

            # Start API server
            if self.api_server:
                await self.api_server.start()

            # Start metrics
            if self.metrics_collector:
                await self.metrics_collector.start()

            # Set up event handlers
            self._setup_event_handlers()

            self.state = BridgeState.READY
            self.logger.info("A2A Bridge started successfully")

        except Exception as e:
            self.state = BridgeState.ERROR
            self.logger.error(f"Failed to start A2A Bridge: {e}")
            raise

    async def stop(self):
        """Stop the A2A Bridge"""
        self.logger.info("Stopping A2A Bridge...")
        self.state = BridgeState.STOPPING

        try:
            # Stop components in reverse order
            if self.metrics_collector:
                await self.metrics_collector.stop()

            if self.api_server:
                await self.api_server.stop()

            await self.workflow_orchestrator.stop()
            await self.agent_manager.stop_discovery()
            await self.transport.stop()

            self.state = BridgeState.INITIALIZING
            self.logger.info("A2A Bridge stopped successfully")

        except Exception as e:
            self.logger.error(f"Error stopping A2A Bridge: {e}")
            raise

    async def _initialize_components(self):
        """Initialize all bridge components"""
        # Initialize protocol
        await self.protocol.initialize()

        # Initialize transport
        await self.transport.initialize()

        # Initialize agent manager
        await self.agent_manager.initialize()

        # Initialize workflow orchestrator
        await self.workflow_orchestrator.initialize()

    def _setup_event_handlers(self):
        """Set up event handlers for component events"""
        # Transport events
        self.transport.add_event_handler("message_received", self._on_transport_message)
        self.transport.add_event_handler("connection_established", self._on_connection_established)
        self.transport.add_event_handler("connection_lost", self._on_connection_lost)

        # Agent manager events
        self.agent_manager.add_event_handler("agent_discovered", self._on_agent_discovered)
        self.agent_manager.add_event_handler("agent_lost", self._on_agent_lost)

        # Workflow events
        self.workflow_orchestrator.add_event_handler("workflow_completed", self._on_workflow_completed)
        self.workflow_orchestrator.add_event_handler("workflow_failed", self._on_workflow_failed)

    async def _on_transport_message(self, message: dict):
        """Handle incoming transport message"""
        self.metrics.total_messages_processed += 1

        # Route message based on type
        message_type = message.get("type")

        if message_type == "mcp_request":
            await self._handle_mcp_request(message)
        elif message_type == "a2a_message":
            await self._handle_a2a_message(message)
        elif message_type == "workflow_event":
            await self._handle_workflow_event(message)
        else:
            self.logger.warning(f"Unknown message type: {message_type}")

    async def _handle_mcp_request(self, message: dict):
        """Handle MCP request from elrmcp"""
        try:
            # Translate MCP to A2A protocol
            a2a_message = await self.protocol.mcp_to_a2a(message)

            # Send to A2A agent
            response = await self.transport.send(a2a_message)

            # Translate A2A response back to MCP
            mcp_response = await self.protocol.a2a_to_mcp(response)

            # Send response back to elrmcp
            await self.transport.send(mcp_response)

        except Exception as e:
            self.logger.error(f"Error handling MCP request: {e}")
            await self._handle_error(e)

    async def _handle_a2a_message(self, message: dict):
        """Handle A2A message from agent"""
        try:
            # Translate A2A to MCP protocol
            mcp_message = await self.protocol.a2a_to_mcp(message)

            # Send to elrmcp
            response = await self.transport.send(mcp_message)

            # Translate MCP response back to A2A
            a2a_response = await self.protocol.mcp_to_a2a(response)

            # Send response back to agent
            await self.transport.send(a2a_response)

        except Exception as e:
            self.logger.error(f"Error handling A2A message: {e}")
            await self._handle_error(e)

    async def _handle_workflow_event(self, message: dict):
        """Handle workflow event"""
        workflow_id = message.get("workflow_id")
        event_type = message.get("event_type")

        # Forward to workflow orchestrator
        await self.workflow_orchestrator.handle_event(workflow_id, event_type, message)

    async def _on_connection_established(self, connection_info: dict):
        """Handle connection established event"""
        self.logger.info(f"Connection established: {connection_info}")

        # Notify all components
        await self.agent_manager.refresh_agent_list()

    async def _on_connection_lost(self, connection_info: dict):
        """Handle connection lost event"""
        self.logger.warning(f"Connection lost: {connection_info}")

        # Update metrics
        self.metrics.last_error_time = datetime.now()
        self.metrics.error_count += 1

        # Attempt to reconnect
        await self.transport.reconnect()

    async def _on_agent_discovered(self, agent_info: AgentInfo):
        """Handle agent discovered event"""
        self.metrics.total_agents_discovered += 1
        self.logger.info(f"Agent discovered: {agent_info.agent_id}")

        # Notify other components
        await self.workflow_orchestrator.add_available_agent(agent_info)

    async def _on_agent_lost(self, agent_info: AgentInfo):
        """Handle agent lost event"""
        self.logger.warning(f"Agent lost: {agent_info.agent_id}")

        # Remove from orchestrator
        await self.workflow_orchestrator.remove_agent(agent_info.agent_id)

    async def _on_workflow_completed(self, workflow_id: str):
        """Handle workflow completed event"""
        self.metrics.total_workflows_completed += 1
        self.logger.info(f"Workflow completed: {workflow_id}")

    async def _on_workflow_failed(self, workflow_id: str, error: str):
        """Handle workflow failed event"""
        self.logger.error(f"Workflow failed: {workflow_id}, error: {error}")

        # Update metrics
        self.metrics.last_error_time = datetime.now()
        self.metrics.error_count += 1

    async def _handle_error(self, error: Exception):
        """Handle bridge error"""
        self.logger.error(f"Bridge error: {error}")
        self.state = BridgeState.ERROR
        self.metrics.last_error_time = datetime.now()
        self.metrics.error_count += 1

    # Public API methods
    async def send_to_agent(self, agent_id: str, message: dict) -> dict:
        """Send message to specific agent"""
        return await self.agent_manager.send_to_agent(agent_id, message)

    async def start_workflow(self, workflow_config: dict) -> str:
        """Start a multi-agent workflow"""
        return await self.workflow_orchestrator.start_workflow(workflow_config)

    async def get_agent_status(self, agent_id: Optional[str] = None) -> dict:
        """Get agent status information"""
        return await self.agent_manager.get_agent_status(agent_id)

    async def get_workflow_status(self, workflow_id: Optional[str] = None) -> dict:
        """Get workflow status information"""
        return await self.workflow_orchestrator.get_workflow_status(workflow_id)

    async def get_bridge_metrics(self) -> dict:
        """Get bridge operational metrics"""
        uptime = (datetime.now() - self.start_time).total_seconds()
        self.metrics.uptime_seconds = int(uptime)

        return {
            "state": self.state.value,
            "metrics": self.metrics,
            "uptime": uptime,
            "config": self.config.__dict__
        }

    # Event handling
    def add_event_handler(self, event_type: str, handler):
        """Add event handler"""
        if event_type not in self._event_handlers:
            self._event_handlers[event_type] = []
        self._event_handlers[event_type].append(handler)

    def remove_event_handler(self, event_type: str, handler):
        """Remove event handler"""
        if event_type in self._event_handlers:
            if handler in self._event_handlers[event_type]:
                self._event_handlers[event_type].remove(handler)

    async def emit_event(self, event_type: str, data: dict):
        """Emit event to all handlers"""
        if event_type in self._event_handlers:
            for handler in self._event_handlers[event_type]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(data)
                    else:
                        handler(data)
                except Exception as e:
                    self.logger.error(f"Error in event handler: {e}")