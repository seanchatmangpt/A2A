"""
Comprehensive Test Suite for Craftplan MCP + A2A Integration

This package provides a complete testing framework for the integration of:
- Craftplan MCP Server
- A2A Agent
- elrmcp integration
- Multi-agent workflows

Test Structure:
- unit/ - Individual component tests
- integration/ - System interaction tests
- e2e/ - End-to-end workflow tests
- performance/ - Performance and load testing
- security/ - Security and penetration testing
- utils/ - Testing utilities and helpers
- fixtures/ - Test data and mock servers
- config/ - Test configuration files
"""

__version__ = "0.1.0"
__all__ = [
    "test_runner",
    "test_utils",
    "test_config",
    "test_fixtures",
    "mcp_tests",
    "a2a_tests",
    "integration_tests",
    "e2e_tests",
    "performance_tests",
    "security_tests"
]