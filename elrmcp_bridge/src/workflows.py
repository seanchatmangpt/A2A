"""Multi-Agent Workflow Orchestration

This module provides comprehensive workflow orchestration for multi-agent
coordination, enabling complex task delegation and cross-agent communication.

Workflow Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │              Workflow Orchestrator                           │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ Workflow    │    │ Task        │    ├──┬─────────┤      │
    │  │ Registry    │◄──►│ Manager     │    │Workflow│ Executor│      │
    │  └─────────────┘    └─────────────┘    │  Planner │        │
    │           │               │               └────┬───┘        │
    │  ┌─────────────┐    ┌─────────────┐         │             │
    │  │ State       │    ├──┬─────────┤          │             │
    │  │ Manager     │    │Workflow│Monitor│      │             │
    │  └─────────────┘    │  Status │        │      │             │
    │                     └─────────┘        │      │             │
    └─────────────────────────────────────────────────────────────┘

Key Features:
    - Multi-agent task delegation
    - Workflow state management
    - Task dependency resolution
    - Error handling and recovery
    - Performance monitoring
    - Comprehensive logging and metrics
"""

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Set, Type, Union
from enum import Enum
import uuid
import time


class WorkflowStatus(Enum):
    """Workflow execution status"""
    PENDING = "pending"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    TIMEOUT = "timeout"


class TaskStatus(Enum):
    """Task execution status"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    RETRYING = "retrying"
    WAITING = "waiting"


@dataclass
class TaskDefinition:
    """Task definition"""
    task_id: str
    name: str
    type: str  # "agent", "subworkflow", "parallel", "sequence"
    agent_id: Optional[str] = None
    parameters: Dict[str, Any] = field(default_factory=dict)
    dependencies: List[str] = field(default_factory=list)
    timeout: int = 300  # seconds
    retry_count: int = 0
    max_retries: int = 3
    priority: int = 1
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "task_id": self.task_id,
            "name": self.name,
            "type": self.type,
            "agent_id": self.agent_id,
            "parameters": self.parameters,
            "dependencies": self.dependencies,
            "timeout": self.timeout,
            "retry_count": self.retry_count,
            "max_retries": self.max_retries,
            "priority": self.priority,
            "metadata": self.metadata
        }


@dataclass
class TaskExecution:
    """Task execution instance"""
    task_id: str
    status: TaskStatus = TaskStatus.PENDING
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    result: Optional[Any] = None
    error: Optional[str] = None
    retry_count: int = 0
    execution_time: float = 0.0
    assigned_agent: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "task_id": self.task_id,
            "status": self.status.value,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "result": self.result,
            "error": self.error,
            "retry_count": self.retry_count,
            "execution_time": self.execution_time,
            "assigned_agent": self.assigned_agent,
            "metadata": self.metadata
        }


@dataclass
class WorkflowDefinition:
    """Workflow definition"""
    workflow_id: str
    name: str
    description: str
    tasks: List[TaskDefinition] = field(default_factory=list)
    parameters: Dict[str, Any] = field(default_factory=dict)
    timeout: int = 600  # seconds
    priority: int = 1
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "workflow_id": self.workflow_id,
            "name": self.name,
            "description": self.description,
            "tasks": [task.to_dict() for task in self.tasks],
            "parameters": self.parameters,
            "timeout": self.timeout,
            "priority": self.priority,
            "metadata": self.metadata
        }


@dataclass
class WorkflowExecution:
    """Workflow execution instance"""
    workflow_id: str
    status: WorkflowStatus = WorkflowStatus.PENDING
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    result: Optional[Any] = None
    error: Optional[str] = None
    tasks: Dict[str, TaskExecution] = field(default_factory=dict)
    current_task: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "workflow_id": self.workflow_id,
            "status": self.status.value,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "result": self.result,
            "error": self.error,
            "tasks": {task_id: task.to_dict() for task_id, task in self.tasks.items()},
            "current_task": self.current_task,
            "metadata": self.metadata
        }


class TaskDependencyResolver:
    """Task dependency resolution and ordering"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)

    def resolve_dependencies(self, tasks: List[TaskDefinition]) -> List[List[str]]:
        """Resolve task dependencies and return execution order"""
        # Build dependency graph
        graph = {}
        in_degree = {}

        for task in tasks:
            task_id = task.task_id
            graph[task_id] = task.dependencies
            in_degree[task_id] = len(task.dependencies)

        # Topological sort using Kahn's algorithm
        queue = [task_id for task_id, degree in in_degree.items() if degree == 0]
        execution_order = []

        while queue:
            current_level = []
            next_queue = []

            for task_id in queue:
                current_level.append(task_id)

                for dependent_task_id, dependencies in graph.items():
                    if task_id in dependencies:
                        in_degree[dependent_task_id] -= 1
                        if in_degree[dependent_task_id] == 0:
                            next_queue.append(dependent_task_id)

            execution_order.append(current_level)
            queue = next_queue

        # Check for cycles
        if len(execution_order) != len(tasks):
            raise ValueError("Circular dependency detected in workflow")

        return execution_order

    def get_ready_tasks(self, workflow: WorkflowExecution, task_definitions: List[TaskDefinition]) -> List[TaskDefinition]:
        """Get tasks that are ready to execute"""
        ready_tasks = []

        for task_def in task_definitions:
            # Check if task is already completed or running
            if task_def.task_id in workflow.tasks:
                task_exec = workflow.tasks[task_def.task_id]
                if task_exec.status in [TaskStatus.COMPLETED, TaskStatus.RUNNING]:
                    continue

            # Check if all dependencies are completed
            all_dependencies_completed = True
            for dep_id in task_def.dependencies:
                if dep_id in workflow.tasks:
                    dep_exec = workflow.tasks[dep_id]
                    if dep_exec.status != TaskStatus.COMPLETED:
                        all_dependencies_completed = False
                        break
                else:
                    all_dependencies_completed = False
                    break

            if all_dependencies_completed:
                ready_tasks.append(task_def)

        return ready_tasks

    def has_unresolved_dependencies(self, task_id: str, workflow: WorkflowExecution) -> bool:
        """Check if task has unresolved dependencies"""
        task_def = next((t for t in workflow.metadata.get("task_definitions", []) if t.task_id == task_id), None)
        if not task_def:
            return False

        for dep_id in task_def.dependencies:
            if dep_id in workflow.tasks:
                dep_exec = workflow.tasks[dep_id]
                if dep_exec.status != TaskStatus.COMPLETED:
                    return True
            else:
                return True

        return False


class TaskExecutor:
    """Task execution engine"""

    def __init__(self, agent_manager):
        self.agent_manager = agent_manager
        self.logger = logging.getLogger(__name__)
        self.running_tasks: Dict[str, asyncio.Task] = {}

    async def execute_task(self, task_def: TaskDefinition, workflow: WorkflowExecution) -> TaskExecution:
        """Execute a single task"""
        task_exec = TaskExecution(
            task_id=task_def.task_id,
            status=TaskStatus.RUNNING,
            started_at=datetime.now()
        )

        workflow.tasks[task_def.task_id] = task_exec

        try:
            # Execute task based on type
            if task_def.type == "agent":
                result = await self._execute_agent_task(task_def, workflow)
            elif task_def.type == "subworkflow":
                result = await self._execute_subworkflow_task(task_def, workflow)
            elif task_def.type == "parallel":
                result = await self._execute_parallel_task(task_def, workflow)
            elif task_def.type == "sequence":
                result = await self._execute_sequence_task(task_def, workflow)
            else:
                raise ValueError(f"Unknown task type: {task_def.type}")

            # Complete task successfully
            task_exec.status = TaskStatus.COMPLETED
            task_exec.result = result
            task_exec.completed_at = datetime.now()
            task_exec.execution_time = (task_exec.completed_at - task_exec.started_at).total_seconds()

            self.logger.info(f"Task completed: {task_def.task_id}")

            return task_exec

        except Exception as e:
            # Handle task failure
            task_exec.status = TaskStatus.FAILED
            task_exec.error = str(e)
            task_exec.completed_at = datetime.now()
            task_exec.execution_time = (task_exec.completed_at - task_exec.started_at).total_seconds()

            self.logger.error(f"Task failed: {task_def.task_id}, error: {e}")

            # Check for retries
            if task_def.retry_count < task_def.max_retries:
                task_exec.status = TaskStatus.RETRYING
                task_exec.retry_count += 1

                # Schedule retry
                await self._schedule_retry(task_def, workflow)

            return task_exec

    async def _execute_agent_task(self, task_def: TaskDefinition, workflow: WorkflowExecution) -> Any:
        """Execute agent task"""
        # Select agent based on task requirements
        if task_def.agent_id:
            agent_id = task_def.agent_id
        else:
            # Find agent with required capability
            target_agents = await self.agent_manager.get_agents_by_capability(task_def.name)
            if not target_agents:
                raise ValueError(f"No agents found with capability: {task_def.name}")

            agent_id = target_agents[0].agent_id

        # Send task to agent
        message = {
            "type": "task",
            "task_id": task_def.task_id,
            "name": task_def.name,
            "parameters": task_def.parameters,
            "timeout": task_def.timeout
        }

        response = await self.agent_manager.send_to_agent(agent_id, message)

        if response.get("error"):
            raise ValueError(response["error"])

        return response.get("result")

    async def _execute_subworkflow_task(self, task_def: TaskDefinition, workflow: WorkflowExecution) -> Any:
        """Execute subworkflow task"""
        # Extract subworkflow definition
        subworkflow_def = task_def.parameters.get("subworkflow")
        if not subworkflow_def:
            raise ValueError("Subworkflow task requires subworkflow definition")

        # Create subworkflow execution
        subworkflow_id = f"{workflow.workflow_id}_{task_def.task_id}"
        subworkflow = WorkflowDefinition(
            workflow_id=subworkflow_id,
            name=subworkflow_def.get("name", "Subworkflow"),
            description=subworkflow_def.get("description", ""),
            tasks=subworkflow_def.get("tasks", []),
            parameters=subworkflow_def.get("parameters", {}),
            timeout=subworkflow_def.get("timeout", task_def.timeout)
        )

        # Execute subworkflow
        subworkflow_execution = WorkflowExecution(
            workflow_id=subworkflow_id,
            status=WorkflowStatus.RUNNING,
            started_at=datetime.now()
        )

        subworkflow_executor = WorkflowOrchestrator(self.agent_manager)
        result = await subworkflow_executor.execute_workflow(subworkflow, subworkflow_execution)

        return result

    async def _execute_parallel_task(self, task_def: TaskDefinition, workflow: WorkflowExecution) -> Any:
        """Execute parallel task"""
        subtasks = task_def.parameters.get("subtasks", [])
        if not subtasks:
            raise ValueError("Parallel task requires subtasks")

        # Execute subtasks in parallel
        subtask_executions = []
        for subtask_def in subtasks:
            subtask_exec = TaskExecution(
                task_id=subtask_def["task_id"],
                status=TaskStatus.RUNNING,
                started_at=datetime.now()
            )

            # Execute subtask
            subtask_result = await self.execute_task(subtask_def, workflow)
            subtask_executions.append(subtask_result)

        # Wait for all subtasks to complete
        results = []
        for subtask_exec in subtask_executions:
            if subtask_exec.status == TaskStatus.COMPLETED:
                results.append(subtask_exec.result)
            else:
                raise ValueError(f"Subtask failed: {subtask_exec.task_id}")

        return results

    async def _execute_sequence_task(self, task_def: TaskDefinition, workflow: WorkflowExecution) -> Any:
        """Execute sequence task"""
        steps = task_def.parameters.get("steps", [])
        if not steps:
            raise ValueError("Sequence task requires steps")

        # Execute steps in sequence
        results = []
        for step_def in steps:
            step_task = TaskDefinition(
                task_id=step_def["task_id"],
                name=step_def["name"],
                type=step_def.get("type", "agent"),
                parameters=step_def.get("parameters", {}),
                dependencies=step_def.get("dependencies", [])
            )

            step_result = await self.execute_task(step_task, workflow)
            results.append(step_result)

        return results

    async def _schedule_retry(self, task_def: TaskDefinition, workflow: WorkflowExecution):
        """Schedule task retry"""
        # Calculate retry delay (exponential backoff)
        delay = min(2 ** task_def.retry_count, 60)  # Max 60 seconds

        self.logger.info(f"Scheduling retry for task {task_def.task_id} in {delay} seconds")

        # Schedule retry
        async def retry_task():
            await asyncio.sleep(delay)
            await self.execute_task(task_def, workflow)

        asyncio.create_task(retry_task())


class WorkflowMonitor:
    """Workflow monitoring and health checking"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.running_workflows: Dict[str, WorkflowExecution] = {}
        self.monitor_interval = 10  # seconds
        self.monitor_timer = None
        self.running = False

    async def start_monitoring(self):
        """Start workflow monitoring"""
        self.logger.info("Starting workflow monitoring...")
        self.running = True
        self.monitor_timer = asyncio.create_task(self._periodic_monitor())

    async def stop_monitoring(self):
        """Stop workflow monitoring"""
        self.logger.info("Stopping workflow monitoring...")
        self.running = False

        if self.monitor_timer:
            self.monitor_timer.cancel()
            self.monitor_timer = None

    async def _periodic_monitor(self):
        """Periodic monitoring"""
        while self.running:
            try:
                await self._check_workflows()
                await asyncio.sleep(self.monitor_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in workflow monitoring: {e}")
                await asyncio.sleep(self.monitor_interval)

    async def _check_workflows(self):
        """Check running workflows"""
        for workflow_id, workflow in self.running_workflows.items():
            if workflow.status == WorkflowStatus.RUNNING:
                # Check for timeouts
                if workflow.started_at:
                    elapsed = (datetime.now() - workflow.started_at).total_seconds()
                    if elapsed > workflow.metadata.get("timeout", 600):
                        await self._timeout_workflow(workflow_id, workflow)

    async def _timeout_workflow(self, workflow_id: str, workflow: WorkflowExecution):
        """Handle workflow timeout"""
        self.logger.warning(f"Workflow timeout: {workflow_id}")
        workflow.status = WorkflowStatus.TIMEOUT
        workflow.error = f"Workflow timed out after {workflow.metadata.get('timeout', 600)} seconds"
        workflow.completed_at = datetime.now()

        # Mark all running tasks as failed
        for task_id, task_exec in workflow.tasks.items():
            if task_exec.status == TaskStatus.RUNNING:
                task_exec.status = TaskStatus.FAILED
                task_exec.error = "Task failed due to workflow timeout"
                task_exec.completed_at = datetime.now()

    def add_workflow(self, workflow: WorkflowExecution):
        """Add workflow to monitoring"""
        self.running_workflows[workflow.workflow_id] = workflow

    def remove_workflow(self, workflow_id: str):
        """Remove workflow from monitoring"""
        if workflow_id in self.running_workflows:
            del self.running_workflows[workflow_id]


class WorkflowOrchestrator:
    """Main workflow orchestrator"""

    def __init__(self, agent_manager, max_concurrent_workflows: int = 10, workflow_timeout: int = 300):
        self.agent_manager = agent_manager
        self.max_concurrent_workflows = max_concurrent_workflows
        self.workflow_timeout = workflow_timeout
        self.logger = logging.getLogger(__name__)

        # Initialize components
        self.dependency_resolver = TaskDependencyResolver()
        self.task_executor = TaskExecutor(agent_manager)
        self.workflow_monitor = WorkflowMonitor()

        # Event handlers
        self.event_handlers: Dict[str, List] = {}

        # Workflow registry
        self.running_workflows: Dict[str, WorkflowExecution] = {}
        self.completed_workflows: Dict[str, WorkflowExecution] = {}

        # Running state
        self.running = False

    async def start(self):
        """Start workflow orchestrator"""
        self.logger.info("Starting Workflow Orchestrator...")

        # Start monitoring
        await self.workflow_monitor.start_monitoring()

        # Set up event handlers
        self._setup_event_handlers()

        self.running = True
        self.logger.info("Workflow Orchestrator started successfully")

    async def stop(self):
        """Stop workflow orchestrator"""
        self.logger.info("Stopping Workflow Orchestrator...")

        self.running = False

        # Stop monitoring
        await self.workflow_monitor.stop_monitoring()

        # Cancel running workflows
        for workflow_id, workflow in self.running_workflows.items():
            if workflow.status == WorkflowStatus.RUNNING:
                await self._cancel_workflow(workflow_id, workflow)

        self.logger.info("Workflow Orchestrator stopped successfully")

    def _setup_event_handlers(self):
        """Set up event handlers"""
        self.event_handlers = {
            "workflow_started": self._on_workflow_started,
            "workflow_completed": self._on_workflow_completed,
            "workflow_failed": self._on_workflow_failed,
            "task_started": self._on_task_started,
            "task_completed": self._on_task_completed,
            "task_failed": self._on_task_failed
        }

    async def start_workflow(self, workflow_def: WorkflowDefinition) -> str:
        """Start a new workflow"""
        if not self.running:
            raise RuntimeError("Workflow orchestrator is not running")

        # Check workflow limit
        if len(self.running_workflows) >= self.max_concurrent_workflows:
            raise RuntimeError("Maximum concurrent workflows reached")

        # Create workflow execution
        workflow_exec = WorkflowExecution(
            workflow_id=workflow_def.workflow_id,
            status=WorkflowStatus.RUNNING,
            started_at=datetime.now(),
            metadata={
                "task_definitions": workflow_def.tasks,
                "timeout": self.workflow_timeout
            }
        )

        # Register workflow
        self.running_workflows[workflow_def.workflow_id] = workflow_exec
        self.workflow_monitor.add_workflow(workflow_exec)

        # Start workflow execution
        asyncio.create_task(self._execute_workflow(workflow_def, workflow_exec))

        return workflow_def.workflow_id

    async def execute_workflow(self, workflow_def: WorkflowDefinition, workflow_exec: WorkflowExecution) -> Any:
        """Execute workflow to completion"""
        try:
            await self._execute_workflow(workflow_def, workflow_exec)
            return workflow_exec.result
        except Exception as e:
            self.logger.error(f"Error executing workflow {workflow_def.workflow_id}: {e}")
            raise

    async def _execute_workflow(self, workflow_def: WorkflowDefinition, workflow_exec: WorkflowExecution):
        """Execute workflow logic"""
        try:
            # Resolve task dependencies
            execution_order = self.dependency_resolver.resolve_dependencies(workflow_def.tasks)

            self.logger.info(f"Starting workflow {workflow_def.workflow_id} with {len(execution_order)} execution phases")

            # Execute tasks in phases
            for phase_index, phase_tasks in enumerate(execution_order):
                self.logger.debug(f"Executing phase {phase_index + 1}/{len(execution_order)}: {phase_tasks}")

                # Get ready tasks for this phase
                ready_tasks = self.dependency_resolver.get_ready_tasks(
                    workflow_exec,
                    [task for task in workflow_def.tasks if task.task_id in phase_tasks]
                )

                # Execute ready tasks
                task_futures = []
                for task_def in ready_tasks:
                    task_future = asyncio.create_task(
                        self.task_executor.execute_task(task_def, workflow_exec)
                    )
                    task_futures.append((task_def.task_id, task_future))

                # Wait for tasks to complete
                for task_id, task_future in task_futures:
                    try:
                        await task_future
                    except Exception as e:
                        self.logger.error(f"Error in task {task_id}: {e}")
                        # Continue with other tasks

                # Check if workflow should continue
                if not self._should_continue_workflow(workflow_exec):
                    break

            # Finalize workflow
            await self._finalize_workflow(workflow_def, workflow_exec)

        except Exception as e:
            self.logger.error(f"Error in workflow execution: {e}")
            workflow_exec.status = WorkflowStatus.FAILED
            workflow_exec.error = str(e)
            workflow_exec.completed_at = datetime.now()

    def _should_continue_workflow(self, workflow: WorkflowExecution) -> bool:
        """Check if workflow should continue"""
        if workflow.status != WorkflowStatus.RUNNING:
            return False

        # Check if all tasks are completed
        for task_def in workflow.metadata.get("task_definitions", []):
            if task_def.task_id in workflow.tasks:
                task_exec = workflow.tasks[task_def.task_id]
                if task_exec.status not in [TaskStatus.COMPLETED, TaskStatus.FAILED]:
                    return True
            else:
                return True

        return False

    async def _finalize_workflow(self, workflow_def: WorkflowDefinition, workflow_exec: WorkflowExecution):
        """Finalize workflow execution"""
        # Check overall status
        completed_tasks = sum(1 for task in workflow_exec.tasks.values() if task.status == TaskStatus.COMPLETED)
        total_tasks = len(workflow_def.tasks)

        if completed_tasks == total_tasks:
            workflow_exec.status = WorkflowStatus.COMPLETED
            workflow_exec.result = {
                "completed_tasks": completed_tasks,
                "total_tasks": total_tasks,
                "success_rate": completed_tasks / total_tasks
            }
        else:
            workflow_exec.status = WorkflowStatus.FAILED
            workflow_exec.error = f"Workflow completed with {completed_tasks}/{total_tasks} tasks"

        workflow_exec.completed_at = datetime.now()

        # Move to completed workflows
        self.completed_workflows[workflow_def.workflow_id] = workflow_exec
        self.running_workflows.pop(workflow_def.workflow_id, None)
        self.workflow_monitor.remove_workflow(workflow_def.workflow_id)

        # Emit completion event
        await self.emit_event("workflow_completed", workflow_exec)

    async def _cancel_workflow(self, workflow_id: str, workflow: WorkflowExecution):
        """Cancel workflow"""
        workflow.status = WorkflowStatus.CANCELLED
        workflow.completed_at = datetime.now()

        # Cancel running tasks
        for task_id, task_exec in workflow.tasks.items():
            if task_exec.status == TaskStatus.RUNNING:
                task_exec.status = TaskStatus.CANCELLED
                task_exec.completed_at = datetime.now()

        # Remove from running workflows
        self.running_workflows.pop(workflow_id, None)
        self.workflow_monitor.remove_workflow(workflow_id)

    async def get_workflow_status(self, workflow_id: Optional[str] = None) -> Dict[str, Any]:
        """Get workflow status"""
        if workflow_id:
            workflow = self.running_workflows.get(workflow_id) or self.completed_workflows.get(workflow_id)
            return workflow.to_dict() if workflow else {"error": "Workflow not found"}
        else:
            return {
                "running_workflows": len(self.running_workflows),
                "completed_workflows": len(self.completed_workflows),
                "running": [w.to_dict() for w in self.running_workflows.values()],
                "completed": [w.to_dict() for w in self.completed_workflows.values()]
            }

    async def add_available_agent(self, agent_info):
        """Add available agent to orchestrator"""
        # Agent is now available for task assignment
        self.logger.debug(f"Agent {agent_info.agent_id} available for workflow execution")

    async def remove_agent(self, agent_id: str):
        """Remove agent from orchestrator"""
        # Reassign tasks from lost agent
        for workflow_id, workflow in self.running_workflows.items():
            for task_id, task_exec in workflow.tasks.items():
                if task_exec.assigned_agent == agent_id:
                    task_exec.status = TaskStatus.PENDING
                    task_exec.assigned_agent = None

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

    # Event handlers
    async def _on_workflow_started(self, workflow: WorkflowExecution):
        """Handle workflow started event"""
        self.logger.info(f"Workflow started: {workflow.workflow_id}")

    async def _on_workflow_completed(self, workflow: WorkflowExecution):
        """Handle workflow completed event"""
        self.logger.info(f"Workflow completed: {workflow.workflow_id}")

    async def _on_workflow_failed(self, workflow: WorkflowExecution):
        """Handle workflow failed event"""
        self.logger.error(f"Workflow failed: {workflow.workflow_id}")

    async def _on_task_started(self, task: TaskExecution):
        """Handle task started event"""
        self.logger.debug(f"Task started: {task.task_id}")

    async def _on_task_completed(self, task: TaskExecution):
        """Handle task completed event"""
        self.logger.debug(f"Task completed: {task.task_id}")

    async def _on_task_failed(self, task: TaskExecution):
        """Handle task failed event"""
        self.logger.warning(f"Task failed: {task.task_id}")