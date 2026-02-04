#!/usr/bin/env python3
"""
Basic Usage Example for A2A Bridge

This example demonstrates how to use the A2A bridge to connect elrmcp with Craftplan A2A agents,
enabling seamless agent-to-agent communication and multi-agent workflows.

Usage:
    python basic_usage.py
"""

import asyncio
import logging
from typing import Dict, Any

from elrmcp_bridge.src.bridge import A2ABridge
from elrmcp_bridge.src.config import BridgeConfig


async def main():
    """Main application"""
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    logger.info("Starting A2A Bridge basic usage example...")

    # Create bridge configuration
    config = BridgeConfig(
        host="localhost",
        port=8001,
        debug=True,
        development=True,

        # Configure transport
        bridge_config.transport.type = "websocket",
        bridge_config.transport.websocket_url = "ws://localhost:8080",

        # Configure security
        bridge_config.security.api_key = "demo-key",
        bridge_config.security.auth_required = False,

        # Configure logging
        bridge_config.logging.level = "INFO",
        bridge_config.logging.enable_console = True,
        bridge_config.logging.enable_file = False,

        # Configure metrics
        bridge_config.metrics.enabled = True,
        bridge_config.metrics.port = 8000
    )

    # Create A2A bridge
    bridge = A2ABridge(config)

    try:
        # Start bridge
        await bridge.start()
        logger.info("A2A Bridge started successfully")

        # Get bridge status
        status = await bridge.get_bridge_metrics()
        logger.info(f"Bridge status: {status}")

        # List agents
        agents = await bridge.get_agent_status()
        logger.info(f"Discovered agents: {len(agents['agents'])}")

        # Example: Send message to agent
        if agents['agents']:
            agent_id = list(agents['agents'].keys())[0]
            message = {
                "type": "mcp_request",
                "id": f"msg-{id(message)}",
                "method": "tools/call",
                "params": {
                    "name": "file_read",
                    "arguments": {
                        "path": "/tmp/example.txt"
                    }
                }
            }

            logger.info(f"Sending message to agent {agent_id}: {message['method']}")
            response = await bridge.send_to_agent(agent_id, message)
            logger.info(f"Response: {response}")

        # Example: Start a simple workflow
        workflow_config = {
            "workflow_id": "demo-workflow",
            "name": "Demo Workflow",
            "description": "A simple demonstration workflow",
            "tasks": [
                {
                    "task_id": "task-1",
                    "name": "data-collection",
                    "type": "agent",
                    "parameters": {
                        "source": "demo-data"
                    },
                    "priority": 1
                },
                {
                    "task_id": "task-2",
                    "name": "data-processing",
                    "type": "agent",
                    "dependencies": ["task-1"],
                    "parameters": {
                        "input_data": "{{task-1.result}}"
                    },
                    "priority": 1
                }
            ]
        }

        logger.info("Starting demo workflow...")
        workflow_id = await bridge.start_workflow(workflow_config)
        logger.info(f"Workflow started: {workflow_id}")

        # Wait for workflow to complete
        await asyncio.sleep(5)

        # Get workflow status
        workflow_status = await bridge.get_workflow_status(workflow_id)
        logger.info(f"Workflow status: {workflow_status}")

        # Monitor for a while
        logger.info("Monitoring bridge for 30 seconds...")
        for i in range(30):
            status = await bridge.get_bridge_metrics()
            logger.info(f"Bridge metrics - Messages: {status['metrics']['total_messages_processed']}, "
                       f"Workflows: {status['metrics']['total_workflows_completed']}")
            await asyncio.sleep(1)

    except KeyboardInterrupt:
        logger.info("Shutting down...")
    except Exception as e:
        logger.error(f"Error: {e}")
    finally:
        # Stop bridge
        await bridge.stop()
        logger.info("A2A Bridge stopped")


if __name__ == "__main__":
    asyncio.run(main())