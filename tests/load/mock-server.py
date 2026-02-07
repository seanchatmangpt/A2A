#!/usr/bin/env python3
"""
Mock A2A API Server for Load Testing
Simulates all A2A API endpoints for performance testing
"""

import asyncio
import json
import random
import time
from datetime import datetime
from aiohttp import web
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Simulated data store
AGENTS = {}
WORKFLOWS = {}
METRICS = {
    "total_requests": 0,
    "total_agents_discovered": 0,
    "total_workflows_completed": 0,
    "total_messages_processed": 0
}
START_TIME = time.time()


async def health_check(request):
    """Health check endpoint"""
    METRICS["total_requests"] += 1
    return web.json_response({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0"
    })


async def bridge_status(request):
    """Bridge status endpoint"""
    METRICS["total_requests"] += 1
    return web.json_response({
        "state": "ready",
        "uptime": time.time() - START_TIME,
        "metrics": METRICS
    })


async def list_agents(request):
    """List all agents"""
    METRICS["total_requests"] += 1
    agents = list(AGENTS.values())
    return web.json_response(agents)


async def get_agent(request):
    """Get specific agent"""
    METRICS["total_requests"] += 1
    agent_id = request.match_info.get("agent_id")
    agent = AGENTS.get(agent_id)

    if not agent:
        return web.json_response({"error": "Agent not found"}, status=404)

    return web.json_response(agent)


async def register_agent(request):
    """Register a new agent"""
    METRICS["total_requests"] += 1

    try:
        data = await request.json()
        agent_id = data.get("agent_id", f"agent-{random.randint(1000, 9999)}")

        agent = {
            "agent_id": agent_id,
            "name": data.get("name", "Unknown Agent"),
            "version": data.get("version", "1.0.0"),
            "capabilities": data.get("capabilities", []),
            "endpoints": data.get("endpoints", {}),
            "metadata": data.get("metadata", {}),
            "status": "active",
            "registered_at": datetime.now().isoformat()
        }

        AGENTS[agent_id] = agent
        METRICS["total_agents_discovered"] += 1

        return web.json_response({
            "success": True,
            "agent_id": agent_id,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return web.json_response({"error": str(e)}, status=400)


async def update_agent_status(request):
    """Update agent status"""
    METRICS["total_requests"] += 1
    agent_id = request.match_info.get("agent_id")

    try:
        data = await request.json()
        status = data.get("status")

        if agent_id in AGENTS:
            AGENTS[agent_id]["status"] = status
            AGENTS[agent_id]["updated_at"] = datetime.now().isoformat()

        return web.json_response({
            "success": True,
            "agent_id": agent_id,
            "status": status,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return web.json_response({"error": str(e)}, status=400)


async def list_workflows(request):
    """List all workflows"""
    METRICS["total_requests"] += 1
    workflows = list(WORKFLOWS.values())
    return web.json_response(workflows)


async def get_workflow(request):
    """Get specific workflow"""
    METRICS["total_requests"] += 1
    workflow_id = request.match_info.get("workflow_id")
    workflow = WORKFLOWS.get(workflow_id)

    if not workflow:
        return web.json_response({"error": "Workflow not found"}, status=404)

    return web.json_response(workflow)


async def start_workflow(request):
    """Start a new workflow"""
    METRICS["total_requests"] += 1

    try:
        data = await request.json()
        workflow_config = data.get("workflow_config", {})
        workflow_id = workflow_config.get("workflow_id", f"workflow-{random.randint(1000, 9999)}")

        workflow = {
            "workflow_id": workflow_id,
            "name": workflow_config.get("name", "Unknown Workflow"),
            "status": "running",
            "steps": workflow_config.get("steps", []),
            "started_at": datetime.now().isoformat(),
            "progress": random.randint(10, 50)
        }

        WORKFLOWS[workflow_id] = workflow
        METRICS["total_workflows_completed"] += 1

        return web.json_response({
            "success": True,
            "workflow_id": workflow_id,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return web.json_response({"error": str(e)}, status=400)


async def update_workflow_status(request):
    """Update workflow status"""
    METRICS["total_requests"] += 1
    workflow_id = request.match_info.get("workflow_id")

    try:
        data = await request.json()
        status = data.get("status")

        if workflow_id in WORKFLOWS:
            WORKFLOWS[workflow_id]["status"] = status
            WORKFLOWS[workflow_id]["updated_at"] = datetime.now().isoformat()

        return web.json_response({
            "success": True,
            "workflow_id": workflow_id,
            "status": status,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return web.json_response({"error": str(e)}, status=400)


async def get_metrics(request):
    """Get system metrics"""
    METRICS["total_requests"] += 1
    METRICS["total_messages_processed"] = METRICS["total_requests"]

    return web.json_response({
        "bridge_metrics": METRICS,
        "protocol_metrics": {
            "messages_sent": METRICS["total_messages_processed"],
            "messages_received": METRICS["total_messages_processed"],
            "avg_latency": random.uniform(10, 100)
        },
        "timestamp": datetime.now().isoformat()
    })


async def get_config(request):
    """Get current configuration"""
    METRICS["total_requests"] += 1
    config = {
        "bridge": {
            "host": "localhost",
            "port": 8001,
            "debug": False,
            "max_connections": 1000,
            "timeout": 30
        },
        "system": {
            "host": "localhost",
            "port": 8001,
            "debug": False,
            "max_connections": 1000,
            "timeout": 30,
            "enable_cors": True,
            "auth_required": False
        }
    }
    return web.json_response(config)


async def update_config(request):
    """Update configuration"""
    METRICS["total_requests"] += 1
    key = request.match_info.get("key")

    try:
        data = await request.json()

        return web.json_response({
            "success": True,
            "key": key,
            "value": data,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        return web.json_response({"error": str(e)}, status=400)


async def system_info(request):
    """Get system information"""
    METRICS["total_requests"] += 1

    system_info = {
        "platform": "linux",
        "python_version": "3.11.0",
        "cpu_count": 8,
        "memory_total": 16777216000,
        "memory_available": 8388608000,
        "disk_usage": 45.2,
        "uptime": time.time() - START_TIME,
        "timestamp": datetime.now().isoformat()
    }

    return web.json_response(system_info)


async def get_logs(request):
    """Get system logs"""
    METRICS["total_requests"] += 1

    logs = [
        {
            "timestamp": datetime.now().isoformat(),
            "level": "INFO",
            "message": "Mock API server processing requests",
            "component": "api-server"
        },
        {
            "timestamp": datetime.now().isoformat(),
            "level": "DEBUG",
            "message": f"Total requests processed: {METRICS['total_requests']}",
            "component": "metrics"
        }
    ]

    return web.json_response({
        "logs": logs,
        "count": len(logs),
        "timestamp": datetime.now().isoformat()
    })


async def dashboard(request):
    """Web dashboard"""
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>A2A Mock Server</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; }
            h1 { color: #333; }
            .status { color: #28a745; font-weight: bold; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>A2A Mock API Server</h1>
            <p class="status">Status: Running</p>
            <p>This is a mock server for load testing the A2A protocol.</p>
        </div>
    </body>
    </html>
    """
    return web.Response(text=html, content_type='text/html')


def create_app():
    """Create and configure the application"""
    app = web.Application()

    # Add routes
    app.router.add_get("/", dashboard)
    app.router.add_get("/health", health_check)
    app.router.add_get("/bridge/status", bridge_status)

    # Agent endpoints
    app.router.add_get("/agents", list_agents)
    app.router.add_post("/agents", register_agent)
    app.router.add_get("/agents/{agent_id}", get_agent)
    app.router.add_post("/agents/{agent_id}/status", update_agent_status)

    # Workflow endpoints
    app.router.add_get("/workflows", list_workflows)
    app.router.add_post("/workflows", start_workflow)
    app.router.add_get("/workflows/{workflow_id}", get_workflow)
    app.router.add_post("/workflows/{workflow_id}/status", update_workflow_status)

    # System endpoints
    app.router.add_get("/metrics", get_metrics)
    app.router.add_get("/config", get_config)
    app.router.add_post("/config/{key}", update_config)
    app.router.add_get("/system/info", system_info)
    app.router.add_get("/system/logs", get_logs)

    return app


async def main():
    """Main entry point"""
    logger.info("Starting A2A Mock API Server...")

    app = create_app()
    runner = web.AppRunner(app)
    await runner.setup()

    site = web.TCPSite(runner, "0.0.0.0", 8001)
    await site.start()

    logger.info("Mock API Server running on http://0.0.0.0:8001")
    logger.info("Ready for load testing!")

    # Keep the server running
    try:
        while True:
            await asyncio.sleep(3600)
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
