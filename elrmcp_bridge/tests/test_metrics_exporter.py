"""Tests for JSONMetricsExporter."""

import asyncio
import importlib.util
import json
import pathlib
import sys
import pytest
from unittest.mock import MagicMock

# Import metrics module directly to avoid triggering the package __init__.py,
# which has heavy optional dependencies (websockets, aiohttp, etc.).
_spec = importlib.util.spec_from_file_location(
    "elrmcp_bridge_metrics",
    pathlib.Path(__file__).parent.parent / "src" / "metrics.py",
)
_metrics_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_metrics_mod)
JSONMetricsExporter = _metrics_mod.JSONMetricsExporter


def _make_collector(metric_names: list):
    """Return a mock MetricsCollector whose get_all_metrics() returns a dict keyed by name."""
    collector = MagicMock()
    collector.get_all_metrics.return_value = {name: {} for name in metric_names}
    return collector


class TestJSONMetricsExporter:
    @pytest.fixture
    def metric_names(self):
        return ["requests_total", "latency_seconds", "errors_total"]

    @pytest.fixture
    def exporter(self, metric_names):
        return JSONMetricsExporter(_make_collector(metric_names))

    def test_export_returns_valid_json(self, exporter, metric_names):
        result = asyncio.run(exporter.export())
        parsed = json.loads(result)  # must not raise
        assert "metrics" in parsed
        assert set(parsed["metrics"]) == set(metric_names)

    def test_export_empty_collector(self):
        exporter = JSONMetricsExporter(_make_collector([]))
        result = asyncio.run(exporter.export())
        parsed = json.loads(result)
        assert parsed == {"metrics": []}

    def test_send_to_writes_file(self, exporter, metric_names, tmp_path):
        dest = tmp_path / "metrics.json"
        ok = asyncio.run(exporter.send_to(str(dest)))
        assert ok is True
        assert dest.exists()
        parsed = json.loads(dest.read_text())
        assert set(parsed["metrics"]) == set(metric_names)

    def test_send_to_returns_false_on_invalid_path(self, exporter):
        ok = asyncio.run(exporter.send_to("/no/such/directory/metrics.json"))
        assert ok is False
