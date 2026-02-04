"""
Tests for MetricsCollector functionality
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime, timedelta

from elrmcp_bridge.src.metrics import MetricsCollector, MetricType, MetricDefinition, MetricValue


class TestMetricsCollector:
    """Test MetricsCollector class"""

    @pytest.fixture
    def metrics_config(self):
        """Create metrics configuration"""
        config = Mock()
        config.enabled = True
        config.port = 8000
        config.prefix = "elrmcp_bridge"
        config.labels = {"env": "test"}
        config.interval = 60
        return config

    @pytest.fixture
    def metrics_collector(self, metrics_config):
        """Create MetricsCollector instance"""
        return MetricsCollector(metrics_config)

    def test_metrics_collector_initialization(self, metrics_collector):
        """Test MetricsCollector initialization"""
        assert metrics_collector.config.enabled is True
        assert metrics_collector.config.port == 8000
        assert metrics_collector.config.prefix == "elrmcp_bridge"
        assert metrics_collector.config.labels == {"env": "test"}
        assert metrics_collector.registry is not None
        assert metrics_collector.prometheus_server is not None
        assert metrics_collector.collection_interval is None

    def test_register_metric(self, metrics_collector):
        """Test metric registration"""
        metric_def = MetricDefinition(
            name="test_metric",
            type=MetricType.COUNTER,
            description="Test metric",
            labels=["label1", "label2"]
        )

        metrics_collector.register_metric(metric_def)

        # Check if metric is registered
        metrics = metrics_collector.registry.get_metrics()
        assert "test_metric" in metrics
        assert metrics["test_metric"]["type"] == MetricType.COUNTER

    def test_register_duplicate_metric(self, metrics_collector):
        """Test registering duplicate metric"""
        metric_def = MetricDefinition(
            name="test_metric",
            type=MetricType.COUNTER,
            description="Test metric"
        )

        # Register first time
        metrics_collector.register_metric(metric_def)

        # Register same metric again - should not raise error
        metrics_collector.register_metric(metric_def)

        # Should still be registered once
        metrics = metrics_collector.registry.get_metrics()
        assert len([m for m in metrics.values() if m["name"] == "test_metric"]) == 1

    def test_increment_counter(self, metrics_collector):
        """Test counter increment"""
        metric_def = MetricDefinition(
            name="messages_processed",
            type=MetricType.COUNTER,
            description="Messages processed"
        )

        metrics_collector.register_metric(metric_def)

        # Increment counter
        metrics_collector.increment("messages_processed", 5)
        metrics_collector.increment("messages_processed", 3)

        # Check value
        value = metrics_collector.get_metric_value("messages_processed")
        assert value == 8

    def test_set_gauge(self, metrics_collector):
        """Test gauge setting"""
        metric_def = MetricDefinition(
            name="active_connections",
            type=MetricType.GAUGE,
            description="Active connections"
        )

        metrics_collector.register_metric(metric_def)

        # Set gauge value
        metrics_collector.set_gauge("active_connections", 10)
        metrics_collector.set_gauge("active_connections", 15)

        # Check value
        value = metrics_collector.get_metric_value("active_connections")
        assert value == 15

    def test_histogram(self, metrics_collector):
        """Test histogram operations"""
        metric_def = MetricDefinition(
            name="request_duration",
            type=MetricType.HISTOGRAM,
            description="Request duration"
        )

        metrics_collector.register_metric(metric_def)

        # Record observations
        metrics_collector.record_histogram("request_duration", 100)
        metrics_collector.record_histogram("request_duration", 200)
        metrics_collector.record_histogram("request_duration", 300)

        # Check histogram values
        histogram = metrics_collector.get_histogram_values("request_duration")
        assert histogram["count"] == 3
        assert histogram["sum"] == 600
        assert histogram["bucket"] == {
            "+Inf": 3,
            "300": 3,
            "200": 2,
            "100": 1
        }

    def test_metric_not_found(self, metrics_collector):
        """Test accessing non-existent metric"""
        with pytest.raises(Exception, match="Metric not found"):
            metrics_collector.get_metric_value("nonexistent_metric")

    @pytest.mark.asyncio
    async def test_start_metrics_collection(self, metrics_collector):
        """Test starting metrics collection"""
        mock_interval = AsyncMock()
        metrics_collector._collect_metrics_interval = mock_interval

        await metrics_collector.start_metrics_collection()

        assert metrics_collector.collection_interval is not None
        mock_interval.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_metrics_collection(self, metrics_collector):
        """Test stopping metrics collection"""
        mock_interval = AsyncMock()
        mock_interval.is_running = True
        mock_interval.stop = Mock()
        metrics_collector.collection_interval = mock_interval

        await metrics_collector.stop_metrics_collection()

        mock_interval.stop.assert_called_once()
        assert metrics_collector.collection_interval is None

    @pytest.mark.asyncio
    async def test_collect_metrics(self, metrics_collector):
        """Test metrics collection"""
        # Register some metrics
        metrics_collector.register_metric(MetricDefinition(
            name="test_counter",
            type=MetricType.COUNTER,
            description="Test counter"
        ))
        metrics_collector.register_metric(MetricDefinition(
            name="test_gauge",
            type=MetricType.GAUGE,
            description="Test gauge"
        ))

        # Set some values
        metrics_collector.increment("test_counter", 10)
        metrics_collector.set_gauge("test_gauge", 25)

        # Collect metrics
        metrics = await metrics_collector.collect_metrics()

        assert "test_counter" in metrics
        assert "test_gauge" in metrics
        assert metrics["test_counter"]["value"] == 10
        assert metrics["test_gauge"]["value"] == 25

    def test_get_prometheus_format(self, metrics_collector):
        """Test Prometheus format output"""
        # Register metrics
        metrics_collector.register_metric(MetricDefinition(
            name="test_counter",
            type=MetricType.COUNTER,
            description="Test counter"
        ))
        metrics_collector.register_metric(MetricDefinition(
            name="test_gauge",
            type=MetricType.GAUGE,
            description="Test gauge"
        ))

        # Set values
        metrics_collector.increment("test_counter", 10)
        metrics_collector.set_gauge("test_gauge", 25)

        # Get Prometheus format
        prometheus_output = metrics_collector.get_prometheus_format()

        # Should be valid Prometheus format
        assert "elrmcp_bridge_test_counter" in prometheus_output
        assert "elrmcp_bridge_test_gauge" in prometheus_output
        assert "test_counter 10" in prometheus_output
        assert "test_gauge 25" in prometheus_output

    @pytest.mark.asyncio
    async def start_prometheus_server(self, metrics_collector):
        """Test starting Prometheus server"""
        mock_server = AsyncMock()
        metrics_collector.prometheus_server = mock_server

        await metrics_collector.start_prometheus_server()

        mock_server.start.assert_called_once()

    @pytest.mark.asyncio
    async def stop_prometheus_server(self, metrics_collector):
        """Test stopping Prometheus server"""
        mock_server = AsyncMock()
        mock_server.is_running = True
        mock_server.stop = Mock()
        metrics_collector.prometheus_server = mock_server

        await metrics_collector.stop_prometheus_server()

        mock_server.stop.assert_called_once()

    def test_metric_labels(self, metrics_collector):
        """Test metric labels"""
        metric_def = MetricDefinition(
            name="labeled_metric",
            type=MetricType.COUNTER,
            description="Labeled metric",
            labels=["env", "version"]
        )

        metrics_collector.register_metric(metric_def)

        # Increment with labels
        metrics_collector.increment("labeled_metric", 5, labels={"env": "prod", "version": "1.0"})

        # Get value with specific labels
        value = metrics_collector.get_metric_value("labeled_metric", labels={"env": "prod", "version": "1.0"})
        assert value == 5

    def test_metric_aggregation(self, metrics_collector):
        """Test metric aggregation"""
        # Register multiple metrics with same name
        metrics_collector.register_metric(MetricDefinition(
            name="system_memory",
            type=MetricType.GAUGE,
            description="System memory"
        ))

        # Set multiple values (simulating different instances)
        metrics_collector.set_gauge("system_memory", 100, labels={"instance": "1"})
        metrics_collector.set_gauge("system_memory", 200, labels={"instance": "2"})

        # Aggregate values
        aggregated = metrics_collector.aggregate_metrics("system_memory", operation="sum")
        assert aggregated == 300

    def test_metric_export_json(self, metrics_collector):
        """Test JSON export"""
        # Register and set metrics
        metrics_collector.register_metric(MetricDefinition(
            name="test_metric",
            type=MetricType.COUNTER,
            description="Test metric"
        ))
        metrics_collector.increment("test_metric", 42)

        # Export to JSON
        json_output = metrics_collector.export_metrics(format="json")

        # Should be valid JSON
        import json
        data = json.loads(json_output)
        assert "test_metric" in data
        assert data["test_metric"]["value"] == 42

    def test_metric_export_csv(self, metrics_collector):
        """Test CSV export"""
        # Register and set metrics
        metrics_collector.register_metric(MetricDefinition(
            name="test_counter",
            type=MetricType.COUNTER,
            description="Test counter"
        ))
        metrics_collector.increment("test_counter", 100)

        # Export to CSV
        csv_output = metrics_collector.export_metrics(format="csv")

        # Should be valid CSV
        lines = csv_output.strip().split('\n')
        assert len(lines) > 1  # Header + data
        assert "name" in lines[0]
        assert "test_counter" in lines[1]

    @pytest.mark.asyncio
    async def test_metrics_alerting(self, metrics_collector):
        """Test metrics alerting"""
        # Register alert
        metrics_collector.register_alert(
            "high_error_rate",
            "error_count",
            100,
            "critical"
        )

        # Set high value
        metrics_collector.register_metric(MetricDefinition(
            name="error_count",
            type=MetricType.COUNTER,
            description="Error count"
        ))
        metrics_collector.increment("error_count", 150)

        # Check alert
        alerts = metrics_collector.check_alerts()
        assert len(alerts) > 0
        assert alerts[0]["metric"] == "error_count"
        assert alerts[0]["severity"] == "critical"

    def test_metric_metadata(self, metrics_collector):
        """Test metric metadata"""
        metric_def = MetricDefinition(
            name="test_metric",
            type=MetricType.COUNTER,
            description="Test metric",
            unit="seconds"
        )

        # Get metric metadata
        metadata = metrics_collector.get_metric_metadata("test_metric")
        assert metadata["description"] == "Test metric"
        assert metadata["type"] == MetricType.COUNTER
        assert metadata["unit"] == "seconds"

    def test_metrics_cleanup(self, metrics_collector):
        """Test metrics cleanup"""
        # Register some metrics
        metrics_collector.register_metric(MetricDefinition(
            name="temp_metric",
            type=MetricType.COUNTER,
            description="Temporary metric"
        ))

        # Set values
        metrics_collector.increment("temp_metric", 10)

        # Clean up old metrics
        metrics_collector.cleanup_old_metrics(max_age_seconds=0)

        # Metric should be removed
        with pytest.raises(Exception, match="Metric not found"):
            metrics_collector.get_metric_value("temp_metric")

    @pytest.mark.asyncio
    async def test_metrics_batch_update(self, metrics_collector):
        """Test batch metrics update"""
        # Register metrics
        metrics = [
            MetricDefinition(name="metric1", type=MetricType.COUNTER, description="Metric 1"),
            MetricDefinition(name="metric2", type=MetricType.GAUGE, description="Metric 2")
        ]
        metrics_collector.register_metrics(metrics)

        # Batch update
        updates = {
            "metric1": {"value": 10, "type": "increment"},
            "metric2": {"value": 20, "type": "set"}
        }
        metrics_collector.batch_update(updates)

        # Check values
        assert metrics_collector.get_metric_value("metric1") == 10
        assert metrics_collector.get_metric_value("metric2") == 20

    def test_metrics_query_language(self, metrics_collector):
        """Test metrics query language"""
        # Register metrics
        metrics = [
            MetricDefinition(name="cpu_usage", type=MetricType.GAUGE, description="CPU usage"),
            MetricDefinition(name="memory_usage", type=MetricType.GAUGE, description="Memory usage")
        ]
        metrics_collector.register_metrics(metrics)

        # Set values
        metrics_collector.set_gauge("cpu_usage", 80)
        metrics_collector.set_gauge("memory_usage", 60)

        # Query metrics
        query = "SELECT * WHERE value > 50"
        result = metrics_collector.query_metrics(query)

        # Should return metrics with values > 50
        assert len(result) == 2  # Both CPU and memory are > 50