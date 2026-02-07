"""Tests for health and system endpoints."""

import pytest
from datetime import datetime


@pytest.mark.asyncio
class TestHealthEndpoints:
    """Test suite for health check endpoints."""

    async def test_health_check_success(self, api_client):
        """Test health check endpoint returns healthy status."""
        response = await api_client.get("/health")
        assert response.status == 200

        data = await response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data
        assert "version" in data

    async def test_health_check_response_format(self, api_client):
        """Test health check response has correct format."""
        response = await api_client.get("/health")
        data = await response.json()

        # Validate timestamp format
        timestamp = data.get("timestamp")
        assert timestamp is not None
        # Should be ISO format
        datetime.fromisoformat(timestamp)

    async def test_bridge_status(self, api_client):
        """Test bridge status endpoint."""
        response = await api_client.get("/bridge/status")
        assert response.status == 200

        data = await response.json()
        assert "state" in data
        assert "uptime" in data
        assert "metrics" in data

    async def test_bridge_status_metrics(self, api_client):
        """Test bridge status includes metrics."""
        response = await api_client.get("/bridge/status")
        data = await response.json()

        metrics = data.get("metrics", {})
        assert "total_messages_processed" in metrics
        assert "total_workflows_completed" in metrics
        assert "total_agents_discovered" in metrics
        assert metrics["total_messages_processed"] >= 0

    async def test_system_info(self, api_client):
        """Test system info endpoint."""
        response = await api_client.get("/system/info")
        assert response.status == 200

        data = await response.json()
        assert "platform" in data
        assert "python_version" in data
        assert "cpu_count" in data
        assert "memory_total" in data
        assert "timestamp" in data

    async def test_system_info_values(self, api_client):
        """Test system info has valid values."""
        response = await api_client.get("/system/info")
        data = await response.json()

        assert data["cpu_count"] > 0
        assert data["memory_total"] > 0
        assert data["memory_available"] >= 0
        assert 0 <= data["disk_usage"] <= 100

    async def test_metrics_endpoint(self, api_client):
        """Test metrics endpoint."""
        response = await api_client.get("/metrics")
        assert response.status == 200

        data = await response.json()
        assert "bridge_metrics" in data
        assert "protocol_metrics" in data
        assert "timestamp" in data

    async def test_metrics_protocol_data(self, api_client):
        """Test protocol metrics data."""
        response = await api_client.get("/metrics")
        data = await response.json()

        protocol_metrics = data.get("protocol_metrics", {})
        assert "requests_total" in protocol_metrics
        assert "errors_total" in protocol_metrics
        assert "average_latency" in protocol_metrics

    async def test_system_logs(self, api_client):
        """Test system logs endpoint."""
        response = await api_client.get("/system/logs")
        assert response.status == 200

        data = await response.json()
        assert "logs" in data
        assert "count" in data
        assert "timestamp" in data
        assert isinstance(data["logs"], list)


@pytest.mark.asyncio
class TestConfigEndpoints:
    """Test suite for configuration endpoints."""

    async def test_get_config(self, api_client):
        """Test get configuration endpoint."""
        response = await api_client.get("/config")
        assert response.status == 200

        data = await response.json()
        assert "bridge" in data or "system" in data

    async def test_get_config_system_settings(self, api_client):
        """Test config includes system settings."""
        response = await api_client.get("/config")
        data = await response.json()

        if "system" in data:
            system = data["system"]
            assert "host" in system
            assert "port" in system
            assert "debug" in system


@pytest.mark.asyncio
class TestCORSHeaders:
    """Test suite for CORS functionality."""

    async def test_cors_headers_present(self, api_client):
        """Test CORS headers are present in responses."""
        response = await api_client.get("/health")

        assert "Access-Control-Allow-Origin" in response.headers
        assert response.headers["Access-Control-Allow-Origin"] == "*"

    async def test_cors_allowed_methods(self, api_client):
        """Test CORS allowed methods header."""
        response = await api_client.get("/health")

        if "Access-Control-Allow-Methods" in response.headers:
            methods = response.headers["Access-Control-Allow-Methods"]
            assert "GET" in methods
            assert "POST" in methods


@pytest.mark.asyncio
class TestErrorHandling:
    """Test suite for API error handling."""

    async def test_404_not_found(self, api_client):
        """Test 404 error for non-existent endpoint."""
        response = await api_client.get("/nonexistent")
        assert response.status == 404

    async def test_invalid_agent_id(self, api_client):
        """Test error handling for invalid agent ID."""
        response = await api_client.get("/agents/invalid-agent-999")
        # Should return error (500 or 404)
        assert response.status >= 400
