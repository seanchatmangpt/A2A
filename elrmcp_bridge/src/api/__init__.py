"""Management API Module

This module provides comprehensive REST API for managing A2A bridge operations,
including agent management, workflow monitoring, metrics collection, and system administration.

API Features:
    - Agent discovery and registration
    - Workflow management and monitoring
    - Real-time metrics and health checks
    - Configuration management
    - System administration
    - Web-based dashboard
"""

from .server import APIServer
from .endpoints import AgentEndpoints, WorkflowEndpoints, SystemEndpoints

__all__ = ["APIServer", "AgentEndpoints", "WorkflowEndpoints", "SystemEndpoints"]