"""
Tests for WorkflowOrchestrator functionality
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime

from elrmcp_bridge.src.workflows import (
    WorkflowOrchestrator,
    WorkflowDefinition,
    WorkflowExecution,
    TaskDefinition,
    TaskExecution,
    TaskStatus,
    WorkflowStatus
)
from elrmcp_bridge.src.config import WorkflowConfig


class TestWorkflowOrchestrator:
    """Test WorkflowOrchestrator class"""

    @pytest.fixture
    def workflow_config(self):
        """Create mock workflow configuration"""
        return Mock(spec=WorkflowConfig)

    @pytest.fixture
    def sample_workflow_definition(self):
        """Create sample workflow definition"""
        return WorkflowDefinition(
            workflow_id="test-workflow",
            name="Test Workflow",
            description="A test workflow",
            tasks=[
                TaskDefinition(
                    task_id="task-1",
                    name="first_task",
                    type="agent",
                    parameters={"input": "test"}
                ),
                TaskDefinition(
                    task_id="task-2",
                    name="second_task",
                    type="agent",
                    parameters={"input": "{{task-1.result}}"},
                    dependencies=["task-1"]
                ),
                TaskDefinition(
                    task_id="task-3",
                    name="parallel_task",
                    type="agent",
                    parameters={"input": "parallel"}
                )
            ]
        )

    @pytest.fixture
    def workflow_orchestrator(self, workflow_config):
        """Create WorkflowOrchestrator instance"""
        with patch('elrmcp_bridge.src.workflows.DependencyResolver'), \
             patch('elrmcp_bridge.src.workflows.TaskExecutor'), \
             patch('elrmcp_bridge.src.workflows.EventBus'):

            return WorkflowOrchestrator(workflow_config)

    def test_workflow_orchestrator_initialization(self, workflow_orchestrator):
        """Test WorkflowOrchestrator initialization"""
        assert workflow_orchestrator.config is not None
        assert workflow_orchestrator.dependency_resolver is not None
        assert workflow_orchestrator.task_executor is not None
        assert workflow_orchestrator.event_bus is not None
        assert workflow_orchestrator.workflow_executions == {}

    @pytest.mark.asyncio
    async def test_start_workflow_success(self, workflow_orchestrator, sample_workflow_definition):
        """Test successful workflow start"""
        mock_exec_id = "exec-123"
        workflow_orchestrator.dependency_resolver.resolve_dependencies = Mock(return_value=["task-1", "task-3", "task-2"])
        workflow_orchestrator.dependency_resolver.get_ready_tasks = Mock(return_value=["task-1", "task-3"])
        workflow_orchestrator.task_executor.execute_task = AsyncMock(return_value=TaskExecution(
            task_id="task-1",
            status=TaskStatus.COMPLETED,
            result={"output": "success"},
            start_time=datetime.now(),
            end_time=datetime.now()
        ))
        workflow_orchestrator.event_bus.emit = Mock()

        execution_id = await workflow_orchestrator.start_workflow(sample_workflow_definition.to_dict())

        assert execution_id == mock_exec_id
        assert execution_id in workflow_orchestrator.workflow_executions
        workflow_orchestrator.dependency_resolver.resolve_dependencies.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_workflow_invalid_config(self, workflow_orchestrator):
        """Test starting workflow with invalid config"""
        invalid_config = {"invalid": "config"}

        with pytest.raises(ValueError, match="Invalid workflow configuration"):
            await workflow_orchestrator.start_workflow(invalid_config)

    @pytest.mark.asyncio
    async def test_get_workflow_status(self, workflow_orchestrator, sample_workflow_definition):
        """Test getting workflow status"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={
                "task-1": TaskExecution(
                    task_id="task-1",
                    status=TaskStatus.COMPLETED,
                    result={"output": "success"},
                    start_time=datetime.now(),
                    end_time=datetime.now()
                ),
                "task-2": TaskExecution(
                    task_id="task-2",
                    status=TaskStatus.PENDING,
                    start_time=None,
                    end_time=None
                )
            },
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution

        status = await workflow_orchestrator.get_workflow_status("exec-123")

        assert status["workflow_id"] == "test-workflow"
        assert status["status"] == WorkflowStatus.RUNNING.value
        assert len(status["tasks"]) == 2
        assert status["tasks"]["task-1"]["status"] == TaskStatus.COMPLETED.value
        assert status["tasks"]["task-2"]["status"] == TaskStatus.PENDING.value

    def test_get_workflow_status_nonexistent(self, workflow_orchestrator):
        """Test getting status of non-existent workflow"""
        with pytest.raises(Exception, match="Workflow not found"):
            # This would be an async call but we're testing the sync version here
            workflow_orchestrator._get_workflow_status("non-existent-exec-id")

    @pytest.mark.asyncio
    async def test_cancel_workflow(self, workflow_orchestrator, sample_workflow_definition):
        """Test cancelling workflow"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.task_executor.cancel_task = AsyncMock()
        workflow_orchestrator.event_bus.emit = Mock()

        result = await workflow_orchestrator.cancel_workflow("exec-123")

        assert result is True
        assert mock_execution.status == WorkflowStatus.CANCELLED
        workflow_orchestrator.task_executor.cancel_task.assert_called_once()

    @pytest.mark.asyncio
    async def test_cancel_completed_workflow(self, workflow_orchestrator, sample_workflow_definition):
        """Test cancelling completed workflow"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.COMPLETED,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution

        result = await workflow_orchestrator.cancel_workflow("exec-123")

        assert result is False  # Cannot cancel completed workflow

    @pytest.mark.asyncio
    async def test_pause_workflow(self, workflow_orchestrator, sample_workflow_definition):
        """Test pausing workflow"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.event_bus.emit = Mock()

        await workflow_orchestrator.pause_workflow("exec-123")

        assert mock_execution.status == WorkflowStatus.PAUSED

    @pytest.mark.asyncio
    async def test_resume_workflow(self, workflow_orchestrator, sample_workflow_definition):
        """Test resuming workflow"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.PAUSED,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.dependency_resolver.get_ready_tasks = Mock(return_value=["task-1"])
        workflow_orchestrator.task_executor.execute_task = AsyncMock()
        workflow_orchestrator.event_bus.emit = Mock()

        await workflow_orchestrator.resume_workflow("exec-123")

        assert mock_execution.status == WorkflowStatus.RUNNING
        workflow_orchestrator.dependency_resolver.get_ready_tasks.assert_called_once()

    def test_dependency_resolution(self, workflow_orchestrator, sample_workflow_definition):
        """Test task dependency resolution"""
        order = workflow_orchestrator.dependency_resolver.resolve_dependencies(sample_workflow_definition.tasks)

        # Should be: task-1, task-3 (parallel), task-2 (depends on task-1)
        assert "task-1" in order
        assert "task-3" in order
        assert "task-2" in order
        assert order.index("task-1") < order.index("task-2")  # task-1 before task-2

    def test_get_ready_tasks(self, workflow_orchestrator, sample_workflow_definition):
        """Test getting ready tasks"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        # Initially, only task-1 and task-3 should be ready (no dependencies)
        ready_tasks = workflow_orchestrator.dependency_resolver.get_ready_tasks(mock_execution, sample_workflow_definition.tasks)
        assert len(ready_tasks) == 2
        assert "task-1" in ready_tasks
        assert "task-3" in ready_tasks
        assert "task-2" not in ready_tasks  # Has dependency

    @pytest.mark.asyncio
    async def test_task_execution_success(self, workflow_orchestrator, sample_workflow_definition):
        """Test successful task execution"""
        task = sample_workflow_definition.tasks[0]
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.task_executor.execute_task = AsyncMock(return_value=TaskExecution(
            task_id="task-1",
            status=TaskStatus.COMPLETED,
            result={"output": "success"},
            start_time=datetime.now(),
            end_time=datetime.now()
        ))
        workflow_orchestrator.event_bus.emit = Mock()

        task_exec = await workflow_orchestrator.execute_task(task, "exec-123")

        assert task_exec.status == TaskStatus.COMPLETED
        assert task_exec.result == {"output": "success"}
        workflow_orchestrator.task_executor.execute_task.assert_called_once_with(task)

    @pytest.mark.asyncio
    async def test_task_execution_failure(self, workflow_orchestrator, sample_workflow_definition):
        """Test failed task execution"""
        task = sample_workflow_definition.tasks[0]
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.task_executor.execute_task = AsyncMock(side_effect=Exception("Task failed"))
        workflow_orchestrator.event_bus.emit = Mock()

        task_exec = await workflow_orchestrator.execute_task(task, "exec-123")

        assert task_exec.status == TaskStatus.FAILED
        assert "error" in task_exec.result
        assert "Task failed" in task_exec.result["error"]

    @pytest.mark.asyncio
    async def test_task_retry(self, workflow_orchestrator, sample_workflow_definition):
        """Test task retry mechanism"""
        task = sample_workflow_definition.tasks[0]
        task.max_retries = 2

        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={
                "task-1": TaskExecution(
                    task_id="task-1",
                    status=TaskStatus.FAILED,
                    result={"error": "Temporary failure"},
                    start_time=datetime.now(),
                    end_time=datetime.now(),
                    retry_count=1
                )
            },
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.task_executor.execute_task = AsyncMock(return_value=TaskExecution(
            task_id="task-1",
            status=TaskStatus.COMPLETED,
            result={"output": "success"},
            start_time=datetime.now(),
            end_time=datetime.now()
        ))
        workflow_orchestrator.event_bus.emit = Mock()

        task_exec = await workflow_orchestrator.execute_task(task, "exec-123")

        assert task_exec.status == TaskStatus.COMPLETED
        assert task_exec.result == {"output": "success"}

    def test_workflow_timeout(self, workflow_orchestrator, sample_workflow_definition):
        """Test workflow timeout handling"""
        sample_workflow_definition.timeout = 30  # 30 seconds

        # Mock execution that's been running too long
        old_time = datetime.now() - timedelta(seconds=45)
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=old_time
        )

        # Check if workflow should timeout
        should_timeout = workflow_orchestrator._should_timeout_workflow(mock_execution)
        assert should_timeout is True

    @pytest.mark.asyncio
    async def test_concurrent_execution(self, workflow_orchestrator, sample_workflow_definition):
        """Test concurrent task execution"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.dependency_resolver.get_ready_tasks = Mock(return_value=["task-1", "task-3"])
        workflow_orchestrator.task_executor.execute_task = AsyncMock(return_value=TaskExecution(
            task_id="task-1",
            status=TaskStatus.COMPLETED,
            result={"output": "success"},
            start_time=datetime.now(),
            end_time=datetime.now()
        ))
        workflow_orchestrator.event_bus.emit = Mock()

        # Execute ready tasks concurrently
        await workflow_orchestrator.execute_concurrent_tasks("exec-123")

        # Should have executed both ready tasks
        assert workflow_orchestrator.task_executor.execute_task.call_count == 2

    def test_workflow_statistics(self, workflow_orchestrator):
        """Test workflow statistics"""
        mock_execution1 = Mock()
        mock_execution1.status = WorkflowStatus.COMPLETED
        mock_execution1.start_time = datetime.now() - timedelta(minutes=10)
        mock_execution1.end_time = datetime.now() - timedelta(minutes=5)

        mock_execution2 = Mock()
        mock_execution2.status = WorkflowStatus.RUNNING
        mock_execution2.start_time = datetime.now() - timedelta(minutes=2)
        mock_execution2.end_time = None

        workflow_orchestrator.workflow_executions = {
            "exec-1": mock_execution1,
            "exec-2": mock_execution2
        }

        stats = workflow_orchestrator.get_workflow_statistics()

        assert stats["total_workflows"] == 2
        assert stats["completed_workflows"] == 1
        assert stats["running_workflows"] == 1
        assert stats["failed_workflows"] == 0

    @pytest.mark.asyncio
    async def test_event_emission(self, workflow_orchestrator, sample_workflow_definition):
        """Test event emission"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.event_bus.emit = Mock()

        # Emit workflow started event
        await workflow_orchestrator.emit_event("workflow.started", "exec-123")

        workflow_orchestrator.event_bus.emit.assert_called_once_with("workflow.started", {
            "execution_id": "exec-123",
            "workflow_id": "test-workflow",
            "timestamp": mock_execution.start_time.isoformat()
        })

    def test_workflow_serialization(self, workflow_orchestrator, sample_workflow_definition):
        """Test workflow serialization"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={},
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution

        # Serialize workflow
        serialized = workflow_orchestrator.serialize_workflow("exec-123")
        assert "workflow_id" in serialized
        assert "status" in serialized
        assert "tasks" in serialized

        # Deserialize workflow
        deserialized = workflow_orchestrator.deserialize_workflow(serialized)
        assert deserialized.workflow_id == "test-workflow"
        assert deserialized.status == WorkflowStatus.RUNNING

    @pytest.mark.asyncio
    async def test_workflow_cleanup(self, workflow_orchestrator, sample_workflow_definition):
        """Test workflow cleanup"""
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.COMPLETED,
            tasks={},
            start_time=datetime.now() - timedelta(minutes=10),
            end_time=datetime.now() - timedelta(minutes=5)
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution

        # Cleanup old completed workflows
        await workflow_orchestrator.cleanup_completed_workflows(max_age_minutes=5)

        assert "exec-123" not in workflow_orchestrator.workflow_executions

    @pytest.mark.asyncio
    async def test_workflow_error_propagation(self, workflow_orchestrator, sample_workflow_definition):
        """Test error propagation in workflows"""
        # Make task-2 fail
        task2 = sample_workflow_definition.tasks[1]
        mock_execution = WorkflowExecution(
            workflow_id="test-workflow",
            workflow_definition=sample_workflow_definition,
            status=WorkflowStatus.RUNNING,
            tasks={
                "task-2": TaskExecution(
                    task_id="task-2",
                    status=TaskStatus.FAILED,
                    result={"error": "Dependency failed"},
                    start_time=datetime.now(),
                    end_time=datetime.now()
                )
            },
            start_time=datetime.now()
        )

        workflow_orchestrator.workflow_executions["exec-123"] = mock_execution
        workflow_orchestrator.event_bus.emit = Mock()

        # Handle error propagation
        await workflow_orchestrator.handle_error("exec-123", "task-2", Exception("Dependency failed"))

        # Check if dependent tasks were cancelled
        assert mock_execution.status == WorkflowStatus.FAILED