#!/usr/bin/env python3
"""
API Usage Example for A2A Bridge

This example demonstrates how to use the REST API for managing A2A bridge operations,
including agent management, workflow monitoring, and system administration.

Usage:
    python api_usage.py
"""

import asyncio
import aiohttp
import json
import logging
from datetime import datetime
from typing import Dict, Any, List

from elrmcp_bridge.src.bridge import A2ABridge
from elrmcp_bridge.src.config import BridgeConfig


class A2ABridgeClient:
    """Client for A2A Bridge API"""

    def __init__(self, base_url: str = "http://localhost:8001", api_key: str = None):
        self.base_url = base_url
        self.api_key = api_key
        self.session = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.session.close()

    async def _request(self, method: str, endpoint: str, data: Dict[str, Any] = None) -> Dict[str, Any]:
        """Make API request"""
        headers = {}
        if self.api_key:
            headers["X-API-Key"] = self.api_key

        url = f"{self.base_url}{endpoint}"

        if method.upper() == "GET":
            async with self.session.get(url, headers=headers) as response:
                return await response.json()
        elif method.upper() == "POST":
            async with self.session.post(url, headers=headers, json=data) as response:
                return await response.json()
        elif method.upper() == "PUT":
            async with self.session.put(url, headers=headers, json=data) as response:
                return await response.json()
        elif method.upper() == "DELETE":
            async with self.session.delete(url, headers=headers) as response:
                return await response.json()
        else:
            raise ValueError(f"Unsupported HTTP method: {method}")

    async def health_check(self) -> Dict[str, Any]:
        """Health check"""
        return await self._request("GET", "/health")

    async def bridge_status(self) -> Dict[str, Any]:
        """Get bridge status"""
        return await self._request("GET", "/bridge/status")

    async def list_agents(self) -> Dict[str, Any]:
        """List all agents"""
        return await self._request("GET", "/agents")

    async def get_agent(self, agent_id: str) -> Dict[str, Any]:
        """Get specific agent"""
        return await self._request("GET", f"/agents/{agent_id}")

    async def register_agent(self, agent_data: Dict[str, Any]) -> Dict[str, Any]:
        """Register a new agent"""
        return await self._request("POST", "/agents", agent_data)

    async def update_agent_status(self, agent_id: str, status: str) -> Dict[str, Any]:
        """Update agent status"""
        data = {"status": status}
        return await self._request("PUT", f"/agents/{agent_id}/status", data)

    async def list_workflows(self) -> Dict[str, Any]:
        """List all workflows"""
        return await self._request("GET", "/workflows")

    async def get_workflow(self, workflow_id: str) -> Dict[str, Any]:
        """Get specific workflow"""
        return await self._request("GET", f"/workflows/{workflow_id}")

    async def start_workflow(self, workflow_config: Dict[str, Any]) -> Dict[str, Any]:
        """Start a new workflow"""
        data = {"workflow_config": workflow_config}
        return await self._request("POST", "/workflows", data)

    async def cancel_workflow(self, workflow_id: str) -> Dict[str, Any]:
        """Cancel a workflow"""
        return await self._request("PUT", f"/workflows/{workflow_id}/status", {"status": "cancelled"})

    async def get_workflow_logs(self, workflow_id: str) -> Dict[str, Any]:
        """Get workflow logs"""
        return await self._request("GET", f"/workflows/{workflow_id}/logs")

    async def get_metrics(self) -> Dict[str, Any]:
        """Get system metrics"""
        return await self._request("GET", "/metrics")

    async def system_info(self) -> Dict[str, Any]:
        """Get system information"""
        return await self._request("GET", "/system/info")

    async def get_config(self) -> Dict[str, Any]:
        """Get current configuration"""
        return await self._request("GET", "/config")

    async def update_config(self, key: str, value: Any) -> Dict[str, Any]:
        """Update configuration"""
        data = {key: value}
        return await self._request("PUT", f"/config/{key}", data)

    async def system_logs(self) -> Dict[str, Any]:
        """Get system logs"""
        return await self._request("GET", "/system/logs")


async def demonstrate_api_operations():
    """Demonstrate API operations"""
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    logger.info("Starting A2A Bridge API usage example...")

    # Start the A2A bridge in background
    config = BridgeConfig(
        host="localhost",
        port=8001,
        debug=True,
        development=True,
        security_api_key="demo-api-key"
    )

    bridge = A2ABridge(config)

    # Start bridge in background task
    bridge_task = asyncio.create_task(bridge.start())

    try:
        # Wait for bridge to start
        await asyncio.sleep(2)

        # Create API client
        async with A2ABridgeClient("http://localhost:8001", "demo-api-key") as client:
            logger.info("=== API Demo Started ===")

            # 1. Health check
            logger.info("1. Performing health check...")
            health = await client.health_check()
            logger.info(f"Health status: {health['status']}")

            # 2. Bridge status
            logger.info("\n2. Getting bridge status...")
            status = await client.bridge_status()
            logger.info(f"Bridge state: {status['state']}")
            logger.info(f"Uptime: {status['uptime']:.2f} seconds")

            # 3. System information
            logger.info("\n3. Getting system information...")
            system_info = await client.system_info()
            logger.info(f"Platform: {system_info['platform']}")
            logger.info(f"Python version: {system_info['python_version']}")

            # 4. Agent management
            logger.info("\n4. Agent management...")

            # List agents initially
            agents = await client.list_agents()
            logger.info(f"Initial agents: {len(agents['agents'])}")

            # Register a new agent
            new_agent = {
                "agent_id": "demo-agent-1",
                "name": "Demo Agent",
                "version": "1.0.0",
                "capabilities": ["file_operations", "data_processing"],
                "endpoints": {
                    "a2a": "http://localhost:9090",
                    "websocket": "ws://localhost:9090/ws"
                },
                "metadata": {
                    "type": "demo",
                    "purpose": "testing"
                }
            }

            logger.info(f"Registering agent: {new_agent['agent_id']}")
            register_result = await client.register_agent(new_agent)
            logger.info(f"Registration result: {register_result}")

            # List agents again
            agents = await client.list_agents()
            logger.info(f"Agents after registration: {len(agents['agents'])}")

            # Get specific agent
            agent = await client.get_agent("demo-agent-1")
            logger.info(f"Agent details: {agent}")

            # 5. Workflow management
            logger.info("\n5. Workflow management...")

            # List workflows initially
            workflows = await client.list_workflows()
            logger.info(f"Initial workflows: {len(workflows.get('running_workflows', []))}")

            # Start a simple workflow
            workflow_config = {
                "workflow_id": "api-demo-workflow",
                "name": "API Demo Workflow",
                "description": "Workflow created via API",
                "tasks": [
                    {
                        "task_id": "task-1",
                        "name": "collect_data",
                        "type": "agent",
                        "parameters": {
                            "source": "demo-data",
                            "limit": 100
                        }
                    },
                    {
                        "task_id": "task-2",
                        "name": "process_data",
                        "type": "agent",
                        "parameters": {
                            "data": "{{task-1.result}}"
                        },
                        "dependencies": ["task-1"]
                    }
                ]
            }

            logger.info("Starting demo workflow...")
            workflow_result = await client.start_workflow(workflow_config)
            workflow_id = workflow_result['workflow_id']
            logger.info(f"Workflow started: {workflow_id}")

            # Monitor workflow progress
            for i in range(5):
                workflow = await client.get_workflow(workflow_id)
                logger.info(f"Workflow status: {workflow['status']}")

                if workflow['status'] in ['completed', 'failed']:
                    break

                await asyncio.sleep(2)

            # Get workflow logs
            logs = await client.get_workflow_logs(workflow_id)
            logger.info(f"Workflow logs: {len(logs['logs'])} entries")

            # 6. Metrics and monitoring
            logger.info("\n6. Metrics and monitoring...")

            # Get system metrics
            metrics = await client.get_metrics()
            logger.info(f"Bridge metrics: {metrics['bridge_metrics']['metrics']['total_messages_processed']}")
            logger.info(f"Protocol metrics: {metrics['protocol_metrics']['messages_translated']}")

            # Get current configuration
            config = await client.get_config()
            logger.info(f"Config: {config['bridge']['host']}:{config['bridge']['port']}")

            # 7. Advanced operations
            logger.info("\n7. Advanced operations...")

            # Update configuration
            update_result = await client.update_config("debug", True)
            logger.info(f"Config update result: {update_result}")

            # Update agent status
            status_result = await client.update_agent_status("demo-agent-1", "active")
            logger.info(f"Agent status update: {status_result}")

            # 8. System administration
            logger.info("\n8. System administration...")

            # Get system logs
            system_logs = await client.system_logs()
            logger.info(f"System logs: {len(system_logs['logs'])} entries")

            # Comprehensive demo
            logger.info("\n=== Comprehensive Demo ===")
            logger.info("Running comprehensive API operations...")

            # Demonstrate error handling
            try:
                await client.get_agent("non-existent-agent")
            except Exception as e:
                logger.info(f"Error handling works: {e}")

            # Demonstrate concurrent operations
            logger.info("Testing concurrent operations...")
            tasks = []
            for i in range(3):
                task = client.start_workflow({
                    "workflow_id": f"concurrent-workflow-{i}",
                    "name": f"Concurrent Workflow {i}",
                    "description": "Workflow for concurrency test",
                    "tasks": [
                        {
                            "task_id": f"task-{i}-1",
                            "name": "simple_task",
                            "type": "agent",
                            "parameters": {"iteration": i}
                        }
                    ]
                })
                tasks.append(task)

            results = await asyncio.gather(*tasks)
            logger.info(f"Concurrent workflow results: {len(results)} workflows started")

            # Wait for workflows to complete
            await asyncio.sleep(5)

            # Check final workflow statuses
            for i in range(3):
                workflow_id = f"concurrent-workflow-{i}"
                workflow = await client.get_workflow(workflow_id)
                logger.info(f"Workflow {i} status: {workflow['status']}")

            logger.info("=== API Demo Completed Successfully ===")

    except Exception as e:
        logger.error(f"Error in API demo: {e}")
    finally:
        # Stop bridge
        await bridge.stop()
        if bridge_task:
            bridge_task.cancel()
            try:
                await bridge_task
            except asyncio.CancelledError:
                pass


async def main():
    """Main application"""
    await demonstrate_api_operations()


if __name__ == "__main__":
    asyncio.run(main())