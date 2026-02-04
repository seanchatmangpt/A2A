"""Metrics Collection and Observability

This module provides comprehensive metrics collection and monitoring
for the A2A bridge, including performance metrics, business metrics,
 and system health metrics.

Metrics Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │                 Metrics Collector                             │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ Metrics     │    ├──┬─────────┤    │ Prometheus   │      │
    │  │ Registry    │    │Metric│Collector│    │ Exporter    │      │
    │  └─────────────┘    │  Store │        │   Support    │      │
    │           │           └───────┘        └─────────────┘      │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
    │  │ Real-time   │    │ Historical  │    │ Alerting    │      │
    │  │ Dashboard   │    │ Storage     │    │ System      │      │
    │  └─────────────┘    └─────────────┘    └─────────────┘      │
    └─────────────────────────────────────────────────────────────┘

Key Features:
    - Comprehensive metrics collection
    - Real-time monitoring
    - Historical data storage
    - Alerting and notifications
    - Performance optimization
    - Export to Prometheus
"""

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Type, Union
from enum import Enum
import threading
import time
from collections import defaultdict, deque


class MetricType(Enum):
    """Metric types"""
    COUNTER = "counter"
    GAUGE = "gauge"
    HISTOGRAM = "histogram"
    SUMMARY = "summary"


@dataclass
class MetricDefinition:
    """Metric definition"""
    name: str
    type: MetricType
    description: str
    unit: Optional[str] = None
    labels: List[str] = field(default_factory=list)
    buckets: Optional[List[float]] = None
    quantiles: Optional[List[float]] = None
    help_text: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "name": self.name,
            "type": self.type.value,
            "description": self.description,
            "unit": self.unit,
            "labels": self.labels,
            "buckets": self.buckets,
            "quantiles": self.quantiles,
            "help_text": self.help_text
        }


@dataclass
class MetricValue:
    """Metric value"""
    metric_name: str
    value: float
    timestamp: datetime = field(default_factory=datetime.now)
    labels: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            "metric_name": self.metric_name,
            "value": self.value,
            "timestamp": self.timestamp.isoformat(),
            "labels": self.labels
        }


class MetricsRegistry:
    """Metrics registry for storing and retrieving metrics"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.metrics: Dict[str, MetricDefinition] = {}
        self.values: Dict[str, deque] = defaultdict(deque)
        self.max_history_size = 1000
        self.lock = threading.Lock()

    def register_metric(self, metric_def: MetricDefinition):
        """Register a new metric"""
        with self.lock:
            self.metrics[metric_def.name] = metric_def

    def unregister_metric(self, metric_name: str):
        """Unregister a metric"""
        with self.lock:
            if metric_name in self.metrics:
                del self.metrics[metric_name]
            if metric_name in self.values:
                del self.values[metric_name]

    def record_value(self, metric_name: str, value: float, labels: Dict[str, str] = None):
        """Record a metric value"""
        with self.lock:
            if metric_name not in self.values:
                self.values[metric_name] = deque(maxlen=self.max_history_size)

            metric_value = MetricValue(
                metric_name=metric_name,
                value=value,
                labels=labels or {}
            )

            self.values[metric_name].append(metric_value)

    def get_metric_definition(self, metric_name: str) -> Optional[MetricDefinition]:
        """Get metric definition"""
        return self.metrics.get(metric_name)

    def get_values(self, metric_name: str, limit: int = 100) -> List[MetricValue]:
        """Get metric values"""
        values = self.values.get(metric_name, deque())
        return list(values)[-limit:]

    def get_all_metrics(self) -> Dict[str, Any]:
        """Get all metrics and their values"""
        result = {}

        with self.lock:
            for metric_name, metric_def in self.metrics.items():
                values = self.get_values(metric_name)
                result[metric_name] = {
                    "definition": metric_def.to_dict(),
                    "values": [value.to_dict() for value in values],
                    "current_value": values[-1].value if values else 0
                }

        return result

    def get_metrics_summary(self) -> Dict[str, Any]:
        """Get metrics summary"""
        summary = {
            "total_metrics": len(self.metrics),
            "metrics_with_data": sum(1 for v in self.values.values() if v),
            "total_values": sum(len(v) for v in self.values.values()),
            "timestamp": datetime.now().isoformat()
        }
        return summary


class MetricsCollector:
    """Main metrics collector"""

    def __init__(self, port: int = 8000):
        self.port = port
        self.logger = logging.getLogger(__name__)
        self.registry = MetricsRegistry()
        self.server = None
        self.running = False
        self.exporters = []

        # Initialize default metrics
        self._initialize_default_metrics()

    def _initialize_default_metrics(self):
        """Initialize default metrics"""
        # Bridge metrics
        self.registry.register_metric(MetricDefinition(
            name="bridge_messages_processed",
            type=MetricType.COUNTER,
            description="Total messages processed by bridge",
            unit="count"
        ))

        self.registry.register_metric(MetricDefinition(
            name="bridge_workflows_completed",
            type=MetricType.COUNTER,
            description="Total workflows completed",
            unit="count"
        ))

        self.registry.register_metric(MetricDefinition(
            name="bridge_agents_discovered",
            type=MetricType.COUNTER,
            description="Total agents discovered",
            unit="count"
        ))

        self.registry.register_metric(MetricDefinition(
            name="bridge_errors",
            type=MetricType.COUNTER,
            description="Total bridge errors",
            unit="count"
        ))

        self.registry.register_metric(MetricDefinition(
            name="bridge_uptime",
            type=MetricType.GAUGE,
            description="Bridge uptime in seconds",
            unit="seconds"
        ))

        self.registry.register_metric(MetricDefinition(
            name="bridge_active_agents",
            type=MetricType.GAUGE,
            description="Number of active agents",
            unit="count"
        ))

        self.registry.register_metric(MetricDefinition(
            name="bridge_running_workflows",
            type=MetricType.GAUGE,
            description="Number of running workflows",
            unit="count"
        ))

        # Transport metrics
        self.registry.register_metric(MetricDefinition(
            name="transport_connections",
            type=MetricType.GAUGE,
            description="Number of active transport connections",
            unit="count",
            labels=["transport_type"]
        ))

        self.registry.register_metric(MetricDefinition(
            name="transport_message_latency",
            type=MetricType.HISTOGRAM,
            description="Transport message latency in milliseconds",
            unit="ms",
            buckets=[0.1, 0.5, 1, 5, 10, 50, 100, 500, 1000]
        ))

        # Agent metrics
        self.registry.register_metric(MetricDefinition(
            name="agent_message_count",
            type=MetricType.COUNTER,
            description="Messages sent to agents",
            unit="count",
            labels=["agent_id", "status"]
        ))

        self.registry.register_metric(MetricDefinition(
            name="agent_response_time",
            type=MetricType.HISTOGRAM,
            description="Agent response time in seconds",
            unit="seconds",
            buckets=[0.1, 0.5, 1, 2, 5, 10, 30, 60]
        ))

        # Workflow metrics
        self.registry.register_metric(MetricDefinition(
            name="workflow_task_count",
            type=MetricType.COUNTER,
            description="Total workflow tasks executed",
            unit="count"
        ))

        self.registry.register_metric(MetricDefinition(
            name="workflow_duration",
            type=MetricType.HISTOGRAM,
            description="Workflow duration in seconds",
            unit="seconds",
            buckets=[1, 5, 10, 30, 60, 300, 600, 3600]
        ))

        self.registry.register_metric(MetricDefinition(
            name="workflow_success_rate",
            type=MetricType.GAUGE,
            description="Workflow success rate (0-1)",
            unit="ratio"
        ))

        # System metrics
        self.registry.register_metric(MetricDefinition(
            name="system_cpu_usage",
            type=MetricType.GAUGE,
            description="System CPU usage percentage",
            unit="percent"
        ))

        self.registry.register_metric(MetricDefinition(
            name="system_memory_usage",
            type=MetricType.GAUGE,
            description="System memory usage percentage",
            unit="percent"
        ))

        self.registry.register_metric(MetricDefinition(
            name="system_disk_usage",
            type=MetricType.GAUGE,
            description="System disk usage percentage",
            unit="percent"
        ))

    async def start(self):
        """Start metrics collector"""
        self.logger.info(f"Starting metrics collector on port {self.port}")

        # Start HTTP server for metrics endpoint
        from aiohttp import web

        app = web.Application()
        app.router.add_get('/metrics', self._metrics_handler)
        app.router.add_get('/health', self._health_handler)
        app.router.add_get('/api/v1/metrics', self._api_metrics_handler)

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', self.port)
        await site.start()

        self.server = runner
        self.running = True

        self.logger.info(f"Metrics collector started on port {self.port}")

    async def stop(self):
        """Stop metrics collector"""
        self.logger.info("Stopping metrics collector...")

        self.running = False

        if self.server:
            await self.server.cleanup()

        self.logger.info("Metrics collector stopped")

    async def _metrics_handler(self, request):
        """Prometheus metrics handler"""
        import time

        # Generate Prometheus format metrics
        lines = []

        for metric_name, metric_info in self.registry.get_all_metrics().items():
            definition = metric_info["definition"]
            values = metric_info["values"]

            if definition.type == MetricType.COUNTER:
                lines.append(f"# HELP {metric_name} {definition.description}")
                lines.append(f"# TYPE {metric_name} counter")

                for value in values:
                    labels_str = ','.join([f'{k}="{v}"' for k, v in value.labels.items()])
                    lines.append(f"{metric_name}{{{labels_str}}} {value.value}")

            elif definition.type == MetricType.GAUGE:
                lines.append(f"# HELP {metric_name} {definition.description}")
                lines.append(f"# TYPE {metric_name} gauge")

                for value in values:
                    labels_str = ','.join([f'{k}="{v}"' for k, v in value.labels.items()])
                    lines.append(f"{metric_name}{{{labels_str}}} {value.value}")

            elif definition.type == MetricType.HISTOGRAM:
                lines.append(f"# HELP {metric_name} {definition.description}")
                lines.append(f"# TYPE {metric_name} histogram")

                for value in values:
                    labels_str = ','.join([f'{k}="{v}"' for k, v in value.labels.items()])
                    lines.append(f"{metric_name}_sum{{{labels_str}}} {value.value}")
                    lines.append(f"{metric_name}_count{{{labels_str}}} 1")

                    if definition.buckets:
                        for bucket in definition.buckets:
                            if value.value <= bucket:
                                lines.append(f"{metric_name}_bucket{{{labels_str},le=\"{bucket}\"}} 1")
                            else:
                                lines.append(f"{metric_name}_bucket{{{labels_str},le=\"{bucket}\"}} 0")
                        lines.append(f"{metric_name}_bucket{{{labels_str},le=\"+Inf\"}} 1")

        return web.Response(text='\n'.join(lines), content_type='text/plain; version=0.0.4')

    async def _health_handler(self, request):
        """Health check handler"""
        health = {
            "status": "healthy" if self.running else "unhealthy",
            "timestamp": datetime.now().isoformat(),
            "metrics": {
                "total_metrics": len(self.registry.metrics),
                "total_values": sum(len(v) for v in self.registry.values.values()),
                "uptime_seconds": time.time() - self.start_time if hasattr(self, 'start_time') else 0
            }
        }

        return web.json_response(health)

    async def _api_metrics_handler(self, request):
        """JSON API metrics handler"""
        metrics_data = {
            "metrics": self.registry.get_all_metrics(),
            "summary": self.registry.get_metrics_summary(),
            "timestamp": datetime.now().isoformat()
        }

        return web.json_response(metrics_data)

    # Metric recording methods
    def record_message_processed(self):
        """Record a message being processed"""
        self.registry.record_value("bridge_messages_processed", 1)

    def record_workflow_completed(self):
        """Record a workflow completion"""
        self.registry.record_value("bridge_workflows_completed", 1)

    def record_agent_discovered(self):
        """Record an agent discovery"""
        self.registry.record_value("bridge_agents_discovered", 1)

    def record_error(self, error_type: str = "unknown"):
        """Record an error"""
        self.registry.record_value("bridge_errors", 1, {"error_type": error_type})

    def record_agent_message(self, agent_id: str, status: str, response_time: float):
        """Record agent communication"""
        self.registry.record_value("agent_message_count", 1, {"agent_id": agent_id, "status": status})
        self.registry.record_value("agent_response_time", response_time, {"agent_id": agent_id})

    def record_workflow_task(self, workflow_id: str, task_id: str, duration: float):
        """Record workflow task execution"""
        self.registry.record_value("workflow_task_count", 1, {"workflow_id": workflow_id})
        self.registry.record_value("workflow_duration", duration, {"workflow_id": workflow_id})

    def record_system_metrics(self):
        """Record system metrics"""
        import psutil

        # CPU usage
        cpu_percent = psutil.cpu_percent()
        self.registry.record_value("system_cpu_usage", cpu_percent)

        # Memory usage
        memory = psutil.virtual_memory()
        self.registry.record_value("system_memory_usage", memory.percent)

        # Disk usage
        disk = psutil.disk_usage('/')
        self.registry.record_value("system_disk_usage", disk.percent)

    def record_transport_connection(self, transport_type: str, count: int):
        """Record transport connection count"""
        self.registry.record_value("transport_connections", count, {"transport_type": transport_type})

    def record_transport_latency(self, transport_type: str, latency_ms: float):
        """Record transport latency"""
        self.registry.record_value("transport_message_latency", latency_ms, {"transport_type": transport_type})

    def record_active_agents(self, count: int):
        """Record number of active agents"""
        self.registry.record_value("bridge_active_agents", count)

    def record_running_workflows(self, count: int):
        """Record number of running workflows"""
        self.registry.record_value("bridge_running_workflows", count)

    def update_uptime(self):
        """Update uptime metric"""
        if hasattr(self, 'start_time'):
            uptime = time.time() - self.start_time
            self.registry.record_value("bridge_uptime", uptime)

    def get_metrics(self) -> Dict[str, Any]:
        """Get current metrics"""
        return self.registry.get_all_metrics()

    def get_metric(self, metric_name: str) -> Optional[Dict[str, Any]]:
        """Get specific metric data"""
        metrics_data = self.registry.get_all_metrics()
        return metrics_data.get(metric_name)

    def export_metrics(self, format: str = "json") -> str:
        """Export metrics in specified format"""
        if format == "json":
            return json.dumps(self.get_metrics(), indent=2)
        elif format == "prometheus":
            import io
            lines = []
            for metric_name, metric_info in self.registry.get_all_metrics().items():
                definition = metric_info["definition"]
                values = metric_info["values"]

                if definition.type == MetricType.COUNTER:
                    lines.append(f"# HELP {metric_name} {definition.description}")
                    lines.append(f"# TYPE {metric_name} counter")
                    for value in values:
                        lines.append(f"{metric_name} {value.value}")
                elif definition.type == MetricType.GAUGE:
                    lines.append(f"# HELP {metric_name} {definition.description}")
                    lines.append(f"# TYPE {metric_name} gauge")
                    for value in values:
                        lines.append(f"{metric_name} {value.value}")

            return '\n'.join(lines)
        else:
            raise ValueError(f"Unsupported export format: {format}")


class MetricsExporter:
    """Metrics exporter interface"""

    def __init__(self, collector: MetricsCollector):
        self.collector = collector
        self.logger = logging.getLogger(__name__)

    async def export(self) -> str:
        """Export metrics"""
        raise NotImplementedError

    async def send_to(self, destination: str) -> bool:
        """Send metrics to destination"""
        raise NotImplementedError


class PrometheusExporter(MetricsExporter):
    """Prometheus metrics exporter"""

    def __init__(self, collector: MetricsCollector, pushgateway_url: str = None):
        super().__init__(collector)
        self.pushgateway_url = pushgateway_url
        self.job_name = "a2a-bridge"

    async def export(self) -> str:
        """Export metrics in Prometheus format"""
        lines = []

        for metric_name, metric_info in self.collector.get_all_metrics().items():
            definition = metric_info["definition"]
            values = metric_info["values"]

            if definition.type == MetricType.COUNTER:
                lines.append(f"# HELP {metric_name} {definition.description}")
                lines.append(f"# TYPE {metric_name} counter")

                for value in values:
                    labels_str = ','.join([f'{k}="{v}"' for k, v in value.labels.items()])
                    lines.append(f"{metric_name}{{{labels_str}}} {value.value}")

            elif definition.type == MetricType.GAUGE:
                lines.append(f"# HELP {metric_name} {definition.description}")
                lines.append(f"# TYPE {metric_name} gauge")

                for value in values:
                    labels_str = ','.join([f'{k}="{v}"' for k, v in value.labels.items()])
                    lines.append(f"{metric_name}{{{labels_str}}} {value.value}")

            elif definition.type == MetricType.HISTOGRAM:
                lines.append(f"# HELP {metric_name} {definition.description}")
                lines.append(f"# TYPE {metric_name} histogram")

                for value in values:
                    labels_str = ','.join([f'{k}="{v}"' for k, v in value.labels.items()])
                    lines.append(f"{metric_name}_sum{{{labels_str}}} {value.value}")
                    lines.append(f"{metric_name}_count{{{labels_str}}} 1")

        return '\n'.join(lines)

    async def send_to(self, destination: str) -> bool:
        """Send metrics to Prometheus Pushgateway"""
        try:
            import aiohttp

            metrics_content = await self.export()

            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{destination}/pushgateway/metrics/job/{self.job_name}",
                    data=metrics_content.encode('utf-8'),
                    headers={'Content-Type': 'text/plain'}
                ) as response:
                    return response.status == 200

        except Exception as e:
            self.logger.error(f"Failed to send metrics to Pushgateway: {e}")
            return False


class MetricsAggregator:
    """Metrics aggregator for combining multiple metrics"""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.collectors: List[MetricsCollector] = []

    def add_collector(self, collector: MetricsCollector):
        """Add a metrics collector"""
        self.collectors.append(collector)

    def remove_collector(self, collector: MetricsCollector):
        """Remove a metrics collector"""
        if collector in self.collectors:
            self.collectors.remove(collector)

    async def aggregate_metrics(self) -> Dict[str, Any]:
        """Aggregate metrics from all collectors"""
        aggregated = {}

        for collector in self.collectors:
            metrics = collector.get_metrics()
            for metric_name, metric_data in metrics.items():
                if metric_name not in aggregated:
                    aggregated[metric_name] = {
                        "collectors": [],
                        "values": []
                    }

                aggregated[metric_name]["collectors"].append({
                    "collector_id": id(collector),
                    "data": metric_data
                })

                aggregated[metric_name]["values"].extend(metric_data["values"])

        return aggregated

    async def export_aggregated_metrics(self, format: str = "json") -> str:
        """Export aggregated metrics"""
        aggregated = await self.aggregate_metrics()

        if format == "json":
            return json.dumps(aggregated, indent=2)
        else:
            raise ValueError(f"Unsupported export format: {format}")


class MetricsManager:
    """Metrics management system"""

    def __init__(self, port: int = 8000):
        self.port = port
        self.logger = logging.getLogger(__name__)
        self.collector = MetricsCollector(port)
        self.aggregator = MetricsAggregator()
        self.exporters: List[MetricsExporter] = []
        self.running = False

    async def start(self):
        """Start metrics manager"""
        self.logger.info("Starting metrics manager...")

        # Add primary collector to aggregator
        self.aggregator.add_collector(self.collector)

        # Start primary collector
        await self.collector.start()

        self.running = True
        self.logger.info("Metrics manager started successfully")

    async def stop(self):
        """Stop metrics manager"""
        self.logger.info("Stopping metrics manager...")

        self.running = False

        # Stop exporters
        for exporter in self.exporters:
            if hasattr(exporter, 'stop'):
                await exporter.stop()

        # Stop collector
        await self.collector.stop()

        self.logger.info("Metrics manager stopped successfully")

    def add_exporter(self, exporter: MetricsExporter):
        """Add metrics exporter"""
        self.exporters.append(exporter)

    async def export_all_metrics(self) -> Dict[str, str]:
        """Export metrics using all exporters"""
        results = {}

        for exporter in self.exporters:
            try:
                export_data = await exporter.export()
                results[exporter.__class__.__name__] = export_data
            except Exception as e:
                self.logger.error(f"Failed to export with {exporter.__class__.__name__}: {e}")

        return results

    # Convenience methods for recording metrics
    def record(self, metric_name: str, value: float, labels: Dict[str, str] = None):
        """Record a metric value"""
        self.collector.registry.record_value(metric_name, value, labels or {})

    def increment(self, metric_name: str, value: float = 1.0, labels: Dict[str, str] = None):
        """Increment a counter metric"""
        current_value = self.collector.registry.get_values(metric_name)
        if current_value:
            new_value = current_value[-1].value + value
        else:
            new_value = value
        self.record(metric_name, new_value, labels)

    def decrement(self, metric_name: str, value: float = 1.0, labels: Dict[str, str] = None):
        """Decrement a gauge metric"""
        current_value = self.collector.registry.get_values(metric_name)
        if current_value:
            new_value = max(0, current_value[-1].value - value)
        else:
            new_value = 0
        self.record(metric_name, new_value, labels)

    def get_metric(self, metric_name: str) -> Optional[Dict[str, Any]]:
        """Get metric data"""
        return self.collector.get_metric(metric_name)

    def get_all_metrics(self) -> Dict[str, Any]:
        """Get all metrics"""
        return self.collector.get_metrics()

    async def get_aggregated_metrics(self) -> Dict[str, Any]:
        """Get aggregated metrics"""
        return await self.aggregator.aggregate_metrics()