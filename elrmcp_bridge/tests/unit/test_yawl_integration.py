"""
===============================================================================
DEPRECATION NOTICE
===============================================================================

This test module is DEPRECATED.

The pure Erlang YAWL implementation should be tested using:
    - Test modules: erlang/a2a_erl/tests/yawl_*.erl
    - Pattern tests: yawl_pattern_tests.erl
    - Combinatoric tests: yawl_combinatoric_tests.erl
    - Business domain tests: yawl_business_tests.erl

Run Erlang tests with:
    cd erlang/a2a_erl && rebar3 ct

This module will be removed in version 1.0.0.

===============================================================================

Tests for YAWL Integration Module

Tests the integration of YAWL workflow patterns with the existing
workflow orchestrator using gen_pnet as the underlying engine.
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from elrmcp_bridge.src.yawl_integration import (
    YAWLPatternType,
    YAWLPatternDefinition,
    YAWLWorkflowConfig,
    YAWLPatternGenerator,
    YAWLWorkflowGenerator,
    YAWLWorkflowOrchestrator,
    create_yawl_workflow_orchestrator
)


class TestYAWLPatternGenerator:
    """Test YAWL Pattern Generator"""

    def test_pattern_generator_initialization(self):
        """Test YAWL pattern generator initialization"""
        generator = YAWLPatternGenerator()
        patterns = generator.list_patterns()

        assert len(patterns) > 0
        assert YAWLPatternType.BASIC_SEQUENTIAL in patterns
        assert YAWLPatternType.PARALLEL_SPLIT in patterns

    def test_get_pattern_definition(self):
        """Test getting pattern definition"""
        generator = YAWLPatternGenerator()
        pattern = generator.get_pattern_definition(YAWLPatternType.BASIC_SEQUENTIAL)

        assert pattern is not None
        assert pattern.pattern_type == YAWLPatternType.BASIC_SEQUENTIAL
        assert pattern.name == "Basic Sequential"
        assert len(pattern.places) == 4
        assert len(pattern.transitions) == 4

    def test_validate_pattern_config_basic_sequential(self):
        """Test basic sequential pattern configuration validation"""
        generator = YAWLPatternGenerator()
        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            parameters={}
        )

        assert generator.validate_pattern_config(YAWLPatternType.BASIC_SEQUENTIAL, config) is True

    def test_validate_pattern_config_parallel_split(self):
        """Test parallel split pattern configuration validation"""
        generator = YAWLPatternGenerator()

        # Valid configuration
        config_valid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.PARALLEL_SPLIT,
            parameters={"branches": 3}
        )
        assert generator.validate_pattern_config(YAWLPatternType.PARALLEL_SPLIT, config_valid) is True

        # Invalid configuration
        config_invalid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.PARALLEL_SPLIT,
            parameters={"branches": 1}
        )
        assert generator.validate_pattern_config(YAWLPatternType.PARALLEL_SPLIT, config_invalid) is False

    def test_validate_pattern_config_exclusive_choice(self):
        """Test exclusive choice pattern configuration validation"""
        generator = YAWLPatternGenerator()

        # Valid configuration
        config_valid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.EXCLUSIVE_CHOICE,
            parameters={"conditions": ["condition1", "condition2"]}
        )
        assert generator.validate_pattern_config(YAWLPatternType.EXCLUSIVE_CHOICE, config_valid) is True

        # Invalid configuration
        config_invalid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.EXCLUSIVE_CHOICE,
            parameters={"conditions": []}
        )
        assert generator.validate_pattern_config(YAWLPatternType.EXCLUSIVE_CHOICE, config_invalid) is False

    def test_validate_pattern_config_iterative_loop(self):
        """Test iterative loop pattern configuration validation"""
        generator = YAWLPatternGenerator()

        # Valid configuration
        config_valid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.ITERATIVE_LOOP,
            parameters={"condition": lambda x: x > 0}
        )
        assert generator.validate_pattern_config(YAWLPatternType.ITERATIVE_LOOP, config_valid) is True

        # Invalid configuration
        config_invalid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.ITERATIVE_LOOP,
            parameters={}
        )
        assert generator.validate_pattern_config(YAWLPatternType.ITERATIVE_LOOP, config_invalid) is False

    def test_validate_pattern_config_multi_instance(self):
        """Test multi instance pattern configuration validation"""
        generator = YAWLPatternGenerator()

        # Valid configuration
        data = [{"id": 1}, {"id": 2}, {"id": 3}]
        config_valid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.MULTI_INSTANCE,
            parameters={"num_instances": 3, "data": data}
        )
        assert generator.validate_pattern_config(YAWLPatternType.MULTI_INSTANCE, config_valid) is True

        # Invalid configuration
        config_invalid = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.MULTI_INSTANCE,
            parameters={"num_instances": 3}  # Missing data
        )
        assert generator.validate_pattern_config(YAWLPatternType.MULTI_INSTANCE, config_invalid) is False


class TestYAWLWorkflowGenerator:
    """Test YAWL Workflow Generator"""

    @pytest.fixture
    def pattern_generator(self):
        """Create YAWL pattern generator"""
        return YAWLPatternGenerator()

    @pytest.fixture
    def workflow_generator(self, pattern_generator):
        """Create YAWL workflow generator"""
        return YAWLWorkflowGenerator(pattern_generator)

    @pytest.fixture
    def basic_sequential_config(self):
        """Create basic sequential workflow config"""
        return YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            parameters={}
        )

    def test_create_workflow_from_pattern(self, workflow_generator, basic_sequential_config):
        """Test creating workflow from pattern"""
        workflow = workflow_generator.create_workflow_from_pattern(
            YAWLPatternType.BASIC_SEQUENTIAL,
            basic_sequential_config
        )

        assert workflow is not None
        assert workflow.name == "YAWL Basic Sequential"
        assert len(workflow.tasks) == 2  # Two tasks in basic sequential
        assert "pattern_type" in workflow.metadata

    def test_create_workflow_invalid_config(self, workflow_generator):
        """Test creating workflow with invalid configuration"""
        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.PARALLEL_SPLIT,
            parameters={"branches": 1}  # Invalid: must be >= 2
        )

        with pytest.raises(ValueError, match="Invalid configuration"):
            workflow_generator.create_workflow_from_pattern(
                YAWLPatternType.PARALLEL_SPLIT,
                config
            )

    def test_generate_tasks_basic_sequential(self, workflow_generator):
        """Test generating tasks for basic sequential pattern"""
        from elrmcp_bridge.src.yawl_integration import YAWLPatternDefinition

        # Create mock pattern definition
        pattern = YAWLPatternDefinition(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            name="Basic Sequential",
            description="Simple sequential execution",
            places=["start", "task1", "task2", "end"],
            transitions=["start", "t1", "task2", "end"],
            preset={"start": ["start"], "t1": ["task1"], "t2": ["task2"], "end": ["end"]},
            postset={"start": ["task1"], "t1": ["task2"], "t2": ["end"], "end": []},
            initial_marking={"start": ["token"]}
        )

        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            parameters={}
        )

        tasks = workflow_generator._generate_tasks_from_pattern(pattern, config)

        assert len(tasks) == 2  # Two tasks (excluding start/end transitions)
        assert tasks[0].name == "t1_task"
        assert tasks[1].name == "t2_task"
        assert tasks[1].dependencies == ["t1_task"]  # Sequential dependency


class TestYAWLWorkflowOrchestrator:
    """Test YAWL Workflow Orchestrator"""

    @pytest.fixture
    def mock_base_orchestrator(self):
        """Create mock base workflow orchestrator"""
        orchestrator = Mock()
        orchestrator.start_workflow = AsyncMock(return_value="test_workflow_id")
        return orchestrator

    @pytest.fixture
    def yawl_orchestrator(self, mock_base_orchestrator):
        """Create YAWL workflow orchestrator"""
        return YAWLWorkflowOrchestrator(mock_base_orchestrator)

    @pytest.fixture
    def basic_sequential_config(self):
        """Create basic sequential workflow config"""
        return YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            parameters={}
        )

    @pytest.mark.asyncio
    async def test_create_yawl_workflow(self, yawl_orchestrator, basic_sequential_config):
        """Test creating YAWL workflow"""
        workflow_id = await yawl_orchestrator.create_yawl_workflow(
            YAWLPatternType.BASIC_SEQUENTIAL,
            basic_sequential_config
        )

        assert workflow_id is not None
        assert "yawl_" in workflow_id
        assert workflow_id in yawl_orchestrator.yawl_workflows
        assert yawl_orchestrator.base_orchestrator.start_workflow.called

    @pytest.mark.asyncio
    async def test_create_yawl_workflow_invalid_config(self, yawl_orchestrator):
        """Test creating YAWL workflow with invalid configuration"""
        invalid_config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.PARALLEL_SPLIT,
            parameters={"branches": 1}  # Invalid
        )

        with pytest.raises(ValueError, match="Invalid configuration"):
            await yawl_orchestrator.create_yawl_workflow(
                YAWLPatternType.PARALLEL_SPLIT,
                invalid_config
            )

    @pytest.mark.asyncio
    async def test_validate_yawl_pattern(self, yawl_orchestrator, basic_sequential_config):
        """Test YAWL pattern validation"""
        validation_result = await yawl_orchestrator.validate_yawl_pattern(
            YAWLPatternType.BASIC_SEQUENTIAL,
            basic_sequential_config
        )

        assert validation_result["pattern_valid"] is True
        assert validation_result["configuration_valid"] is True
        assert validation_result["execution_semantics_valid"] is True

    def test_get_pattern_execution_status(self, yawl_orchestrator):
        """Test getting pattern execution status"""
        # Simulate pattern execution
        yawl_orchestrator.pattern_executions["test_workflow_id"] = YAWLPatternType.BASIC_SEQUENTIAL

        status = yawl_orchestrator.get_pattern_execution_status("test_workflow_id")

        assert status["workflow_id"] == "test_workflow_id"
        assert status["pattern_type"] == "basic_sequential"
        assert status["pattern_name"] == "Basic Sequential"

    def test_get_pattern_execution_status_not_found(self, yawl_orchestrator):
        """Test getting pattern execution status for non-existent workflow"""
        status = yawl_orchestrator.get_pattern_execution_status("nonexistent_id")

        assert "error" in status
        assert status["error"] == "Pattern execution not found"

    def test_list_available_patterns(self, yawl_orchestrator):
        """Test listing available patterns"""
        patterns_info = yawl_orchestrator.list_available_patterns()

        assert "patterns" in patterns_info
        assert "total" in patterns_info
        assert patterns_info["total"] > 0

        # Check basic sequential pattern
        basic_sequential = next((p for p in patterns_info["patterns"]
                               if p["type"] == "basic_sequential"), None)
        assert basic_sequential is not None
        assert basic_sequential["complexity"] == "low"

    def test_get_pattern_complexity(self, yawl_orchestrator):
        """Test pattern complexity mapping"""
        complexity = yawl_orchestrator._get_pattern_complexity(YAWLPatternType.BASIC_SEQUENTIAL)
        assert complexity == "low"

        complexity = yawl_orchestrator._get_pattern_complexity(YAWLPatternType.PARALLEL_SPLIT)
        assert complexity == "medium"

        complexity = yawl_orchestrator._get_pattern_complexity(YAWLPatternType.ITERATIVE_LOOP)
        assert complexity == "high"

    def test_get_required_parameters(self, yawl_orchestrator):
        """Test required parameters for pattern types"""
        # Basic sequential has no required parameters
        params = yawl_orchestrator._get_required_parameters(YAWLPatternType.BASIC_SEQUENTIAL)
        assert params == []

        # Parallel split requires branches parameter
        params = yawl_orchestrator._get_required_parameters(YAWLPatternType.PARALLEL_SPLIT)
        assert "branches" in params

        # Multi instance requires num_instances and data
        params = yawl_orchestrator._get_required_parameters(YAWLPatternType.MULTI_INSTANCE)
        assert "num_instances" in params
        assert "data" in params


class TestYAWLPatternTypes:
    """Test YAWL Pattern Types"""

    def test_pattern_types_enum(self):
        """Test YAWL pattern types enumeration"""
        assert YAWLPatternType.BASIC_SEQUENTIAL.value == "basic_sequential"
        assert YAWLPatternType.PARALLEL_SPLIT.value == "parallel_split"
        assert YAWLPatternType.ITERATIVE_LOOP.value == "iterative_loop"

        # Test all basic control-flow patterns
        assert YAWLPatternType.EXCLUSIVE_CHOICE.value == "exclusive_choice"
        assert YAWLPatternType.SIMPLE_MERGE.value == "simple_merge"

    def test_pattern_types_advanced_patterns(self):
        """Test advanced YAWL pattern types"""
        assert YAWLPatternType.MULTI_INSTANCE.value == "multi_instance"
        assert YAWLPatternType.INTERLEAVED_PARALLELISM.value == "interleaved_parallelism"
        assert YAWLPatternType.IMPLICIT_MERGE.value == "implicit_merge"

    def test_pattern_types_cancelation_patterns(self):
        """Test YAWL cancellation pattern types"""
        assert YAWLPatternType.CANCELATION_BLOCK.value == "cancelation_block"
        assert YAWLPatternType.CANCELATION_SCOPE.value == "cancelation_scope"
        assert YAWLPatternType.CANCELATION_THREAD.value == "cancelation_thread"
        assert YAWLPatternType.CANCELATION_POINT.value == "cancelation_point"


class TestFactoryFunction:
    """Test Factory Function"""

    def test_create_yawl_workflow_orchestrator(self):
        """Test creating YAWL workflow orchestrator factory function"""
        mock_orchestrator = Mock()
        yawl_orchestrator = create_yawl_workflow_orchestrator(mock_orchestrator)

        assert yawl_orchestrator is not None
        assert yawl_orchestrator.base_orchestrator == mock_orchestrator
        assert isinstance(yawl_orchestrator, YAWLWorkflowOrchestrator)


class TestYAWLWorkflowConfig:
    """Test YAWL Workflow Configuration"""

    def test_workflow_config_creation(self):
        """Test YAWL workflow configuration creation"""
        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            parameters={"timeout": 300},
            resource_allocations={"task1": ["resource1"]},
            data_mappings={"task1": {"input": "output"}}
        )

        assert config.pattern_type == YAWLPatternType.BASIC_SEQUENTIAL
        assert config.parameters["timeout"] == 300
        assert config.resource_allocations["task1"] == ["resource1"]
        assert config.data_mappings["task1"]["input"] == "output"


class TestIntegrationScenarios:
    """Test Integration Scenarios"""

    @pytest.mark.asyncio
    async def test_sequential_workflow_integration(self):
        """Test integration of sequential workflow"""
        mock_orchestrator = Mock()
        mock_orchestrator.start_workflow = AsyncMock(return_value="sequential_workflow_id")

        yawl_orchestrator = YAWLWorkflowOrchestrator(mock_orchestrator)

        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.BASIC_SEQUENTIAL,
            parameters={}
        )

        workflow_id = await yawl_orchestrator.create_yawl_workflow(
            YAWLPatternType.BASIC_SEQUENTIAL,
            config
        )

        assert workflow_id == "yawl_sequential_workflow_id"
        mock_orchestrator.start_workflow.assert_called_once()

    @pytest.mark.asyncio
    async def test_parallel_workflow_integration(self):
        """Test integration of parallel workflow"""
        mock_orchestrator = Mock()
        mock_orchestrator.start_workflow = AsyncMock(return_value="parallel_workflow_id")

        yawl_orchestrator = YAWLWorkflowOrchestrator(mock_orchestrator)

        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.PARALLEL_SPLIT,
            parameters={"branches": 3}
        )

        workflow_id = await yawl_orchestrator.create_yawl_workflow(
            YAWLPatternType.PARALLEL_SPLIT,
            config
        )

        assert workflow_id == "yawl_parallel_workflow_id"
        mock_orchestrator.start_workflow.assert_called_once()

    @pytest.mark.asyncio
    async def test_iterative_workflow_integration(self):
        """Test integration of iterative workflow"""
        mock_orchestrator = Mock()
        mock_orchestrator.start_workflow = AsyncMock(return_value="iterative_workflow_id")

        yawl_orchestrator = YAWLWorkflowOrchestrator(mock_orchestrator)

        def condition(x):
            return x > 0

        config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.ITERATIVE_LOOP,
            parameters={"condition": condition, "max_iterations": 10}
        )

        workflow_id = await yawl_orchestrator.create_yawl_workflow(
            YAWLPatternType.ITERATIVE_LOOP,
            config
        )

        assert workflow_id == "yawl_iterative_workflow_id"
        mock_orchestrator.start_workflow.assert_called_once()

    def test_pattern_validation_scenario(self):
        """Test pattern validation scenario"""
        yawl_orchestrator = YAWLWorkflowOrchestrator(Mock())

        # Valid parallel configuration
        valid_config = YAWLWorkflowConfig(
            pattern_type=YAWLPatternType.PARALLEL_SPLIT,
            parameters={"branches": 4}
        )

        # Test pattern validation
        pattern = yawl_orchestrator.pattern_generator.get_pattern_definition(
            YAWLPatternType.PARALLEL_SPLIT
        )
        assert pattern is not None

        # Test workflow generation
        workflow_generator = YAWLWorkflowGenerator(yawl_orchestrator.pattern_generator)
        workflow = workflow_generator.create_workflow_from_pattern(
            YAWLPatternType.PARALLEL_SPLIT,
            valid_config
        )

        assert workflow is not None
        assert len(workflow.tasks) == 4  # 4 branches
        assert workflow.metadata["pattern_type"] == "parallel_split"