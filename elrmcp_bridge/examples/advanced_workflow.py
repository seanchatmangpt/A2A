#!/usr/bin/env python3
"""
Advanced Workflow Example for A2A Bridge

This example demonstrates advanced workflow features including:
- Multi-agent task delegation
- Complex task dependencies
- Error handling and recovery
- Real-time monitoring
- Performance optimization

Usage:
    python advanced_workflow.py
"""

import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List

from elrmcp_bridge.src.bridge import A2ABridge
from elrmcp_bridge.src.config import BridgeConfig
from elrmcp_bridge.src.workflows import WorkflowDefinition, TaskDefinition


async def create_data_processing_workflow() -> WorkflowDefinition:
    """Create a complex data processing workflow"""
    workflow = WorkflowDefinition(
        workflow_id="data-processing-workflow",
        name="Advanced Data Processing",
        description="Complex multi-agent data processing workflow",
        timeout=600,
        priority=1
    )

    # Task 1: Data Collection (can be done in parallel)
    workflow.tasks.append(TaskDefinition(
        task_id="collect-user-data",
        name="collect_user_data",
        type="agent",
        parameters={
            "source": "user_database",
            "limit": 1000
        },
        timeout=60,
        max_retries=3
    ))

    workflow.tasks.append(TaskDefinition(
        task_id="collect-system-data",
        name="collect_system_data",
        type="agent",
        parameters={
            "source": "system_logs",
            "time_range": "24h"
        },
        timeout=60,
        max_retries=3
    ))

    # Task 2: Data Validation
    workflow.tasks.append(TaskDefinition(
        task_id="validate-user-data",
        name="validate_data",
        type="agent",
        parameters={
            "data_type": "user",
            "validation_rules": ["completeness", "consistency", "format"]
        },
        dependencies=["collect-user-data"],
        timeout=30,
        max_retries=2
    ))

    workflow.tasks.append(TaskDefinition(
        task_id="validate-system-data",
        name="validate_data",
        type="agent",
        parameters={
            "data_type": "system",
            "validation_rules": ["completeness", "consistency"]
        },
        dependencies=["collect-system-data"],
        timeout=30,
        max_retries=2
    ))

    # Task 3: Data Transformation
    workflow.tasks.append(TaskDefinition(
        task_id="transform-user-data",
        name="transform_data",
        type="agent",
        parameters={
            "input_data": "{{validate-user-data.result}}",
            "target_format": "analytics-ready",
            "transformation_rules": ["normalization", "enrichment"]
        },
        dependencies=["validate-user-data"],
        timeout=90,
        max_retries=3
    ))

    workflow.tasks.append(TaskDefinition(
        task_id="transform-system-data",
        name="transform_data",
        type="agent",
        parameters={
            "input_data": "{{validate-system-data.result}}",
            "target_format": "analytics-ready",
            "transformation_rules": ["aggregation", "filtering"]
        },
        dependencies=["validate-system-data"],
        timeout=90,
        max_retries=3
    ))

    # Task 4: Parallel Processing
    workflow.tasks.append(TaskDefinition(
        task_id="parallel-analysis",
        name="execute_parallel_tasks",
        type="parallel",
        parameters={
            "subtasks": [
                {
                    "task_id": "task-user-analytics",
                    "name": "analyze_user_behavior",
                    "type": "agent",
                    "parameters": {
                        "data": "{{transform-user-data.result}}",
                        "analysis_type": "behavioral"
                    }
                },
                {
                    "task_id": "task-system-analytics",
                    "name": "analyze_system_performance",
                    "type": "agent",
                    "parameters": {
                        "data": "{{transform-system-data.result}}",
                        "analysis_type": "performance"
                    }
                },
                {
                    "task_id": "task-compliance-check",
                    "name": "check_compliance",
                    "type": "agent",
                    "parameters": {
                        "data": "{{transform-user-data.result}}",
                        "standards": ["gdpr", "ccpa"]
                    }
                }
            ]
        },
        dependencies=["transform-user-data", "transform-system-data"],
        timeout=120,
        max_retries=2
    ))

    # Task 5: Result Aggregation
    workflow.tasks.append(TaskDefinition(
        task_id="aggregate-results",
        name="aggregate_results",
        type="agent",
        parameters={
            "results": [
                "{{task-user-analytics.result}}",
                "{{task-system-analytics.result}}",
                "{{task-compliance-check.result}}"
            ],
            "output_format": "executive_summary"
        },
        dependencies=["parallel-analysis"],
        timeout=60,
        max_retries=2
    ))

    # Task 6: Report Generation
    workflow.tasks.append(TaskDefinition(
        task_id="generate-report",
        name="generate_report",
        type="sequence",
        parameters={
            "steps": [
                {
                    "task_id": "step-1",
                    "name": "create_template",
                    "type": "agent",
                    "parameters": {
                        "template": "executive_report"
                    }
                },
                {
                    "task_id": "step-2",
                    "name": "populate_data",
                    "type": "agent",
                    "parameters": {
                        "template": "{{step-1.result}}",
                        "data": "{{aggregate-results.result}}"
                    }
                },
                {
                    "task_id": "step-3",
                    "name": "format_output",
                    "type": "agent",
                    "parameters": {
                        "document": "{{step-2.result}}",
                        "format": "pdf"
                    }
                }
            ]
        },
        dependencies=["aggregate-results"],
        timeout=90,
        max_retries=2
    ))

    return workflow


async def main():
    """Main application"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    logger.info("Starting A2A Bridge advanced workflow example...")

    # Create bridge configuration with advanced settings
    config = BridgeConfig(
        host="localhost",
        port=8001,
        debug=True,
        development=True,

        # Enhanced transport configuration
        transport_type="hybrid",
        websocket_url="ws://localhost:8080",
        sse_url="http://localhost:8081",

        # Advanced workflow settings
        max_concurrent_workflows=5,
        workflow_timeout=600,
        task_timeout=120,

        # Enhanced security
        security_config.api_key="advanced-demo-key",
        security_config.auth_required=False,

        # Comprehensive logging
        logging_config.level="DEBUG",
        logging_config.enable_console=True,
        logging_config.enable_file=True,

        # Advanced metrics
        metrics_config.enabled=True,
        metrics_config.port=8000,
        metrics_config.alert_enabled=True,
        metrics_config.alert_email="admin@example.com"
    )

    # Create A2A bridge
    bridge = A2ABridge(config)

    try:
        # Start bridge
        await bridge.start()
        logger.info("A2A Bridge started successfully")

        # Create advanced workflow
        workflow = await create_data_processing_workflow()
        logger.info(f"Created workflow: {workflow.name}")
        logger.info(f"Total tasks: {len(workflow.tasks)}")

        # Start workflow
        workflow_id = await bridge.start_workflow(workflow.to_dict())
        logger.info(f"Workflow started: {workflow_id}")

        # Monitor workflow execution
        logger.info("Monitoring workflow execution...")
        monitoring_start = datetime.now()

        while True:
            workflow_status = await bridge.get_workflow_status(workflow_id)

            if workflow_status['status'] == 'completed':
                logger.info("Workflow completed successfully!")
                break
            elif workflow_status['status'] == 'failed':
                logger.error(f"Workflow failed: {workflow_status.get('error', 'Unknown error')}")
                break
            elif workflow_status['status'] == 'timeout':
                logger.warning("Workflow timed out")
                break

            # Print current progress
            completed_tasks = sum(1 for task in workflow_status['tasks'].values()
                               if task['status'] == 'completed')
            total_tasks = len(workflow_status['tasks'])

            logger.info(f"Progress: {completed_tasks}/{total_tasks} tasks completed")

            # Print task details
            for task_id, task_info in workflow_status['tasks'].items():
                if task_info['status'] not in ['pending']:
                    logger.info(f"Task {task_id}: {task_info['status']} "
                              f"(took {task_info.get('execution_time', 0):.2f}s)")

            # Check for errors
            for task_id, task_info in workflow_status['tasks'].items():
                if task_info['status'] == 'failed':
                    logger.error(f"Task {task_id} failed: {task_info.get('error', 'Unknown error')}")

            await asyncio.sleep(10)

        # Get final workflow results
        final_status = await bridge.get_workflow_status(workflow_id)
        execution_time = (datetime.now() - monitoring_start).total_seconds()

        logger.info(f"Workflow execution completed in {execution_time:.2f} seconds")
        logger.info(f"Final status: {final_status['status']}")

        if 'result' in final_status:
            logger.info(f"Workflow result: {final_status['result']}")

        # Collect performance metrics
        metrics = await bridge.get_bridge_metrics()
        logger.info("Performance Metrics:")
        logger.info(f"  Total messages processed: {metrics['metrics']['total_messages_processed']}")
        logger.info(f"  Total workflows completed: {metrics['metrics']['total_workflows_completed']}")
        logger.info(f"  Total agents discovered: {metrics['metrics']['total_agents_discovered']}")
        logger.info(f"  Bridge uptime: {metrics['uptime']:.2f} seconds")

        # Demonstrate error handling by running another workflow with errors
        logger.info("Testing error handling...")
        error_workflow = WorkflowDefinition(
            workflow_id="error-test-workflow",
            name="Error Handling Test",
            description="Workflow designed to test error handling",
            timeout=30,
            tasks=[
                TaskDefinition(
                    task_id="task-1",
                    name="failing_task",
                    type="agent",
                    parameters={"should_fail": True}
                ),
                TaskDefinition(
                    task_id="task-2",
                    name="dependent_task",
                    type="agent",
                    parameters={"input": "test"},
                    dependencies=["task-1"]
                )
            ]
        )

        error_workflow_id = await bridge.start_workflow(error_workflow.to_dict())
        logger.info(f"Error test workflow started: {error_workflow_id}")

        # Wait for error workflow to complete
        await asyncio.sleep(5)
        error_status = await bridge.get_workflow_status(error_workflow_id)
        logger.info(f"Error test workflow status: {error_status['status']}")

    except KeyboardInterrupt:
        logger.info("Shutting down...")
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
    finally:
        # Stop bridge
        await bridge.stop()
        logger.info("A2A Bridge stopped")


if __name__ == "__main__":
    asyncio.run(main())