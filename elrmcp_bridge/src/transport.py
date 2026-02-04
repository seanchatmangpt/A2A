"""Transport Layer - WebSocket and SSE Communication

This module provides robust transport capabilities for A2A communication,
supporting WebSocket, SSE (Server-Sent Events), and hybrid transport modes.

Transport Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │                 Transport Manager                             │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ WebSocket   │    │ Connection  │    │ Message     │      │
    │  │ Handler     │◄──►│ Manager     │◄──► │ Processor   │      │
    │  └─────────────┘    └─────────────┘    └─────────────┘      │
    │           │               │               │                 │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ SSE        │    │ Event       │    │ Protocol    │      │
    │  │ Handler     │    │ Router      │    │ Adapter     │      │
    │  └─────────────┘    └─────────────┘    └─────────────┘      │
    └─────────────────────────────────────────────────────────────┘

Key Features:
    - Multi-transport support (WebSocket, SSE, Hybrid)
    - Connection pooling and management
    - Message routing and processing
    - Real-time event streaming
    - Automatic reconnection
    - Comprehensive error handling
"""

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional, Set, Type, Union
from enum import Enum
import uuid
import websockets
import aiohttp
from aiohttp import web


class TransportType(Enum):
    """Supported transport types"""
    WEBSOCKET = "websocket"
    SSE = "sse"
    HYBRID = "hybrid"


@dataclass
class ConnectionInfo:
    """Connection information"""
    connection_id: str
    transport_type: TransportType
    endpoint: str
    connected: bool = False
    created_at: datetime = field(default_factory=datetime.now)
    last_activity: datetime = field(default_factory=datetime.now)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class TransportMessage:
    """Transport message"""
    id: str
    content: Any
    timestamp: datetime = field(default_factory=datetime.now)
    source: Optional[str] = None
    target: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class WebSocketHandler:
    """WebSocket connection handler"""

    def __init__(self, endpoint: str, max_connections: int = 100):
        self.endpoint = endpoint
        self.max_connections = max_connections
        self.logger = logging.getLogger(__name__)
        self.connections: Dict[str, websockets.WebSocketServerProtocol] = {}
        self.running = False
        self.server = None

    async def start(self):
        """Start WebSocket server"""
        self.logger.info(f"Starting WebSocket server at {self.endpoint}")

        # Extract host and port from endpoint
        if self.endpoint.startswith("ws://"):
            uri = self.endpoint
        else:
            uri = f"ws://{self.endpoint}"

        # Start WebSocket server
        self.server = await websockets.serve(
            self._handle_connection,
            uri.split(":")[1] if ":" in uri.split("//")[1] else "localhost",
            int(uri.split(":")[2]) if ":" in uri.split("//")[1] else 8080
        )

        self.running = True
        self.logger.info(f"WebSocket server started at {self.endpoint}")

    async def stop(self):
        """Stop WebSocket server"""
        self.logger.info("Stopping WebSocket server...")

        self.running = False

        # Close all connections
        for connection_id, connection in self.connections.items():
            try:
                await connection.close()
            except Exception as e:
                self.logger.error(f"Error closing connection {connection_id}: {e}")

        # Close server
        if self.server:
            self.server.close()
            await self.server.wait_closed()

    async def _handle_connection(self, websocket, path):
        """Handle incoming WebSocket connection"""
        connection_id = str(uuid.uuid4())
        self.connections[connection_id] = websocket

        try:
            self.logger.info(f"WebSocket connection established: {connection_id}")

            # Send welcome message
            welcome_message = {
                "type": "connection_established",
                "connection_id": connection_id,
                "timestamp": datetime.now().isoformat()
            }

            await websocket.send(json.dumps(welcome_message))

            # Handle incoming messages
            async for message in websocket:
                try:
                    await self._handle_message(connection_id, message)
                except Exception as e:
                    self.logger.error(f"Error handling message: {e}")

        except websockets.exceptions.ConnectionClosed:
            self.logger.info(f"WebSocket connection closed: {connection_id}")
        except Exception as e:
            self.logger.error(f"Error in WebSocket connection: {e}")
        finally:
            # Clean up connection
            if connection_id in self.connections:
                del self.connections[connection_id]

    async def _handle_message(self, connection_id: str, message: str):
        """Handle incoming WebSocket message"""
        try:
            data = json.loads(message)
            data["connection_id"] = connection_id
            data["transport_type"] = "websocket"
            data["timestamp"] = datetime.now().isoformat()

            # Process message
            await self._process_message(data)

        except json.JSONDecodeError as e:
            self.logger.error(f"Invalid JSON message: {e}")
        except Exception as e:
            self.logger.error(f"Error handling WebSocket message: {e}")

    async def _process_message(self, message: Dict[str, Any]):
        """Process incoming message"""
        # Emit message to event handlers
        if hasattr(self, 'event_handlers') and 'message_received' in self.event_handlers:
            for handler in self.event_handlers['message_received']:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(message)
                    else:
                        handler(message)
                except Exception as e:
                    self.logger.error(f"Error in message handler: {e}")

    async def send_message(self, message: Dict[str, Any]) -> bool:
        """Send message to all connected clients"""
        success = True

        for connection_id, connection in self.connections.items():
            try:
                await connection.send(json.dumps(message))
            except Exception as e:
                self.logger.error(f"Error sending message to {connection_id}: {e}")
                success = False

        return success

    def get_connection_count(self) -> int:
        """Get number of active connections"""
        return len(self.connections)


class SSEHandler:
    """SSE (Server-Sent Events) handler"""

    def __init__(self, endpoint: str):
        self.endpoint = endpoint
        self.logger = logging.getLogger(__name__)
        self.clients: Dict[str, asyncio.Queue] = {}
        self.running = False
        self.server = None

    async def start(self):
        """Start SSE server"""
        self.logger.info(f"Starting SSE server at {self.endpoint}")

        # Create HTTP server
        app = web.Application()
        app.router.add_get('/events', self._handle_sse_connection)

        # Extract host and port from endpoint
        if ":" in self.endpoint:
            host, port = self.endpoint.split(":")[1], self.endpoint.split(":")[2]
        else:
            host, port = "localhost", 8080

        # Start server
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, host, port)
        await site.start()

        self.running = True
        self.server = runner
        self.logger.info(f"SSE server started at {self.endpoint}")

    async def stop(self):
        """Stop SSE server"""
        self.logger.info("Stopping SSE server...")

        self.running = False

        # Close all clients
        for client_id, queue in self.clients.items():
            try:
                queue.put_nowait(None)
            except Exception as e:
                self.logger.error(f"Error closing SSE client {client_id}: {e}")

        # Close server
        if self.server:
            await self.server.cleanup()

    async def _handle_sse_connection(self, request):
        """Handle SSE connection"""
        client_id = str(uuid.uuid4())
        self.clients[client_id] = asyncio.Queue()

        # Send welcome event
        await self._send_event(client_id, {
            "type": "connection_established",
            "client_id": client_id,
            "timestamp": datetime.now().isoformat()
        })

        try:
            # Keep connection alive
            response = web.StreamResponse(
                status=200,
                headers={
                    'Content-Type': 'text/event-stream',
                    'Cache-Control': 'no-cache',
                    'Connection': 'keep-alive',
                    'Access-Control-Allow-Origin': '*'
                }
            )
            await response.prepare(request)

            while self.running:
                # Wait for message
                message = await self.clients[client_id].get()
                if message is None:
                    break

                # Send event
                await self._send_sse_event(response, message)

            await response.write_eof()

        except Exception as e:
            self.logger.error(f"Error in SSE connection {client_id}: {e}")
        finally:
            # Clean up client
            if client_id in self.clients:
                del self.clients[client_id]

    async def _send_sse_event(self, response, event_data: Dict[str, Any]):
        """Send SSE event"""
        try:
            event_json = json.dumps(event_data)
            sse_event = f"data: {event_json}\n\n"

            await response.write(sse_event.encode('utf-8'))
            await response.drain()

        except Exception as e:
            self.logger.error(f"Error sending SSE event: {e}")

    async def _send_event(self, client_id: str, event_data: Dict[str, Any]):
        """Send event to specific client"""
        if client_id in self.clients:
            try:
                await self.clients[client_id].put(event_data)
            except Exception as e:
                self.logger.error(f"Error sending event to {client_id}: {e}")

    async def broadcast_event(self, event_data: Dict[str, Any]):
        """Broadcast event to all clients"""
        for client_id in self.clients:
            await self._send_event(client_id, event_data)

    def get_client_count(self) -> int:
        """Get number of active clients"""
        return len(self.clients)


class ConnectionManager:
    """Connection management and pooling"""

    def __init__(self, max_connections: int = 100):
        self.max_connections = max_connections
        self.logger = logging.getLogger(__name__)
        self.connections: Dict[str, ConnectionInfo] = {}
        self.connection_pool: Dict[str, Any] = {}
        self.running = False

    async def start(self):
        """Start connection manager"""
        self.logger.info("Starting connection manager...")
        self.running = True

    async def stop(self):
        """Stop connection manager"""
        self.logger.info("Stopping connection manager...")

        self.running = False

        # Close all connections
        for connection_id, connection_info in self.connections.items():
            await self._close_connection(connection_id)

    async def create_connection(self, endpoint: str, transport_type: TransportType) -> ConnectionInfo:
        """Create new connection"""
        connection_id = str(uuid.uuid4())

        # Check connection limit
        if len(self.connections) >= self.max_connections:
            raise Exception("Maximum connections reached")

        # Create connection info
        connection_info = ConnectionInfo(
            connection_id=connection_id,
            transport_type=transport_type,
            endpoint=endpoint
        )

        self.connections[connection_id] = connection_info

        return connection_info

    async def close_connection(self, connection_id: str):
        """Close specific connection"""
        if connection_id in self.connections:
            await self._close_connection(connection_id)

    async def _close_connection(self, connection_id: str):
        """Close connection"""
        try:
            connection_info = self.connections[connection_id]

            # Close actual connection
            if connection_id in self.connection_pool:
                connection = self.connection_pool[connection_id]
                if hasattr(connection, 'close'):
                    await connection.close()
                del self.connection_pool[connection_id]

            # Update connection info
            connection_info.connected = False
            connection_info.last_activity = datetime.now()

            self.logger.info(f"Connection closed: {connection_id}")

        except Exception as e:
            self.logger.error(f"Error closing connection {connection_id}: {e}")
        finally:
            if connection_id in self.connections:
                del self.connections[connection_id]

    async def get_connection(self, connection_id: str) -> Optional[ConnectionInfo]:
        """Get connection information"""
        return self.connections.get(connection_id)

    def get_connection_count(self) -> int:
        """Get number of active connections"""
        return len(self.connections)

    def get_connection_stats(self) -> Dict[str, Any]:
        """Get connection statistics"""
        active_connections = sum(1 for conn in self.connections.values() if conn.connected)
        total_connections = len(self.connections)

        return {
            "total_connections": total_connections,
            "active_connections": active_connections,
            "inactive_connections": total_connections - active_connections,
            "connection_types": {
                transport.value: sum(1 for conn in self.connections.values()
                                   if conn.transport_type == transport)
                for transport in TransportType
            }
        }


class TransportManager:
    """Main transport manager"""

    def __init__(self, transport_type: str = "websocket"):
        self.transport_type = TransportType(transport_type)
        self.logger = logging.getLogger(__name__)

        # Initialize components
        self.connection_manager = ConnectionManager()
        self.websocket_handler = None
        self.sse_handler = None

        # Event handlers
        self.event_handlers: Dict[str, List] = {}

        # Running state
        self.running = False

    async def initialize(self):
        """Initialize transport manager"""
        self.logger.info("Initializing Transport Manager...")

        # Initialize connection manager
        await self.connection_manager.start()

        # Initialize transport handlers
        if self.transport_type in [TransportType.WEBSOCKET, TransportType.HYBRID]:
            await self._initialize_websocket()

        if self.transport_type in [TransportType.SSE, TransportType.HYBRID]:
            await self._initialize_sse()

        # Set up event handlers
        self._setup_event_handlers()

        self.logger.info("Transport Manager initialized successfully")

    async def start(self):
        """Start transport manager"""
        self.logger.info("Starting Transport Manager...")
        self.running = True

        # Start transport handlers
        if self.websocket_handler:
            await self.websocket_handler.start()

        if self.sse_handler:
            await self.sse_handler.start()

        self.logger.info("Transport Manager started successfully")

    async def stop(self):
        """Stop transport manager"""
        self.logger.info("Stopping Transport Manager...")

        self.running = False

        # Stop transport handlers
        if self.websocket_handler:
            await self.websocket_handler.stop()

        if self.sse_handler:
            await self.sse_handler.stop()

        # Stop connection manager
        await self.connection_manager.stop()

        self.logger.info("Transport Manager stopped successfully")

    async def _initialize_websocket(self):
        """Initialize WebSocket handler"""
        self.websocket_handler = WebSocketHandler("ws://localhost:8080")

        # Set up event handlers
        self.websocket_handler.event_handlers = {
            "message_received": self._on_websocket_message,
            "connection_established": self._on_websocket_connected,
            "connection_lost": self._on_websocket_disconnected
        }

    async def _initialize_sse(self):
        """Initialize SSE handler"""
        self.sse_handler = SSEHandler("http://localhost:8081")

        # Set up event handlers
        self.sse_handler.event_handlers = {
            "message_received": self._on_sse_message,
            "connection_established": self._on_sse_connected,
            "connection_lost": self._on_sse_disconnected
        }

    def _setup_event_handlers(self):
        """Set up event handlers"""
        self.event_handlers = {
            "message_received": self._on_message_received,
            "connection_established": self._on_connection_established,
            "connection_lost": self._on_connection_lost,
            "reconnect": self._on_reconnect
        }

    async def send(self, message: Dict[str, Any]) -> bool:
        """Send message through transport"""
        try:
            # Add timestamp to message
            message["timestamp"] = datetime.now().isoformat()

            # Route message based on transport type
            if self.transport_type == TransportType.WEBSOCKET:
                return await self.websocket_handler.send_message(message)
            elif self.transport_type == TransportType.SSE:
                await self.sse_handler.broadcast_event(message)
                return True
            elif self.transport_type == TransportType.HYBRID:
                # Send to both transports
                ws_success = await self.websocket_handler.send_message(message)
                await self.sse_handler.broadcast_event(message)
                return ws_success

            return False

        except Exception as e:
            self.logger.error(f"Error sending message: {e}")
            return False

    async def reconnect(self):
        """Reconnect to transport"""
        self.logger.info("Attempting to reconnect...")

        try:
            # Stop current connections
            if self.websocket_handler:
                await self.websocket_handler.stop()

            if self.sse_handler:
                await self.sse_handler.stop()

            # Restart transport handlers
            await self.start()

            self.logger.info("Reconnected successfully")

        except Exception as e:
            self.logger.error(f"Error reconnecting: {e}")
            raise

    async def _on_message_received(self, message: Dict[str, Any]):
        """Handle message received event"""
        # Emit to event handlers
        if "message_received" in self.event_handlers:
            for handler in self.event_handlers["message_received"]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(message)
                    else:
                        handler(message)
                except Exception as e:
                    self.logger.error(f"Error in message handler: {e}")

    async def _on_connection_established(self, connection_info: Dict[str, Any]):
        """Handle connection established event"""
        self.logger.info(f"Connection established: {connection_info}")

        # Emit to event handlers
        if "connection_established" in self.event_handlers:
            for handler in self.event_handlers["connection_established"]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(connection_info)
                    else:
                        handler(connection_info)
                except Exception as e:
                    self.logger.error(f"Error in connection handler: {e}")

    async def _on_connection_lost(self, connection_info: Dict[str, Any]):
        """Handle connection lost event"""
        self.logger.warning(f"Connection lost: {connection_info}")

        # Emit to event handlers
        if "connection_lost" in self.event_handlers:
            for handler in self.event_handlers["connection_lost"]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(connection_info)
                    else:
                        handler(connection_info)
                except Exception as e:
                    self.logger.error(f"Error in connection handler: {e}")

    async def _on_reconnect(self, connection_info: Dict[str, Any]):
        """Handle reconnect event"""
        self.logger.info(f"Reconnected: {connection_info}")

        # Emit to event handlers
        if "reconnect" in self.event_handlers:
            for handler in self.event_handlers["reconnect"]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(connection_info)
                    else:
                        handler(connection_info)
                except Exception as e:
                    self.logger.error(f"Error in reconnect handler: {e}")

    # Transport-specific event handlers
    async def _on_websocket_message(self, message: Dict[str, Any]):
        """Handle WebSocket message"""
        message["transport_type"] = "websocket"
        await self._on_message_received(message)

    async def _on_websocket_connected(self, connection_info: Dict[str, Any]):
        """Handle WebSocket connection"""
        await self._on_connection_established(connection_info)

    async def _on_websocket_disconnected(self, connection_info: Dict[str, Any]):
        """Handle WebSocket disconnection"""
        await self._on_connection_lost(connection_info)

    async def _on_sse_message(self, message: Dict[str, Any]):
        """Handle SSE message"""
        message["transport_type"] = "sse"
        await self._on_message_received(message)

    async def _on_sse_connected(self, connection_info: Dict[str, Any]):
        """Handle SSE connection"""
        await self._on_connection_established(connection_info)

    async def _on_sse_disconnected(self, connection_info: Dict[str, Any]):
        """Handle SSE disconnection"""
        await self._on_connection_lost(connection_info)

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

    def get_stats(self) -> Dict[str, Any]:
        """Get transport statistics"""
        stats = {
            "transport_type": self.transport_type.value,
            "running": self.running,
            "connection_stats": self.connection_manager.get_connection_stats()
        }

        if self.websocket_handler:
            stats["websocket_connections"] = self.websocket_handler.get_connection_count()

        if self.sse_handler:
            stats["sse_clients"] = self.sse_handler.get_client_count()

        return stats