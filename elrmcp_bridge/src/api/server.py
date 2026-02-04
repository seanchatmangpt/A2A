"""REST API Server

This module provides a comprehensive REST API for managing A2A bridge operations,
including agent management, workflow monitoring, metrics collection, and system administration.
"""

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional, Type, Union
from enum import Enum

import aiohttp
from aiohttp import web
import uvloop

from ..config import BridgeConfig


@dataclass
class APIServerConfig:
    """API server configuration"""
    host: str = "localhost"
    port: int = 8001
    debug: bool = False
    max_connections: int = 1000
    timeout: int = 30
    enable_cors: bool = True
    auth_required: bool = False
    api_key: Optional[str] = None

    def __post_init__(self):
        if self.api_key and not self.auth_required:
            self.auth_required = True


class APIError(Exception):
    """API error"""
    def __init__(self, message: str, code: int = 400, details: Dict[str, Any] = None):
        super().__init__(message)
        self.code = code
        self.details = details or {}


class APIServer:
    """REST API server for A2A bridge management"""

    def __init__(self, bridge, config: APIServerConfig = None):
        self.bridge = bridge
        self.config = config or APIServerConfig()
        self.logger = logging.getLogger(__name__)
        self.app = None
        self.runner = None
        self.site = None
        self.running = False

        # Initialize endpoints
        self.endpoints = {
            "/health": self._health_check,
            "/bridge/status": self._bridge_status,
            "/agents": self._list_agents,
            "/agents/{agent_id}": self._get_agent,
            "/agents/{agent_id}/status": self._update_agent_status,
            "/workflows": self._list_workflows,
            "/workflows/{workflow_id}": self._get_workflow,
            "/workflows/{workflow_id}/status": self._update_workflow_status,
            "/metrics": self._get_metrics,
            "/config": self._get_config,
            "/config/{key}": self._update_config,
            "/system/info": self._system_info,
            "/system/logs": self._get_logs
        }

    async def start(self):
        """Start API server"""
        self.logger.info(f"Starting API server at {self.config.host}:{self.config.port}")

        # Create application
        self.app = web.Application(
            client_max_size=1024 * 1024 * 10,  # 10MB max payload
            debug=self.config.debug
        )

        # Set up routes
        self._setup_routes()

        # Set up middlewares
        self.app.middlewares.extend([
            self._error_middleware,
            self._logging_middleware,
            self._cors_middleware
        ])

        # Create runner
        self.runner = web.AppRunner(self.app)
        await self.runner.setup()

        # Create site
        self.site = web.TCPSite(self.runner, self.config.host, self.config.port)

        # Start server
        await self.site.start()
        self.running = True

        self.logger.info(f"API server started at {self.config.host}:{self.config.port}")

    async def stop(self):
        """Stop API server"""
        self.logger.info("Stopping API server...")

        self.running = False

        # Stop server
        if self.site:
            await self.site.stop()

        if self.runner:
            await self.runner.cleanup()

        self.logger.info("API server stopped")

    def _setup_routes(self):
        """Setup API routes"""
        for route_path, handler in self.endpoints.items():
            self.app.router.add_route(
                "*", route_path, self._create_handler(handler)
            )

        # Add static files for web dashboard
        self.app.router.add_static(
            "/static",
            path="./static",
            name="static"
        )

        # Add web dashboard
        self.app.router.add_get("/", self._dashboard)

    def _create_handler(self, handler):
        """Create request handler with authentication"""
        async def wrapped_handler(request):
            # Check authentication if required
            if self.config.auth_required:
                await self._authenticate(request)

            # Add request context
            request.bridge = self.bridge
            request.config = self.config

            # Call handler
            return await handler(request)

        return wrapped_handler

    async def _authenticate(self, request):
        """Authenticate request"""
        # Get API key from headers
        api_key = request.headers.get("X-API-Key")
        if not api_key:
            api_key = request.query.get("api_key")

        if not api_key or api_key != self.config.api_key:
            raise APIError("Authentication required", 401)

    async def _health_check(self, request):
        """Health check endpoint"""
        return web.json_response({
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "version": "1.0.0"
        })

    async def _bridge_status(self, request):
        """Get bridge status"""
        try:
            status = await self.bridge.get_bridge_metrics()
            return web.json_response(status)
        except Exception as e:
            raise APIError(f"Failed to get bridge status: {str(e)}", 500)

    async def _list_agents(self, request):
        """List all agents"""
        try:
            agents = await self.bridge.agent_manager.get_agent_status()
            return web.json_response(agents)
        except Exception as e:
            raise APIError(f"Failed to list agents: {str(e)}", 500)

    async def _get_agent(self, request):
        """Get specific agent information"""
        agent_id = request.match_info.get("agent_id")
        try:
            agent = await self.bridge.get_agent_status(agent_id)
            return web.json_response(agent)
        except Exception as e:
            raise APIError(f"Failed to get agent: {str(e)}", 500)

    async def _update_agent_status(self, request):
        """Update agent status"""
        agent_id = request.match_info.get("agent_id")
        try:
            data = await request.json()
            status = data.get("status")

            # Implement status update logic
            # This would involve updating the agent in the bridge

            return web.json_response({
                "success": True,
                "agent_id": agent_id,
                "status": status,
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            raise APIError(f"Failed to update agent status: {str(e)}", 500)

    async def _list_workflows(self, request):
        """List all workflows"""
        try:
            workflows = await self.bridge.workflow_orchestrator.get_workflow_status()
            return web.json_response(workflows)
        except Exception as e:
            raise APIError(f"Failed to list workflows: {str(e)}", 500)

    async def _get_workflow(self, request):
        """Get specific workflow information"""
        workflow_id = request.match_info.get("workflow_id")
        try:
            workflow = await self.bridge.workflow_orchestrator.get_workflow_status(workflow_id)
            return web.json_response(workflow)
        except Exception as e:
            raise APIError(f"Failed to get workflow: {str(e)}", 500)

    async def _update_workflow_status(self, request):
        """Update workflow status"""
        workflow_id = request.match_info.get("workflow_id")
        try:
            data = await request.json()
            status = data.get("status")

            # Implement status update logic
            # This would involve updating the workflow in the orchestrator

            return web.json_response({
                "success": True,
                "workflow_id": workflow_id,
                "status": status,
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            raise APIError(f"Failed to update workflow status: {str(e)}", 500)

    async def _get_metrics(self, request):
        """Get system metrics"""
        try:
            metrics = await self.bridge.get_bridge_metrics()
            protocol_metrics = self.bridge.protocol.get_metrics()

            return web.json_response({
                "bridge_metrics": metrics,
                "protocol_metrics": protocol_metrics,
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            raise APIError(f"Failed to get metrics: {str(e)}", 500)

    async def _get_config(self, request):
        """Get current configuration"""
        try:
            config = {
                "bridge": self.config.__dict__,
                "system": {
                    "host": self.config.host,
                    "port": self.config.port,
                    "debug": self.config.debug,
                    "max_connections": self.config.max_connections,
                    "timeout": self.config.timeout,
                    "enable_cors": self.config.enable_cors,
                    "auth_required": self.config.auth_required
                }
            }
            return web.json_response(config)
        except Exception as e:
            raise APIError(f"Failed to get configuration: {str(e)}", 500)

    async def _update_config(self, request):
        """Update configuration"""
        key = request.match_info.get("key")
        try:
            data = await request.json()

            # Implement configuration update logic
            # This would involve updating the bridge configuration

            return web.json_response({
                "success": True,
                "key": key,
                "value": data,
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            raise APIError(f"Failed to update configuration: {str(e)}", 500)

    async def _system_info(self, request):
        """Get system information"""
        try:
            import platform
            import psutil

            system_info = {
                "platform": platform.platform(),
                "python_version": platform.python_version(),
                "cpu_count": psutil.cpu_count(),
                "memory_total": psutil.virtual_memory().total,
                "memory_available": psutil.virtual_memory().available,
                "disk_usage": psutil.disk_usage('/').percent,
                "timestamp": datetime.now().isoformat()
            }

            return web.json_response(system_info)
        except Exception as e:
            raise APIError(f"Failed to get system info: {str(e)}", 500)

    async def _get_logs(self, request):
        """Get system logs"""
        try:
            logs = []
            # Mock log data - in real implementation, this would read from log files
            log_entry = {
                "timestamp": datetime.now().isoformat(),
                "level": "INFO",
                "message": "Sample log message",
                "component": "api-server"
            }
            logs.append(log_entry)

            return web.json_response({
                "logs": logs,
                "count": len(logs),
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            raise APIError(f"Failed to get logs: {str(e)}", 500)

    async def _dashboard(self, request):
        """Web dashboard"""
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>A2A Bridge Dashboard</title>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: Arial, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #f5f5f5;
                }
                .container {
                    max-width: 1200px;
                    margin: 0 auto;
                    background-color: white;
                    padding: 20px;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }
                .header {
                    text-align: center;
                    margin-bottom: 30px;
                }
                .status {
                    display: inline-block;
                    padding: 5px 10px;
                    border-radius: 4px;
                    font-weight: bold;
                }
                .status.healthy {
                    background-color: #28a745;
                    color: white;
                }
                .status.warning {
                    background-color: #ffc107;
                    color: black;
                }
                .status.error {
                    background-color: #dc3545;
                    color: white;
                }
                .card {
                    background-color: #f8f9fa;
                    padding: 15px;
                    margin: 10px 0;
                    border-radius: 4px;
                    border-left: 4px solid #007bff;
                }
                .metrics {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 15px;
                    margin: 20px 0;
                }
                .metric {
                    background-color: #e9ecef;
                    padding: 15px;
                    border-radius: 4px;
                    text-align: center;
                }
                .metric-value {
                    font-size: 24px;
                    font-weight: bold;
                    color: #007bff;
                }
                .metric-label {
                    font-size: 14px;
                    color: #6c757d;
                }
                .refresh-btn {
                    background-color: #007bff;
                    color: white;
                    padding: 10px 20px;
                    border: none;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 16px;
                }
                .refresh-btn:hover {
                    background-color: #0056b3;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>A2A Bridge Dashboard</h1>
                    <div class="status healthy" id="system-status">System Status: Healthy</div>
                    <br>
                    <button class="refresh-btn" onclick="refreshData()">Refresh Data</button>
                </div>

                <div class="metrics" id="metrics">
                    <div class="metric">
                        <div class="metric-value" id="agent-count">0</div>
                        <div class="metric-label">Active Agents</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value" id="workflow-count">0</div>
                        <div class="metric-label">Running Workflows</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value" id="uptime">0</div>
                        <div class="metric-label">Uptime (s)</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value" id="messages">0</div>
                        <div class="metric-label">Messages Processed</div>
                    </div>
                </div>

                <div class="card">
                    <h2>Recent Logs</h2>
                    <div id="logs">Loading...</div>
                </div>
            </div>

            <script>
                function refreshData() {
                    fetch('/bridge/status')
                        .then(response => response.json())
                        .then(data => {
                            document.getElementById('agent-count').textContent = data.metrics.total_agents_discovered || 0;
                            document.getElementById('workflow-count').textContent = data.metrics.total_workflows_completed || 0;
                            document.getElementById('uptime').textContent = Math.floor(data.uptime || 0);
                            document.getElementById('messages').textContent = data.metrics.total_messages_processed || 0;
                        })
                        .catch(error => console.error('Error:', error));
                }

                function loadLogs() {
                    fetch('/system/logs')
                        .then(response => response.json())
                        .then(data => {
                            const logsDiv = document.getElementById('logs');
                            logsDiv.innerHTML = data.logs.map(log =>
                                `<div>[${log.timestamp}] ${log.level}: ${log.message}</div>`
                            ).join('');
                        })
                        .catch(error => console.error('Error:', error));
                }

                // Load data initially
                refreshData();
                loadLogs();

                // Refresh every 30 seconds
                setInterval(refreshData, 30000);
                setInterval(loadLogs, 60000);
            </script>
        </body>
        </html>
        """
        return web.Response(text=html, content_type='text/html')

    async def _error_middleware(self, request, handler):
        """Error handling middleware"""
        try:
            return await handler(request)
        except APIError as e:
            return web.json_response({
                "error": {
                    "code": e.code,
                    "message": str(e),
                    "details": e.details
                }
            }, status=e.code)
        except Exception as e:
            self.logger.error(f"Unhandled error in API: {e}")
            return web.json_response({
                "error": {
                    "code": 500,
                    "message": "Internal server error"
                }
            }, status=500)

    async def _logging_middleware(self, request, handler):
        """Logging middleware"""
        start_time = datetime.now()
        path = request.path_qs

        try:
            response = await handler(request)
            duration = (datetime.now() - start_time).total_seconds()

            self.logger.info(f"API Request: {request.method} {path} - {response.status} - {duration:.3f}s")
            return response
        except Exception as e:
            duration = (datetime.now() - start_time).total_seconds()
            self.logger.error(f"API Error: {request.method} {path} - {duration:.3f}s - {str(e)}")
            raise

    async def _cors_middleware(self, request, handler):
        """CORS middleware"""
        if not self.config.enable_cors:
            return await handler(request)

        response = await handler(request)

        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type, X-API-Key')

        if request.method == 'OPTIONS':
            return web.Response(status=200)

        return response