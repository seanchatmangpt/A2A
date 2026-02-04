"""
Configuration system for Craftplan MCP + A2A + elrmcp integration.

This package provides hierarchical configuration management with support for:
- Environment variables
- Configuration file loading (JSON, YAML, TOML)
- Dynamic configuration reloading
- Configuration validation and schema checking
- Multi-environment support
"""

__version__ = "0.1.0"
__all__ = ["Config", "ConfigLoader", "ConfigValidator", "ConfigSchema"]