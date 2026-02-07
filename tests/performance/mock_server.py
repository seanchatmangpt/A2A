#!/usr/bin/env python3
"""
Mock API Server for Performance Testing
Provides lightweight mock endpoints for benchmarking
"""

import asyncio
import json
import random
from datetime import datetime
from aiohttp import web
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class MockAPIServer:
    """Mock API server for testing"""

    def __init__(self, host='localhost', port=8001):
        self.host = host
        self.port = port
        self.app = None
        self.runner = None
        self.site = None
        self.request_count = 0
        self.start_time = datetime.now()

    async def health_check(self, request):
        """Mock health check endpoint"""
        self.request_count += 1
        return web.json_response({
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "version": "1.0.0"
        })

    async def bridge_status(self, request):
        """Mock bridge status endpoint"""
        self.request_count += 1
        uptime = (datetime.now() - self.start_time).total_seconds()
        return web.json_response({
            "state": "READY",
            "uptime": uptime,
            "metrics": {
                "total_agents_discovered": random.randint(5, 20),
                "total_workflows_completed": random.randint(10, 50),
                "total_messages_processed": random.randint(100, 1000)
            }
        })

    async def list_agents(self, request):
        """Mock list agents endpoint"""
        self.request_count += 1
        agents = []
        for i in range(random.randint(3, 10)):
            agents.append({
                "agent_id": f"agent-{i}",
                "name": f"Agent {i}",
                "status": "active",
                "capabilities": ["chat", "search"]
            })
        return web.json_response(agents)

    async def list_workflows(self, request):
        """Mock list workflows endpoint"""
        self.request_count += 1
        workflows = []
        for i in range(random.randint(2, 8)):
            workflows.append({
                "workflow_id": f"workflow-{i}",
                "status": random.choice(["running", "completed", "pending"]),
                "created_at": datetime.now().isoformat()
            })
        return web.json_response(workflows)

    async def get_metrics(self, request):
        """Mock metrics endpoint"""
        self.request_count += 1
        return web.json_response({
            "bridge_metrics": {
                "total_messages_processed": random.randint(100, 1000),
                "avg_latency_ms": random.uniform(10, 50),
                "error_rate": random.uniform(0, 0.5)
            },
            "protocol_metrics": {
                "total_requests": self.request_count,
                "success_rate": 99.5
            },
            "timestamp": datetime.now().isoformat()
        })

    async def get_config(self, request):
        """Mock config endpoint"""
        self.request_count += 1
        return web.json_response({
            "bridge": {
                "host": "localhost",
                "port": 8001,
                "debug": False
            },
            "system": {
                "max_connections": 1000,
                "timeout": 30
            }
        })

    async def system_info(self, request):
        """Mock system info endpoint"""
        self.request_count += 1
        return web.json_response({
            "platform": "Linux",
            "python_version": "3.9.0",
            "cpu_count": 4,
            "memory_total": 8589934592,
            "memory_available": 4294967296,
            "disk_usage": random.uniform(30, 70),
            "timestamp": datetime.now().isoformat()
        })

    async def system_logs(self, request):
        """Mock system logs endpoint"""
        self.request_count += 1
        logs = []
        for i in range(5):
            logs.append({
                "timestamp": datetime.now().isoformat(),
                "level": random.choice(["INFO", "DEBUG", "WARNING"]),
                "message": f"Sample log message {i}",
                "component": "api-server"
            })
        return web.json_response({
            "logs": logs,
            "count": len(logs),
            "timestamp": datetime.now().isoformat()
        })

    async def start(self):
        """Start the mock server"""
        self.app = web.Application()

        # Setup routes
        self.app.router.add_get('/health', self.health_check)
        self.app.router.add_get('/bridge/status', self.bridge_status)
        self.app.router.add_get('/agents', self.list_agents)
        self.app.router.add_get('/workflows', self.list_workflows)
        self.app.router.add_get('/metrics', self.get_metrics)
        self.app.router.add_get('/config', self.get_config)
        self.app.router.add_get('/system/info', self.system_info)
        self.app.router.add_get('/system/logs', self.system_logs)

        # Start server
        self.runner = web.AppRunner(self.app)
        await self.runner.setup()
        self.site = web.TCPSite(self.runner, self.host, self.port)
        await self.site.start()

        logger.info(f"Mock API server started at http://{self.host}:{self.port}")

    async def stop(self):
        """Stop the mock server"""
        if self.site:
            await self.site.stop()
        if self.runner:
            await self.runner.cleanup()
        logger.info("Mock API server stopped")


async def main():
    """Main entry point"""
    server = MockAPIServer()
    await server.start()

    logger.info("Server is running. Press Ctrl+C to stop.")

    try:
        # Keep running
        while True:
            await asyncio.sleep(3600)
    except KeyboardInterrupt:
        logger.info("Stopping server...")
        await server.stop()


if __name__ == "__main__":
    asyncio.run(main())
