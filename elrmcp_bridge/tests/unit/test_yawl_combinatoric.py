"""YAWL Combinatoric Testing Module

This module provides combinatoric testing for YAWL workflow patterns,
enabling systematic testing of pattern combinations and business scenarios.

Features:
    - Pattern combination generation
    - Business scenario simulation
    - Performance benchmarking
    - Error condition testing
    - Comprehensive validation
"""

import itertools
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, Tuple, Union
from enum import Enum
from datetime import datetime
import time
import asyncio
from concurrent.futures import ThreadPoolExecutor

from elrmcp_bridge.src.yawl_integration import (
    YAWLPatternType,
    YAWLWorkflowConfig,
    YAWLPatternGenerator,
    YAWLWorkflowGenerator,
    YAWLWorkflowOrchestrator
)


class ComplexityLevel(Enum):
    """Complexity levels for test scenarios"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class ScenarioType(Enum):
    """Types of test scenarios"""
    BUSINESS = "business"
    EDGE_CASE = "edge_case"
    PERFORMANCE = "performance"
    ERROR = "error"


class BusinessDomain(Enum):
    """Business domains for testing"""
    ORDER_PROCESSING = "order_processing"
    DOCUMENT_WORKFLOW = "document_workflow"
    DATA_PIPELINE = "data_pipeline"
    APPROVAL_CHAIN = "approval_chain"
    NOTIFICATION_SYSTEM = "notification_system"
    FINANCIAL_WORKFLOW = "financial_workflow"
    SUPPLY_CHAIN = "supply_chain"
    CUSTOMER_SERVICE = "customer_service"
    HR_WORKFLOW = "hr_workflow"
    SECURITY_AUDIT = "security_audit"


@dataclass
class TestResult:
    """Result of a test execution"""
    test_id: str
    scenario_name: str
    pattern_combination: List[Tuple[YAWLPatternType, Dict]]
    status: str  # "passed", "failed", "error"
    execution_time: float
    resource_utilization: float
    throughput: float
    error_message: Optional[str] = None
    validation_results: Dict[str, Any] = field(default_factory=dict)
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class ScenarioConfig:
    """Configuration for test scenario"""
    business_domain: BusinessDomain
    complexity: ComplexityLevel
    scenario_type: ScenarioType
    parameters: Dict[str, Any] = field(default_factory=dict)
    resource_requirements: Dict[str, List[str]] = field(default_factory=dict)
    data_volume: str = "medium"
    timeout: int = 30000
    success_criteria: Dict[str, Any] = field(default_factory=dict)


class YAWLCombinatoricTester:
    """Combinatoric testing engine for YAWL patterns"""

    def __init__(self, base_orchestrator):
        self.base_orchestrator = base_orchestrator
        self.pattern_generator = YAWLPatternGenerator()
        self.workflow_generator = YAWLWorkflowGenerator(self.pattern_generator)
        self.yawl_orchestrator = YAWLWorkflowOrchestrator(base_orchestrator)
        self.logger = logging.getLogger(__name__)
        self.test_results: List[TestResult] = []
        self.combination_cache: Dict[str, List] = {}

    def generate_sequential_combinations(self, patterns: List[YAWLPatternType],
                                       length: int) -> List[List[Tuple[YAWLPatternType, Dict]]]:
        """Generate sequential combinations of patterns"""
        combinations = []

        for combo in itertools.product(patterns, repeat=length):
            combination = [(p, {}) for p in combo]
            combinations.append(combination)

        return combinations

    def generate_parallel_combinations(self, patterns: List[YAWLPatternType],
                                       branch_count: int) -> List[List[Tuple[YAWLPatternType, Dict]]]:
        """Generate parallel combinations of patterns"""
        combinations = []

        for combo in itertools.product(patterns, repeat=branch_count):
            # Create parallel split structure
            combination = [(YAWLPatternType.PARALLEL_SPLIT, {"branches": branch_count})]
            for p in combo:
                combination.append((p, {}))
            combination.append((YAWLPatternType.PARALLEL_JOIN, {"branches": branch_count}))
            combinations.append(combination)

        return combinations

    def generate_nested_combinations(self, patterns: List[YAWLPatternType],
                                    max_depth: int) -> List[List[Tuple[YAWLPatternType, Dict]]]:
        """Generate nested combinations of patterns"""
        combinations = []

        for depth in range(1, max_depth + 1):
            for combo in itertools.product(patterns, repeat=depth):
                # Create nested structure
                combination = []
                for p in combo:
                    combination.append((p, {"nested": True, "depth": depth}))
                combinations.append(combination)

        return combinations

    def generate_all_combinations(self, patterns: List[YAWLPatternType],
                                 max_length: int = 5) -> List[List[Tuple[YAWLPatternType, Dict]]]:
        """Generate all possible combinations up to max_length"""
        all_combinations = []

        for length in range(1, max_length + 1):
            sequential = self.generate_sequential_combinations(patterns, length)
            all_combinations.extend(sequential)

            if length >= 2:
                parallel = self.generate_parallel_combinations(patterns, length)
                all_combinations.extend(parallel)

                nested = self.generate_nested_combinations(patterns, min(length, 3))
                all_combinations.extend(nested)

        return all_combinations

    def create_business_scenario(self, domain: BusinessDomain,
                                complexity: ComplexityLevel) -> ScenarioConfig:
        """Create a business scenario configuration"""
        return ScenarioConfig(
            business_domain=domain,
            complexity=complexity,
            scenario_type=ScenarioType.BUSINESS,
            parameters=self._get_domain_parameters(domain, complexity),
            resource_requirements=self._get_domain_resources(domain, complexity),
            data_volume=self._get_data_volume(complexity),
            success_criteria=self._get_success_criteria(domain, complexity)
        )

    def _get_domain_parameters(self, domain: BusinessDomain,
                              complexity: ComplexityLevel) -> Dict[str, Any]:
        """Get parameters for business domain"""
        params = {}

        if domain == BusinessDomain.ORDER_PROCESSING:
            params.update({
                "branches": 3 if complexity == ComplexityLevel.LOW else 4 if complexity == ComplexityLevel.MEDIUM else 5,
                "validation_required": True,
                "payment_processing": True,
                "inventory_check": True
            })
        elif domain == BusinessDomain.DOCUMENT_WORKFLOW:
            params.update({
                "branches": 2 if complexity == ComplexityLevel.LOW else 3,
                "approval_levels": 2 if complexity == ComplexityLevel.LOW else 3 if complexity == ComplexityLevel.MEDIUM else 4,
                "compliance_check": complexity == ComplexityLevel.HIGH,
                "audit_trail": True
            })
        elif domain == BusinessDomain.DATA_PIPELINE:
            params.update({
                "branches": 4 if complexity == ComplexityLevel.LOW else 6,
                "data_partitions": 10 if complexity == ComplexityLevel.LOW else 50 if complexity == ComplexityLevel.MEDIUM else 100,
                "quality_check": True,
                "parallel_processing": complexity != ComplexityLevel.LOW
            })

        return params

    def _get_domain_resources(self, domain: BusinessDomain,
                             complexity: ComplexityLevel) -> Dict[str, List[str]]:
        """Get resource requirements for domain"""
        resources = {}

        if domain == BusinessDomain.ORDER_PROCESSING:
            resources.update({
                "validate_order": ["validation_service", "database"],
                "process_payment": ["payment_gateway", "fraud_detection"],
                "check_inventory": ["inventory_service", "cache"],
                "ship_order": ["fulfillment_service", "tracking"]
            })
        elif domain == BusinessDomain.DOCUMENT_WORKFLOW:
            resources.update({
                "submit_document": ["document_system", "user_interface"],
                "legal_review": ["legal_expert", "compliance_tool"],
                "approve": ["authority_system", "digital_signature"],
                "archive": ["document_repository", "backup"]
            })
        elif domain == BusinessDomain.DATA_PIPELINE:
            resources.update({
                "extract": ["extractor", "source_connector"],
                "validate": ["validator", "schema_checker"],
                "transform": ["transformer", "rule_processor"],
                "store": ["storage_system", "database_cluster"]
            })

        return resources

    def _get_data_volume(self, complexity: ComplexityLevel) -> str:
        """Get data volume based on complexity"""
        return {
            ComplexityLevel.LOW: "small",
            ComplexityLevel.MEDIUM: "medium",
            ComplexityLevel.HIGH: "large"
        }[complexity]

    def _get_success_criteria(self, domain: BusinessDomain,
                             complexity: ComplexityLevel) -> Dict[str, Any]:
        """Get success criteria for domain"""
        criteria = {
            "max_duration": 30000 if complexity == ComplexityLevel.LOW else 60000 if complexity == ComplexityLevel.MEDIUM else 120000,
            "min_success_rate": 0.95,
            "resource_utilization": 0.8
        }

        if domain == BusinessDomain.DATA_PIPELINE:
            criteria["throughput"] = 10000 if complexity == ComplexityLevel.HIGH else 1000
            criteria["data_quality"] = 0.99

        return criteria

    async def execute_test(self, test_id: str, scenario_config: ScenarioConfig) -> TestResult:
        """Execute a single test scenario"""
        start_time = time.time()
        pattern_combination = self._generate_pattern_combination(scenario_config)

        try:
            # Create workflow configuration
            workflow_config = YAWLWorkflowConfig(
                pattern_type=pattern_combination[0][0] if pattern_combination else YAWLPatternType.BASIC_SEQUENTIAL,
                parameters=scenario_config.parameters,
                resource_allocations=scenario_config.resource_requirements
            )

            # Validate pattern
            validation_result = await self.yawl_orchestrator.validate_yawl_pattern(
                workflow_config.pattern_type,
                workflow_config
            )

            # Execute workflow
            workflow_id = await self.yawl_orchestrator.create_yawl_workflow(
                workflow_config.pattern_type,
                workflow_config
            )

            execution_time = time.time() - start_time

            # Create test result
            result = TestResult(
                test_id=test_id,
                scenario_name=f"{scenario_config.business_domain.value}_{scenario_config.complexity.value}",
                pattern_combination=pattern_combination,
                status="passed" if validation_result["pattern_valid"] else "failed",
                execution_time=execution_time,
                resource_utilization=0.75,  # Simulated
                throughput=100.0 / execution_time if execution_time > 0 else 0,
                validation_results=validation_result
            )

            self.test_results.append(result)
            return result

        except Exception as e:
            execution_time = time.time() - start_time
            result = TestResult(
                test_id=test_id,
                scenario_name=f"{scenario_config.business_domain.value}_{scenario_config.complexity.value}",
                pattern_combination=pattern_combination,
                status="error",
                execution_time=execution_time,
                resource_utilization=0.0,
                throughput=0.0,
                error_message=str(e)
            )
            self.test_results.append(result)
            return result

    def _generate_pattern_combination(self, config: ScenarioConfig) -> List[Tuple[YAWLPatternType, Dict]]:
        """Generate pattern combination based on scenario configuration"""
        domain = config.business_domain
        complexity = config.complexity

        if domain == BusinessDomain.ORDER_PROCESSING:
            return self._order_processing_patterns(complexity)
        elif domain == BusinessDomain.DOCUMENT_WORKFLOW:
            return self._document_workflow_patterns(complexity)
        elif domain == BusinessDomain.DATA_PIPELINE:
            return self._data_pipeline_patterns(complexity)
        else:
            return [(YAWLPatternType.BASIC_SEQUENTIAL, {})]

    def _order_processing_patterns(self, complexity: ComplexityLevel) -> List[Tuple[YAWLPatternType, Dict]]:
        """Generate order processing patterns"""
        if complexity == ComplexityLevel.LOW:
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "validate_order"}),
                (YAWLPatternType.EXCLUSIVE_CHOICE, {"conditions": 2}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 2}),
                (YAWLPatternType.PARALLEL_JOIN, {"branches": 2})
            ]
        elif complexity == ComplexityLevel.MEDIUM:
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "validate_order"}),
                (YAWLPatternType.EXCLUSIVE_CHOICE, {"conditions": 3}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 3}),
                (YAWLPatternType.PARALLEL_JOIN, {"branches": 3}),
                (YAWLPatternType.MULTI_INSTANCE, {"num_instances": 3})
            ]
        else:  # HIGH
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "validate_order"}),
                (YAWLPatternType.EXCLUSIVE_CHOICE, {"conditions": 4}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 4}),
                (YAWLPatternType.INTERLEAVED_PARALLELISM, {"tasks": 2}),
                (YAWLPatternType.PARALLEL_JOIN, {"branches": 4}),
                (YAWLPatternType.MULTI_INSTANCE, {"num_instances": 5}),
                (YAWLPatternType.ITERATIVE_LOOP, {"max_iterations": 5})
            ]

    def _document_workflow_patterns(self, complexity: ComplexityLevel) -> List[Tuple[YAWLPatternType, Dict]]:
        """Generate document workflow patterns"""
        if complexity == ComplexityLevel.LOW:
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "submit"}),
                (YAWLPatternType.EXCLUSIVE_CHOICE, {"conditions": 2}),
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "approve"})
            ]
        elif complexity == ComplexityLevel.MEDIUM:
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "submit"}),
                (YAWLPatternType.EXCLUSIVE_CHOICE, {"conditions": 3}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 3}),
                (YAWLPatternType.PARALLEL_JOIN, {"branches": 3}),
                (YAWLPatternType.ITERATIVE_LOOP, {"max_iterations": 3})
            ]
        else:  # HIGH
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "submit"}),
                (YAWLPatternType.EXCLUSIVE_CHOICE, {"conditions": 4}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 4}),
                (YAWLPatternType.INTERLEAVED_PARALLELISM, {"tasks": 2}),
                (YAWLPatternType.PARALLEL_JOIN, {"branches": 4}),
                (YAWLPatternType.MULTI_INSTANCE, {"num_instances": 3}),
                (YAWLPatternType.CANCELATION_BLOCK, {"scope": "process"})
            ]

    def _data_pipeline_patterns(self, complexity: ComplexityLevel) -> List[Tuple[YAWLPatternType, Dict]]:
        """Generate data pipeline patterns"""
        if complexity == ComplexityLevel.LOW:
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "extract"}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 2}),
                (YAWLPatternType.SIMPLE_MERGE, {"branches": 2}),
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "store"})
            ]
        elif complexity == ComplexityLevel.MEDIUM:
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "extract"}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 4}),
                (YAWLPatternType.INTERLEAVED_PARALLELISM, {"tasks": 2}),
                (YAWLPatternType.MULTIPLE_MERGE, {"branches": 3}),
                (YAWLPatternType.MULTI_INSTANCE, {"num_instances": 5}),
                (YAWLPatternType.ITERATIVE_LOOP, {"max_iterations": 10})
            ]
        else:  # HIGH
            return [
                (YAWLPatternType.BASIC_SEQUENTIAL, {"task": "extract"}),
                (YAWLPatternType.PARALLEL_SPLIT, {"branches": 6}),
                (YAWLPatternType.INTERLEAVED_PARALLELISM, {"tasks": 3}),
                (YAWLPatternType.MULTIPLE_MERGE, {"branches": 4}),
                (YAWLPatternType.MULTI_INSTANCE, {"num_instances": 10}),
                (YAWLPatternType.ITERATIVE_LOOP, {"max_iterations": 20}),
                (YAWLPatternType.CANCELATION_BLOCK, {"scope": "pipeline"})
            ]

    async def execute_combinatoric_tests(self, test_matrix: List[ScenarioConfig],
                                        max_concurrent: int = 10) -> List[TestResult]:
        """Execute combinatoric tests with parallel execution"""
        semaphore = asyncio.Semaphore(max_concurrent)

        async def run_test(scenario_config: ScenarioConfig, index: int) -> TestResult:
            async with semaphore:
                test_id = f"test_{index}_{scenario_config.business_domain.value}"
                return await self.execute_test(test_id, scenario_config)

        tasks = [run_test(config, i) for i, config in enumerate(test_matrix)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Handle exceptions
        final_results = []
        for result in results:
            if isinstance(result, Exception):
                final_results.append(TestResult(
                    test_id="error",
                    scenario_name="error",
                    pattern_combination=[],
                    status="error",
                    execution_time=0.0,
                    resource_utilization=0.0,
                    throughput=0.0,
                    error_message=str(result)
                ))
            else:
                final_results.append(result)

        return final_results

    def generate_test_matrix(self, domains: Optional[List[BusinessDomain]] = None,
                            complexities: Optional[List[ComplexityLevel]] = None) -> List[ScenarioConfig]:
        """Generate comprehensive test matrix"""
        if domains is None:
            domains = list(BusinessDomain)
        if complexities is None:
            complexities = list(ComplexityLevel)

        test_matrix = []

        for domain in domains:
            for complexity in complexities:
                # Business scenario
                test_matrix.append(self.create_business_scenario(domain, complexity))

                # Edge case scenario
                if complexity == ComplexityLevel.HIGH:
                    edge_config = ScenarioConfig(
                        business_domain=domain,
                        complexity=complexity,
                        scenario_type=ScenarioType.EDGE_CASE,
                        parameters=self._get_domain_parameters(domain, complexity),
                        resource_requirements=self._get_domain_resources(domain, complexity)
                    )
                    test_matrix.append(edge_config)

                # Performance scenario
                if complexity == ComplexityLevel.HIGH:
                    perf_config = ScenarioConfig(
                        business_domain=domain,
                        complexity=complexity,
                        scenario_type=ScenarioType.PERFORMANCE,
                        parameters=self._get_domain_parameters(domain, complexity),
                        resource_requirements=self._get_domain_resources(domain, complexity),
                        success_criteria={"target_throughput": 1000}
                    )
                    test_matrix.append(perf_config)

        return test_matrix

    def generate_test_report(self) -> Dict[str, Any]:
        """Generate comprehensive test report"""
        if not self.test_results:
            return {"error": "No test results available"}

        total_tests = len(self.test_results)
        passed_tests = len([r for r in self.test_results if r.status == "passed"])
        failed_tests = len([r for r in self.test_results if r.status == "failed"])
        error_tests = len([r for r in self.test_results if r.status == "error"])

        avg_execution_time = sum(r.execution_time for r in self.test_results) / total_tests
        avg_resource_utilization = sum(r.resource_utilization for r in self.test_results) / total_tests
        avg_throughput = sum(r.throughput for r in self.test_results) / total_tests

        # Group by business domain
        domain_results = {}
        for result in self.test_results:
            domain = "_".join(result.scenario_name.split("_")[:-1])
            if domain not in domain_results:
                domain_results[domain] = []
            domain_results[domain].append(result)

        domain_stats = {}
        for domain, results in domain_results.items():
            domain_passed = len([r for r in results if r.status == "passed"])
            domain_stats[domain] = {
                "total": len(results),
                "passed": domain_passed,
                "success_rate": domain_passed / len(results),
                "avg_execution_time": sum(r.execution_time for r in results) / len(results)
            }

        return {
            "summary": {
                "total_tests": total_tests,
                "passed": passed_tests,
                "failed": failed_tests,
                "errors": error_tests,
                "success_rate": passed_tests / total_tests,
                "avg_execution_time": avg_execution_time,
                "avg_resource_utilization": avg_resource_utilization,
                "avg_throughput": avg_throughput
            },
            "domain_statistics": domain_stats,
            "failed_tests": [
                {"test_id": r.test_id, "scenario": r.scenario_name, "error": r.error_message}
                for r in self.test_results if r.status != "passed"
            ],
            "timestamp": datetime.now().isoformat()
        }


def generate_combinatoric_test_cases() -> Dict[str, List]:
    """Generate all combinatoric test cases"""
    tester = YAWLCombinatoricTester(base_orchestrator=None)

    patterns = list(YAWLPatternType)

    # Generate combinations
    test_cases = {
        "sequential": tester.generate_sequential_combinations(patterns[:5], 3),
        "parallel": tester.generate_parallel_combinations(patterns[5:10], 3),
        "nested": tester.generate_nested_combinations(patterns[:3], 3)
    }

    return test_cases


# Test execution example
async def run_combinatoric_tests_example():
    """Example of running combinatoric tests"""
    from elrmcp_bridge.src.workflows import WorkflowOrchestrator

    # Create base orchestrator
    base_orchestrator = WorkflowOrchestrator(max_concurrent_workflows=10)

    # Create combinatoric tester
    tester = YAWLCombinatoricTester(base_orchestrator)

    # Generate test matrix
    test_matrix = tester.generate_test_matrix(
        domains=[BusinessDomain.ORDER_PROCESSING, BusinessDomain.DOCUMENT_WORKFLOW],
        complexities=[ComplexityLevel.LOW, ComplexityLevel.MEDIUM]
    )

    # Execute tests
    results = await tester.execute_combinatoric_tests(test_matrix)

    # Generate report
    report = tester.generate_test_report()

    print("=== Combinatoric Test Report ===")
    print(f"Total Tests: {report['summary']['total_tests']}")
    print(f"Passed: {report['summary']['passed']}")
    print(f"Success Rate: {report['summary']['success_rate']:.2%}")
    print(f"Average Execution Time: {report['summary']['avg_execution_time']:.2f}s")

    return results, report