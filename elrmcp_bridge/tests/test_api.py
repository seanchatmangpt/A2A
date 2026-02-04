"""
Tests for REST API functionality
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from aiohttp import web
import json

from elrmcp_bridge.src.api.server import APIServer
from elrmcp_bridge.src.api.endpoints import APIEndpoints
from elrmcp_bridge.src.bridge import A2ABridge
from elrmcp_bridge.src.config import BridgeConfig


class TestAPIServer:
    """Test APIServer class"""

    @pytest.fixture
    def mock_config(self):
        """Create mock configuration"""
        config = Mock(spec=BridgeConfig)
        config.host = "localhost"
        config.port = 8001
        config.api_enabled = True
        config.api_prefix = "/api"
        config.api_workers = 2
        return config

    @pytest.fixture
    def mock_bridge(self):
        """Create mock bridge"""
        bridge = Mock(spec=A2ABridge)
        bridge.health_check = AsyncMock(return_value={"status": "healthy", "timestamp": "2023-01-01T00:00:00Z"})
        bridge.get_bridge_status = AsyncMock(return_value={
            "state": "running",
            "uptime": 60.0,
            "metrics": {"total_messages_processed": 10}
        })
        bridge.get_agent_status = AsyncMock(return_value={"agents": []})
        bridge.send_to_agent = AsyncMock(return_value={"result": "success"})
        bridge.start_workflow = AsyncMock(return_value="workflow-123")
        bridge.get_workflow_status = AsyncMock(return_value={"status": "running"})
        bridge.cancel_workflow = AsyncMock(return_value=True)
        return bridge

    @pytest.fixture
    def api_server(self, mock_config, mock_bridge):
        """Create APIServer instance"""
        return APIServer(mock_config, mock_bridge)

    @pytest.mark.asyncio
    async def test_api_server_initialization(self, api_server):
        """Test API server initialization"""
        assert api_server.config is not None
        assert api_server.bridge is not None
        assert api_server.app is not None
        assert api_server.runner is None
        assert api_server.site is None

    @pytest.mark.asyncio
    async def test_api_server_start(self, api_server):
        """Test API server start"""
        with patch('elrmcp_bridge.src.api.server.web.AppRunner'), \
             patch('elrmcp_bridge.src.api.server.web.TCPSite') as mock_site, \
             patch('aiohttp.web.run_app') as mock_run_app:

            mock_runner = Mock()
            mock_site.return_value = Mock()
            api_server.app.runner = mock_runner

            await api_server.start()

            api_server.app.setup.assert_called_once()
            mock_runner.setup.assert_called_once()
            mock_runner.start.assert_called_once()
            mock_site.assert_called_once()
            mock_run_app.assert_called_once()

    @pytest.mark.asyncio
    async def test_api_server_stop(self, api_server):
        """Test API server stop"""
        mock_runner = Mock()
        api_server.app.runner = mock_runner

        await api_server.stop()

        mock_runner.stop.assert_called_once()

    def test_setup_routes(self, api_server):
        """Test route setup"""
        api_server._setup_routes()

        # Check if routes are set up
        routes = api_server.app.router.routes()
        route_paths = [route.resource.canonical for route in routes]

        assert "/api/health" in route_paths
        assert "/api/bridge/status" in route_paths
        assert "/api/agents" in route_paths
        assert "/api/agents/{agent_id}" in route_paths
        assert "/api/workflows" in route_paths
        assert "/api/workflows/{workflow_id}" in route_paths

    @pytest.mark.asyncio
    async def test_health_check_endpoint(self, api_server):
        """Test health check endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}

        response = await api_server._health_check(request)

        assert response.status == 200
        data = await response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data

    @pytest.mark.asyncio
    async def test_bridge_status_endpoint(self, api_server):
        """Test bridge status endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}

        response = await api_server._bridge_status(request)

        assert response.status == 200
        data = await response.json()
        assert data["state"] == "running"
        assert "uptime" in data

    @pytest.mark.asyncio
    async def test_list_agents_endpoint(self, api_server):
        """Test list agents endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}

        response = await api_server._list_agents(request)

        assert response.status == 200
        data = await response.json()
        assert "agents" in data

    @pytest.mark.asyncio
    async def test_get_agent_endpoint(self, api_server):
        """Test get agent endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {"agent_id": "agent-1"}

        api_server.bridge.get_agent = AsyncMock(return_value={"agent_id": "agent-1"})

        response = await api_server._get_agent(request)

        assert response.status == 200
        data = await response.json()
        assert data["agent_id"] == "agent-1"

    @pytest.mark.asyncio
    async def test_get_agent_not_found(self, api_server):
        """Test get agent not found"""
        request = Mock()
        request.method = "GET"
        request.match_info = {"agent_id": "non-existent"}

        api_server.bridge.get_agent = AsyncMock(return_value=None)

        response = await api_server._get_agent(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_register_agent_endpoint(self, api_server):
        """Test register agent endpoint"""
        request = Mock()
        request.method = "POST"
        request.match_info = {}
        request.json = AsyncMock(return_value={
            "agent_id": "new-agent",
            "name": "New Agent",
            "capabilities": ["test"]
        })

        api_server.bridge.register_agent = AsyncMock(return_value=True)

        response = await api_server._register_agent(request)

        assert response.status == 201
        data = await response.json()
        assert data["agent_id"] == "new-agent"

    @pytest.mark.asyncio
    async def test_register_agent_invalid(self, api_server):
        """Test register agent with invalid data"""
        request = Mock()
        request.method = "POST"
        request.match_info = {}
        request.json = AsyncMock(return_value={})

        response = await api_server._register_agent(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_start_workflow_endpoint(self, api_server):
        """Test start workflow endpoint"""
        request = Mock()
        request.method = "POST"
        request.match_info = {}
        request.json = AsyncMock(return_value={
            "workflow_id": "test-workflow",
            "tasks": []
        })

        response = await api_server._start_workflow(request)

        assert response.status == 201
        data = await response.json()
        assert data["workflow_id"] == "workflow-123"

    @pytest.mark.asyncio
    async def test_get_workflow_endpoint(self, api_server):
        """Test get workflow endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {"workflow_id": "workflow-123"}

        response = await api_server._get_workflow(request)

        assert response.status == 200
        data = await response.json()
        assert data["status"] == "running"

    @pytest.mark.asyncio
    async def test_cancel_workflow_endpoint(self, api_server):
        """Test cancel workflow endpoint"""
        request = Mock()
        request.method = "PUT"
        request.match_info = {"workflow_id": "workflow-123"}

        response = await api_server._cancel_workflow(request)

        assert response.status == 200
        data = await response.json()
        assert data["success"] is True

    @pytest.mark.asyncio
    async def test_get_metrics_endpoint(self, api_server):
        """Test get metrics endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}

        api_server.bridge.get_bridge_metrics = AsyncMock(return_value={
            "metrics": {"total_messages_processed": 10},
            "uptime": 60.0
        })

        response = await api_server._get_metrics(request)

        assert response.status == 200
        data = await response.json()
        assert "metrics" in data

    @pytest.mark.asyncio
    async def test_system_info_endpoint(self, api_server):
        """Test system info endpoint"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}

        response = await api_server._system_info(request)

        assert response.status == 200
        data = await response.json()
        assert "platform" in data
        assert "version" in data

    @pytest.mark.asyncio
    async def test_cors_middleware(self, api_server):
        """Test CORS middleware"""
        request = Mock()
        request.method = "OPTIONS"
        request.headers = {"Origin": "http://localhost:3000"}
        request.match_info = {}

        with patch('aiohttp.web.Response') as mock_response:
            mock_response.return_value = Mock()
            api_server.app.router.add_route = Mock()

            await api_server._cors_middleware(request, lambda: None)

            # Check CORS headers
            assert "Access-Control-Allow-Origin" in request.headers

    def test_method_not_allowed(self, api_server):
        """Test method not allowed error"""
        from aiohttp import web

        # Try to use unsupported method
        with pytest.raises(web.HTTPMethodNotAllowed):
            api_server._not_allowed()

    def test_not_found(self, api_server):
        """Test not found error"""
        from aiohttp import web

        # Try to access non-existent route
        with pytest.raises(web.HTTPNotFound):
            api_server._not_found()

    @pytest.mark.asyncio
    async def test_error_handling(self, api_server):
        """Test error handling"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}

        # Mock endpoint that raises exception
        async def error_endpoint(request):
            raise Exception("Test error")

        api_server.app.router.add_get("/api/error", error_endpoint)

        response = await api_server.app.router.resolve(request.match_info)[0].handler(request)

        assert response.status == 500
        data = await response.json()
        assert "error" in data

    @pytest.mark.asyncio
    async def test_rate_limiting(self, api_server):
        """Test rate limiting"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}
        request.headers = {"X-Forwarded-For": "127.0.0.1"}

        # Mock multiple requests from same IP
        responses = []
        for i in range(5):
            response = await api_server._health_check(request)
            responses.append(response)

        # After limit reached, should get 429
        assert len([r for r in responses if r.status == 429]) > 0

    def test_api_documentation(self, api_server):
        """Test API documentation"""
        docs = api_server._get_api_docs()

        assert "endpoints" in docs
        assert "version" in docs
        assert "Base URL" in docs
        assert "Health" in docs["endpoints"]

    @pytest.mark.asyncio
    async def test_webhook_endpoint(self, api_server):
        """Test webhook endpoint"""
        request = Mock()
        request.method = "POST"
        request.match_info = {}
        request.json = AsyncMock(return_value={
            "event": "workflow.completed",
            "data": {"workflow_id": "123"}
        })

        response = await api_server._webhook(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_bulk_operations(self, api_server):
        """Test bulk operations"""
        request = Mock()
        request.method = "POST"
        request.match_info = {}
        request.json = AsyncMock(return_value={
            "operations": [
                {"type": "register_agent", "data": {"agent_id": "bulk-1"}},
                {"type": "start_workflow", "data": {"workflow_id": "bulk-1"}}
            ]
        })

        api_server.bridge.register_agent = AsyncMock(return_value=True)
        api_server.bridge.start_workflow = AsyncMock(return_value="workflow-123")

        response = await api_server._bulk_operations(request)

        assert response.status == 200
        data = await response.json()
        assert len(data["results"]) == 2

    def test_request_validation(self, api_server):
        """Test request validation"""
        # Valid request
        valid_data = {
            "agent_id": "test-agent",
            "name": "Test Agent"
        }
        assert api_server._validate_agent_data(valid_data) is True

        # Invalid request
        invalid_data = {
            "name": "Test Agent"  # Missing required field
        }
        assert api_server._validate_agent_data(invalid_data) is False

    @pytest.mark.asyncio
    async def test_authenticated_endpoints(self, api_server):
        """Test authenticated endpoints"""
        request = Mock()
        request.method = "GET"
        request.match_info = {}
        request.headers = {}  # No auth header

        # Test without authentication
        response = await api_server._authenticated_endpoint(request)
        assert response.status == 401

        # Test with valid authentication
        request.headers = {"Authorization": "Bearer valid-token"}
        api_server._validate_token = Mock(return_value=True)

        response = await api_server._authenticated_endpoint(request)
        assert response.status == 200

    def test_token_validation(self, api_server):
        """Test token validation"""
        # Valid token
        assert api_server._validate_token("valid-token") is True

        # Invalid token
        assert api_server._validate_token("invalid-token") is False

    @pytest.mark.asyncio
    async def test_concurrent_requests(self, api_server):
        """Test handling concurrent requests"""
        import asyncio

        # Create multiple concurrent requests
        tasks = []
        for i in range(5):
            request = Mock()
            request.method = "GET"
            request.match_info = {}
            api_server.bridge.health_check = AsyncMock(return_value={"status": "healthy"})

            task = api_server._health_check(request)
            tasks.append(task)

        responses = await asyncio.gather(*tasks)

        # All requests should succeed
        assert len(responses) == 5
        for response in responses:
            assert response.status == 200