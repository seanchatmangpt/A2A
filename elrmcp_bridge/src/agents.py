"""Agent Management and Discovery

This module provides comprehensive agent discovery, registration, and management
for A2A agents, enabling seamless agent-to-agent communication and coordination.

Agent Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │                 Agent Manager                                │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ Agent       │    │ Discovery   │    │ Status      │      │
    │  │ Registry    │◄──►│ Service     │◄──►│ Monitor     │      │
    │  └─────────────┘    └─────────────┘    └─────────────┘      │
    │           │               │               │                 │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ Message     │    │ Health      │    │ Capability  │      │
    │  │ Router      │    │ Check       │    │ Registry    │      │
    │  └─────────────┘    └─────────────┘    └─────────────┘      │
    └─────────────────────────────────────────────────────────────┘

Key Features:
    - Automatic agent discovery and registration
    - Agent health monitoring and management
    - Capability-based agent routing
    - Message routing and load balancing
    - Agent lifecycle management
    - Comprehensive metrics and observability
"""

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Set, Type, Union
from enum import Enum
import uuid


class AgentStatus(Enum):
    """Agent operational status"""
    DISCOVERED = "discovered"
    REGISTERED = "registered"
    ACTIVE = "active"
    BUSY = "busy"
    OFFLINE = "offline"
    ERROR = "error"
    MAINTENANCE = "maintenance"


@dataclass
class AgentInfo:
    """Agent information and metadata"""
    agent_id: str
    name: str
    version: str
    capabilities: List[str]
    endpoints: Dict[str, str]
    status: AgentStatus = AgentStatus.DISCOVERED
    last_seen: datetime = field(default_factory=datetime.now)
    metadata: Dict[str, Any] = field(default_factory=dict)
    load: float = 0.0  # 0.0 to 1.0
    connected: bool = True
    heartbeat_count: int = 0
    errors: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "agent_id": self.agent_id,
            "name": self.name,
            "version": self.version,
            "capabilities": self.capabilities,
            "endpoints": self.endpoints,
            "status": self.status.value,
            "last_seen": self.last_seen.isoformat(),
            "metadata": self.metadata,
            "load": self.load,
            "connected": self.connected,
            "heartbeat_count": self.heartbeat_count,
            "errors": self.errors
        }


@dataclass
class AgentCapability:
    """Agent capability definition"""
    name: str
    version: str
    description: str
    parameters: List[Dict[str, Any]] = field(default_factory=list)
    return_type: str = "json"
    timeout: int = 30  # seconds
    max_retries: int = 3
    rate_limit: int = 100  # requests per minute

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "name": self.name,
            "version": self.version,
            "description": self.description,
            "parameters": self.parameters,
            "return_type": self.return_type,
            "timeout": self.timeout,
            "max_retries": self.max_retries,
            "rate_limit": self.rate_limit
        }


class AgentDiscoveryService:
    """Agent discovery and registration service"""

    def __init__(self, discovery_interval: int = 60):
        self.discovery_interval = discovery_interval
        self.logger = logging.getLogger(__name__)
        self.agents: Dict[str, AgentInfo] = {}
        self.discovery_tasks: Set[str] = set()
        self.discovery_timer = None
        self.running = False

    async def start_discovery(self):
        """Start agent discovery"""
        self.logger.info("Starting agent discovery...")
        self.running = True

        # Start periodic discovery
        self.discovery_timer = asyncio.create_task(self._periodic_discovery())

        # Start immediate discovery
        await self._discover_agents()

    async def stop_discovery(self):
        """Stop agent discovery"""
        self.logger.info("Stopping agent discovery...")
        self.running = False

        if self.discovery_timer:
            self.discovery_timer.cancel()
            self.discovery_timer = None

    async def _periodic_discovery(self):
        """Periodic agent discovery"""
        while self.running:
            try:
                await self._discover_agents()
                await asyncio.sleep(self.discovery_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in periodic discovery: {e}")
                await asyncio.sleep(self.discovery_interval)

    async def _discover_agents(self):
        """Discover available agents"""
        self.logger.debug("Starting agent discovery...")

        # Here you would implement actual discovery logic
        # For now, we'll simulate discovery
        try:
            # Mock discovery - in real implementation, this would:
            # 1. Scan the network for agents
            # 2. Query A2A registry
            # 3. Check agent endpoints
            # 4. Register discovered agents

            mock_agents = self._get_mock_agents()
            for agent_data in mock_agents:
                await self._register_agent(agent_data)

            self.logger.info(f"Discovery completed. Found {len(self.agents)} agents")

        except Exception as e:
            self.logger.error(f"Error during agent discovery: {e}")

    def _get_mock_agents(self) -> List[Dict[str, Any]]:
        """Get mock agent data for testing"""
        return [
            {
                "agent_id": "agent-001",
                "name": "Craftplan A2A Agent",
                "version": "1.0.0",
                "capabilities": ["code-analysis", "file-management", "workflow-execution"],
                "endpoints": {
                    "a2a": "http://localhost:9090",
                    "websocket": "ws://localhost:9090/ws",
                    "sse": "http://localhost:9090/events"
                },
                "metadata": {
                    "type": "a2a-agent",
                    "location": "production",
                    "owner": "craftplan"
                }
            },
            {
                "agent_id": "agent-002",
                "name": "MCP Server Agent",
                "version": "1.0.0",
                "capabilities": ["tool-execution", "resource-management"],
                "endpoints": {
                    "mcp": "http://localhost:8080",
                    "websocket": "ws://localhost:8080/ws"
                },
                "metadata": {
                    "type": "mcp-server",
                    "location": "production",
                    "owner": "elrmcp"
                }
            }
        ]

    async def _register_agent(self, agent_data: Dict[str, Any]):
        """Register discovered agent"""
        agent_id = agent_data["agent_id"]

        if agent_id in self.agents:
            # Update existing agent
            await self._update_agent(agent_id, agent_data)
        else:
            # Create new agent
            agent_info = AgentInfo(
                agent_id=agent_id,
                name=agent_data["name"],
                version=agent_data["version"],
                capabilities=agent_data["capabilities"],
                endpoints=agent_data["endpoints"],
                status=AgentStatus.REGISTERED,
                metadata=agent_data.get("metadata", {})
            )

            self.agents[agent_id] = agent_info
            self.logger.info(f"Registered new agent: {agent_id}")

    async def _update_agent(self, agent_id: str, agent_data: Dict[str, Any]):
        """Update existing agent"""
        if agent_id not in self.agents:
            return

        agent = self.agents[agent_id]

        # Update agent information
        agent.name = agent_data.get("name", agent.name)
        agent.version = agent_data.get("version", agent.version)
        agent.capabilities = agent_data.get("capabilities", agent.capabilities)
        agent.endpoints = agent_data.get("endpoints", agent.endpoints)
        agent.metadata = agent_data.get("metadata", agent.metadata)
        agent.last_seen = datetime.now()
        agent.status = AgentStatus.ACTIVE

        self.logger.debug(f"Updated agent: {agent_id}")

    async def unregister_agent(self, agent_id: str):
        """Unregister agent"""
        if agent_id in self.agents:
            del self.agents[agent_id]
            self.logger.info(f"Unregistered agent: {agent_id}")

    def get_agent(self, agent_id: str) -> Optional[AgentInfo]:
        """Get agent information"""
        return self.agents.get(agent_id)

    def get_agents_by_capability(self, capability: str) -> List[AgentInfo]:
        """Get agents by capability"""
        return [
            agent for agent in self.agents.values()
            if agent.status == AgentStatus.ACTIVE
            and capability in agent.capabilities
            and agent.connected
        ]

    def get_all_agents(self) -> List[AgentInfo]:
        """Get all agents"""
        return list(self.agents.values())

    def get_active_agents(self) -> List[AgentInfo]:
        """Get active agents"""
        return [
            agent for agent in self.agents.values()
            if agent.status == AgentStatus.ACTIVE
            and agent.connected
        ]

    def get_agent_status(self, agent_id: Optional[str] = None) -> Dict[str, Any]:
        """Get agent status information"""
        if agent_id:
            agent = self.agents.get(agent_id)
            return agent.to_dict() if agent else {"error": "Agent not found"}
        else:
            return {
                "total_agents": len(self.agents),
                "active_agents": len([a for a in self.agents.values() if a.status == AgentStatus.ACTIVE]),
                "offline_agents": len([a for a in self.agents.values() if a.status == AgentStatus.OFFLINE]),
                "agents": {aid: agent.to_dict() for aid, agent in self.agents.items()}
            }


class AgentHealthMonitor:
    """Agent health monitoring"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.health_checks: Dict[str, Dict[str, Any]] = {}
        self.health_check_interval = 30  # seconds
        self.health_check_timer = None
        self.running = False

    async def start_health_checks(self):
        """Start health monitoring"""
        self.logger.info("Starting agent health checks...")
        self.running = True
        self.health_check_timer = asyncio.create_task(self._periodic_health_checks())

    async def stop_health_checks(self):
        """Stop health monitoring"""
        self.logger.info("Stopping agent health checks...")
        self.running = False

        if self.health_check_timer:
            self.health_check_timer.cancel()
            self.health_check_timer = None

    async def _periodic_health_checks(self):
        """Periodic health checks"""
        while self.running:
            try:
                await self._check_agent_health()
                await asyncio.sleep(self.health_check_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in health checks: {e}")
                await asyncio.sleep(self.health_check_interval)

    async def _check_agent_health(self):
        """Check health of all agents"""
        for agent_id, agent_info in self.agents.items():
            await self._check_individual_agent_health(agent_id, agent_info)

    async def _check_individual_agent_health(self, agent_id: str, agent_info: AgentInfo):
        """Check individual agent health"""
        try:
            # Check if agent is responsive
            health_status = await self._ping_agent(agent_id, agent_info)

            # Update agent health status
            self.health_checks[agent_id] = health_status

            # Update agent status based on health
            if health_status["healthy"]:
                agent_info.status = AgentStatus.ACTIVE
                agent_info.errors = [error for error in agent_info.errors if not self._is_transient_error(error)]
            else:
                agent_info.status = AgentStatus.ERROR
                agent_info.errors.append(health_status["error"])

            agent_info.last_seen = datetime.now()

        except Exception as e:
            self.logger.error(f"Error checking health for agent {agent_id}: {e}")
            agent_info.status = AgentStatus.ERROR
            agent_info.errors.append(str(e))

    async def _ping_agent(self, agent_id: str, agent_info: AgentInfo) -> Dict[str, Any]:
        """Ping agent for health check"""
        try:
            # Simulate health check
            # In real implementation, this would:
            # 1. Send a health check request to the agent
            # 2. Check response time and status
            # 3. Validate agent capabilities

            # Mock health check
            return {
                "healthy": True,
                "response_time": 0.1,
                "timestamp": datetime.now().isoformat(),
                "error": None
            }

        except Exception as e:
            return {
                "healthy": False,
                "response_time": None,
                "timestamp": datetime.now().isoformat(),
                "error": str(e)
            }

    def _is_transient_error(self, error: str) -> bool:
        """Check if error is transient"""
        transient_errors = [
            "timeout", "connection refused", "network error", "temporary"
        ]
        return any(transient in error.lower() for transient in transient_errors)


class AgentMessageRouter:
    """Agent message routing and load balancing"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.message_queue: asyncio.Queue = asyncio.Queue()
        self.active_routes: Dict[str, asyncio.Task] = {}
        self.load_balancer = LoadBalancer()

    async def route_message(self, message: Dict[str, Any], target_agents: List[AgentInfo]) -> Dict[str, Any]:
        """Route message to target agents"""
        if not target_agents:
            return {"error": "No target agents available"}

        # Select agent using load balancer
        selected_agent = self.load_balancer.select_agent(target_agents)

        # Route message to selected agent
        return await self._send_to_agent(selected_agent, message)

    async def _send_to_agent(self, agent: AgentInfo, message: Dict[str, Any]) -> Dict[str, Any]:
        """Send message to specific agent"""
        try:
            # Select appropriate endpoint based on message type
            endpoint = self._select_endpoint(agent, message)

            # Send message
            response = await self._send_message(endpoint, message)

            # Update agent load
            agent.load = self._calculate_agent_load(response)

            return response

        except Exception as e:
            self.logger.error(f"Error sending message to agent {agent.agent_id}: {e}")
            return {"error": str(e)}

    def _select_endpoint(self, agent: AgentInfo, message: Dict[str, Any]) -> str:
        """Select appropriate endpoint for message"""
        message_type = message.get("type", "a2a_message")

        if message_type == "mcp_request":
            return agent.endpoints.get("mcp", agent.endpoints["a2a"])
        elif message_type == "a2a_message":
            return agent.endpoints.get("a2a", agent.endpoints["websocket"])
        else:
            return agent.endpoints.get("websocket", agent.endpoints["a2a"])

    async def _send_message(self, endpoint: str, message: Dict[str, Any]) -> Dict[str, Any]:
        """Send message to endpoint"""
        # Mock message sending
        # In real implementation, this would use HTTP client, WebSocket, or SSE
        await asyncio.sleep(0.1)  # Simulate network latency

        return {
            "success": True,
            "message_id": message["id"],
            "response_time": 0.1,
            "timestamp": datetime.now().isoformat()
        }

    def _calculate_agent_load(self, response: Dict[str, Any]) -> float:
        """Calculate agent load based on response"""
        # Simple load calculation based on response time
        response_time = response.get("response_time", 0.0)

        if response_time < 0.1:
            return 0.2
        elif response_time < 0.5:
            return 0.5
        else:
            return 0.8


class LoadBalancer:
    """Load balancing algorithm for agent selection"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.algorithm = "round_robin"  # round_robin, least_loaded, random

    def select_agent(self, agents: List[AgentInfo]) -> AgentInfo:
        """Select agent using configured algorithm"""
        if not agents:
            raise ValueError("No agents available")

        if self.algorithm == "round_robin":
            return self._round_robin_selection(agents)
        elif self.algorithm == "least_loaded":
            return self._least_loaded_selection(agents)
        elif self.algorithm == "random":
            return self._random_selection(agents)
        else:
            return self._least_loaded_selection(agents)

    def _round_robin_selection(self, agents: List[AgentInfo]) -> AgentInfo:
        """Round-robin agent selection"""
        # Simple round-robin implementation
        # In real implementation, you'd track the last selected agent
        return agents[0]

    def _least_loaded_selection(self, agents: List[AgentInfo]) -> AgentInfo:
        """Select least loaded agent"""
        return min(agents, key=lambda agent: agent.load)

    def _random_selection(self, agents: List[AgentInfo]) -> AgentInfo:
        """Random agent selection"""
        import random
        return random.choice(agents)


class AgentManager:
    """Main agent management service"""

    def __init__(self, discovery_interval: int = 60):
        self.discovery_interval = discovery_interval
        self.logger = logging.getLogger(__name__)

        # Initialize components
        self.discovery_service = AgentDiscoveryService(discovery_interval)
        self.health_monitor = AgentHealthMonitor()
        self.message_router = AgentMessageRouter()

        # Event handlers
        self.event_handlers: Dict[str, List] = {}

        # Agents registry
        self.agents: Dict[str, AgentInfo] = {}

    async def initialize(self):
        """Initialize agent manager"""
        self.logger.info("Initializing Agent Manager...")

        # Initialize discovery service
        await self.discovery_service.start_discovery()

        # Initialize health monitoring
        await self.health_monitor.start_health_checks()

        # Set up event handlers
        self._setup_event_handlers()

        self.logger.info("Agent Manager initialized successfully")

    async def start_discovery(self):
        """Start agent discovery"""
        await self.discovery_service.start_discovery()

    async def stop_discovery(self):
        """Stop agent discovery"""
        await self.discovery_service.stop_discovery()
        await self.health_monitor.stop_health_checks()

    def _setup_event_handlers(self):
        """Set up event handlers"""
        self.event_handlers = {
            "agent_discovered": self._on_agent_discovered,
            "agent_lost": self._on_agent_lost,
            "agent_status_changed": self._on_agent_status_changed,
            "heartbeat": self._on_heartbeat
        }

    async def send_to_agent(self, agent_id: str, message: Dict[str, Any]) -> Dict[str, Any]:
        """Send message to specific agent"""
        agent = self.agents.get(agent_id)
        if not agent:
            return {"error": f"Agent not found: {agent_id}"}

        # Update agent heartbeat
        agent.last_seen = datetime.now()
        agent.heartbeat_count += 1

        # Route message to agent
        return await self.message_router._send_to_agent(agent, message)

    async def send_to_capability(self, capability: str, message: Dict[str, Any]) -> Dict[str, Any]:
        """Send message to agents with specific capability"""
        target_agents = self.discovery_service.get_agents_by_capability(capability)

        if not target_agents:
            return {"error": f"No agents found with capability: {capability}"}

        # Route message to agents
        return await self.message_router.route_message(message, target_agents)

    async def get_agent_status(self, agent_id: Optional[str] = None) -> Dict[str, Any]:
        """Get agent status information"""
        return self.discovery_service.get_agent_status(agent_id)

    async def get_agents_by_capability(self, capability: str) -> List[AgentInfo]:
        """Get agents by capability"""
        return self.discovery_service.get_agents_by_capability(capability)

    async def refresh_agent_list(self):
        """Refresh agent list"""
        await self.discovery_service._discover_agents()

    def add_event_handler(self, event_type: str, handler):
        """Add event handler"""
        if event_type not in self.event_handlers:
            self.event_handlers[event_type] = []
        self.event_handlers[event_type].append(handler)

    def remove_event_handler(self, event_type: str, handler):
        """Remove event handler"""
        if event_type in self.event_handlers:
            if handler in self.event_handlers[event_type]:
                self.event_handlers[event_type].remove(handler)

    async def _on_agent_discovered(self, agent_info: AgentInfo):
        """Handle agent discovered event"""
        self.agents[agent_info.agent_id] = agent_info
        self.logger.info(f"Agent discovered: {agent_info.agent_id}")

        # Emit event to handlers
        await self.emit_event("agent_discovered", agent_info)

    async def _on_agent_lost(self, agent_info: AgentInfo):
        """Handle agent lost event"""
        if agent_info.agent_id in self.agents:
            del self.agents[agent_info.agent_id]
            self.logger.info(f"Agent lost: {agent_info.agent_id}")

            # Emit event to handlers
            await self.emit_event("agent_lost", agent_info)

    async def _on_agent_status_changed(self, agent_info: AgentInfo):
        """Handle agent status change event"""
        self.logger.info(f"Agent status changed: {agent_info.agent_id} -> {agent_info.status}")

        # Emit event to handlers
        await self.emit_event("agent_status_changed", agent_info)

    async def _on_heartbeat(self, agent_info: AgentInfo):
        """Handle heartbeat event"""
        agent_info.last_seen = datetime.now()
        await self.emit_event("heartbeat", agent_info)

    async def emit_event(self, event_type: str, data: Any):
        """Emit event to all handlers"""
        if event_type in self.event_handlers:
            for handler in self.event_handlers[event_type]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(data)
                    else:
                        handler(data)
                except Exception as e:
                    self.logger.error(f"Error in event handler: {e}")

    @property
    def agents(self) -> Dict[str, AgentInfo]:
        """Get agents registry"""
        return self.discovery_service.agents