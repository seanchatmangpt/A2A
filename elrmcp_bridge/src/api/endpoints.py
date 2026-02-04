"""API Endpoints

This module provides specific API endpoints for A2A bridge operations,
including agent management, workflow monitoring, and system administration.
"""

from .server import APIError, APIServer
from ..agents import AgentManager
from ..workflows import WorkflowOrchestrator


class AgentEndpoints:
    """Agent management endpoints"""

    @staticmethod
    async def list_agents(request):
        """List all agents"""
        bridge = request.bridge
        try:
            agents = await bridge.agent_manager.get_agent_status()
            return agents
        except Exception as e:
            raise APIError(f"Failed to list agents: {str(e)}", 500)

    @staticmethod
    async def get_agent(request):
        """Get specific agent information"""
        bridge = request.bridge
        agent_id = request.match_info.get("agent_id")
        try:
            agent = await bridge.get_agent_status(agent_id)
            return agent
        except Exception as e:
            raise APIError(f"Failed to get agent: {str(e)}", 500)

    @staticmethod
    async def register_agent(request):
        """Register a new agent"""
        bridge = request.bridge
        try:
            data = await request.json()

            # Create agent info from request data
            agent_info = {
                "agent_id": data.get("agent_id", f"agent-{uuid.uuid4()}"),
                "name": data.get("name", "Unknown Agent"),
                "version": data.get("version", "1.0.0"),
                "capabilities": data.get("capabilities", []),
                "endpoints": data.get("endpoints", {}),
                "metadata": data.get("metadata", {})
            }

            # Register agent
            await bridge.agent_manager._register_agent(agent_info)

            return {
                "success": True,
                "agent_id": agent_info["agent_id"],
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to register agent: {str(e)}", 500)

    @staticmethod
    async def update_agent(request):
        """Update agent information"""
        bridge = request.bridge
        agent_id = request.match_info.get("agent_id")
        try:
            data = await request.json()

            # Update agent
            agent_info = {
                "agent_id": agent_id,
                "name": data.get("name"),
                "version": data.get("version"),
                "capabilities": data.get("capabilities", []),
                "endpoints": data.get("endpoints", {}),
                "metadata": data.get("metadata", {})
            }

            await bridge.agent_manager._register_agent(agent_info)

            return {
                "success": True,
                "agent_id": agent_id,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to update agent: {str(e)}", 500)

    @staticmethod
    async def delete_agent(request):
        """Delete an agent"""
        bridge = request.bridge
        agent_id = request.match_info.get("agent_id")
        try:
            await bridge.agent_manager.unregister_agent(agent_id)

            return {
                "success": True,
                "agent_id": agent_id,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to delete agent: {str(e)}", 500)

    @staticmethod
    async def send_agent_message(request):
        """Send message to agent"""
        bridge = request.bridge
        agent_id = request.match_info.get("agent_id")
        try:
            data = await request.json()
            message = data.get("message")

            if not message:
                raise APIError("Message is required", 400)

            response = await bridge.send_to_agent(agent_id, message)

            return {
                "success": True,
                "agent_id": agent_id,
                "response": response,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to send message to agent: {str(e)}", 500)

    @staticmethod
    async def get_agents_by_capability(request):
        """Get agents by capability"""
        bridge = request.bridge
        query_params = request.query
        capability = query_params.get("capability")

        if not capability:
            raise APIError("Capability parameter is required", 400)

        try:
            agents = await bridge.agent_manager.get_agents_by_capability(capability)

            return {
                "capability": capability,
                "agents": [agent.to_dict() for agent in agents],
                "count": len(agents),
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to get agents by capability: {str(e)}", 500)


class WorkflowEndpoints:
    """Workflow management endpoints"""

    @staticmethod
    async def list_workflows(request):
        """List all workflows"""
        bridge = request.bridge
        try:
            workflows = await bridge.workflow_orchestrator.get_workflow_status()
            return workflows
        except Exception as e:
            raise APIError(f"Failed to list workflows: {str(e)}", 500)

    @staticmethod
    async def get_workflow(request):
        """Get specific workflow information"""
        bridge = request.bridge
        workflow_id = request.match_info.get("workflow_id")
        try:
            workflow = await bridge.workflow_orchestrator.get_workflow_status(workflow_id)
            return workflow
        except Exception as e:
            raise APIError(f"Failed to get workflow: {str(e)}", 500)

    @staticmethod
    async def start_workflow(request):
        """Start a new workflow"""
        bridge = request.bridge
        try:
            data = await request.json()
            workflow_config = data.get("workflow_config")

            if not workflow_config:
                raise APIError("Workflow configuration is required", 400)

            workflow_id = await bridge.start_workflow(workflow_config)

            return {
                "success": True,
                "workflow_id": workflow_id,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to start workflow: {str(e)}", 500)

    @staticmethod
    async def cancel_workflow(request):
        """Cancel a workflow"""
        bridge = request.bridge
        workflow_id = request.match_info.get("workflow_id")
        try:
            # Get workflow first
            workflow = await bridge.workflow_orchestrator.get_workflow_status(workflow_id)

            if workflow.get("status") == "cancelled":
                return {"message": "Workflow already cancelled"}

            # Cancel workflow
            await bridge.workflow_orchestrator._cancel_workflow(workflow_id, workflow)

            return {
                "success": True,
                "workflow_id": workflow_id,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to cancel workflow: {str(e)}", 500)

    @staticmethod
    async def get_workflow_logs(request):
        """Get workflow execution logs"""
        bridge = request.bridge
        workflow_id = request.match_info.get("workflow_id")
        try:
            # Mock workflow logs - in real implementation, this would read from logs
            logs = [
                {
                    "timestamp": datetime.now().isoformat(),
                    "level": "INFO",
                    "message": f"Workflow {workflow_id} started",
                    "component": "workflow-orchestrator"
                },
                {
                    "timestamp": datetime.now().isoformat(),
                    "level": "DEBUG",
                    "message": "Task execution in progress",
                    "component": "task-executor"
                }
            ]

            return {
                "workflow_id": workflow_id,
                "logs": logs,
                "count": len(logs),
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to get workflow logs: {str(e)}", 500)


class SystemEndpoints:
    """System management endpoints"""

    @staticmethod
    async def get_system_info(request):
        """Get system information"""
        bridge = request.bridge
        try:
            import platform
            import psutil

            system_info = {
                "bridge": {
                    "state": bridge.state.value,
                    "uptime": (datetime.now() - bridge.start_time).total_seconds(),
                    "total_messages_processed": bridge.metrics.total_messages_processed,
                    "total_workflows_completed": bridge.metrics.total_workflows_completed,
                    "total_agents_discovered": bridge.metrics.total_agents_discovered
                },
                "system": {
                    "platform": platform.platform(),
                    "python_version": platform.python_version(),
                    "cpu_count": psutil.cpu_count(),
                    "memory_total": psutil.virtual_memory().total,
                    "memory_available": psutil.virtual_memory().available,
                    "disk_usage": psutil.disk_usage('/').percent
                },
                "timestamp": datetime.now().isoformat()
            }

            return system_info
        except Exception as e:
            raise APIError(f"Failed to get system info: {str(e)}", 500)

    @staticmethod
    async def get_health_check(request):
        """Comprehensive health check"""
        bridge = request.bridge
        try:
            health = {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "components": {
                    "bridge": {
                        "status": bridge.state.value,
                        "healthy": bridge.state == bridge.state.READY
                    },
                    "agent_manager": {
                        "status": "healthy",
                        "active_agents": len(bridge.agent_manager.get_active_agents())
                    },
                    "workflow_orchestrator": {
                        "status": "healthy",
                        "running_workflows": len(bridge.workflow_orchestrator.running_workflows)
                    },
                    "transport": {
                        "status": "healthy",
                        "connection_stats": bridge.transport.get_stats()
                    }
                }
            }

            # Overall health status
            if not all(comp["healthy"] for comp in health["components"].values()):
                health["status"] = "degraded"

            return health
        except Exception as e:
            raise APIError(f"Failed to perform health check: {str(e)}", 500)

    @staticmethod
    async def get_metrics(request):
        """Get all system metrics"""
        bridge = request.bridge
        try:
            metrics = {
                "bridge_metrics": await bridge.get_bridge_metrics(),
                "protocol_metrics": bridge.protocol.get_metrics(),
                "transport_metrics": bridge.transport.get_stats(),
                "timestamp": datetime.now().isoformat()
            }

            return metrics
        except Exception as e:
            raise APIError(f"Failed to get metrics: {str(e)}", 500)

    @staticmethod
    async def shutdown(request):
        """Graceful shutdown"""
        bridge = request.bridge
        try:
            await bridge.stop()

            return {
                "success": True,
                "message": "System shutdown initiated",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to shutdown system: {str(e)}", 500)

    @staticmethod
    async def restart(request):
        """Restart the system"""
        bridge = request.bridge
        try:
            await bridge.stop()
            await bridge.start()

            return {
                "success": True,
                "message": "System restarted successfully",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to restart system: {str(e)}", 500)

    @staticmethod
    async def export_config(request):
        """Export current configuration"""
        bridge = request.bridge
        try:
            config = {
                "bridge_config": bridge.config.__dict__,
                "timestamp": datetime.now().isoformat()
            }

            return config
        except Exception as e:
            raise APIError(f"Failed to export configuration: {str(e)}", 500)

    @staticmethod
    async def import_config(request):
        """Import new configuration"""
        bridge = request.bridge
        try:
            data = await request.json()
            config_data = data.get("config")

            if not config_data:
                raise APIError("Configuration data is required", 400)

            # Update configuration (this would need validation)
            bridge.config.update(config_data)

            return {
                "success": True,
                "message": "Configuration imported successfully",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            raise APIError(f"Failed to import configuration: {str(e)}", 500)