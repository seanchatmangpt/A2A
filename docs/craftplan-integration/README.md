# Craftplan MCP + A2A Integration Documentation

Welcome to the comprehensive documentation for the Craftplan MCP + A2A integration. This documentation covers all aspects of integrating Model Context Protocol (MCP) servers with the Agent2Agent (A2A) Protocol for enterprise ERP systems.

## 📚 Documentation Structure

This documentation is organized into several main sections:

### 🏗️ System Documentation
- [Architecture Overview](./system/architecture-overview.md) - High-level system design and components
- [Component Descriptions](./system/component-descriptions.md) - Detailed breakdown of each component
- [Data Flow Diagrams](./system/data-flow-diagrams.md) - Visual representation of data flow
- [Integration Patterns](./system/integration-patterns.md) - Common integration patterns and approaches
- [Best Practices](./system/best-practices.md) - Industry best practices for implementation

### 📖 User Guides
- [Installation and Setup](./user-guides/installation-setup.md) - Step-by-step installation guide
- [Configuration Guide](./user-guides/configuration.md) - Configuration options and parameters
- [Usage Examples](./user-guides/usage-examples.md) - Practical usage examples and scenarios
- [Troubleshooting Guide](./user-guides/troubleshooting.md) - Common issues and solutions
- [FAQ Section](./user-guides/faq.md) - Frequently asked questions

### 🔌 API Documentation
- [MCP Tool Documentation](./api/mcp-tools.md) - MCP server tools and their usage
- [A2A Protocol Documentation](./api/a2a-protocol.md) - A2A protocol implementation details
- [Configuration API](./api/configuration-api.md) - API for configuration management
- [Management API](./api/management-api.md) - Management and monitoring APIs
- [Webhook Documentation](./api/webhooks.md) - Webhook integration and events

### 👨‍💻 Developer Documentation
- [Development Setup](./development/setup.md) - Setting up the development environment
- [Code Structure](./development/code-structure.md) - Understanding the codebase structure
- [Testing Guidelines](./development/testing.md) - Testing approach and guidelines
- [Contributing Guidelines](./development/contributing.md) - How to contribute to the project
- [Extension Development](./development/extension-development.md) - Creating custom extensions

### 📖 Reference Documentation
- [Configuration Reference](./reference/configuration-reference.md) - Detailed configuration options
- [API Reference](./reference/api-reference.md) - Complete API documentation
- [Troubleshooting Reference](./reference/troubleshooting-reference.md) - Comprehensive troubleshooting guide
- [Performance Tuning Guide](./reference/performance-tuning.md) - Performance optimization techniques
- [Security Hardening Guide](./reference/security-hardening.md) - Security best practices

## 🚀 Quick Start

### Prerequisites
- Erlang/OTP 27+
- Craftplan ERP system (v2.0+)
- A2A Protocol SDK
- MCP client (Claude Desktop or compatible)

### Basic Installation
```bash
# Clone the repository
git clone https://github.com/a2aproject/A2A.git
cd A2A/craftplan

# Build the project
make build

# Start the MCP server
make start-mcp-server

# Start the A2A agent
make start-a2a-agent
```

### Verification
```bash
# Check MCP server health
curl http://localhost:8090/health

# List available MCP tools
curl -X POST http://localhost:8090/mcp/list-tools

# Check A2A agent status
curl http://localhost:8080/status
```

## 📊 Integration Overview

The Craftplan MCP + A2A integration provides a comprehensive solution for:

- **ERP Integration**: Connect Craftplan ERP capabilities to AI agents
- **Multi-Agent Collaboration**: Enable agents to collaborate on complex tasks
- **Tool Discovery**: Discover and utilize ERP tools via MCP
- **Stateful Interactions**: Maintain state across multi-turn conversations
- **Enterprise Security**: Secure integration with authentication and authorization

## 🔄 Version Information

- **Current Version**: 1.0.0
- **Protocol Versions**: A2A v1.0, MCP 2024-11-05
- **Erlang/OTP**: 27+
- **Last Updated**: 2024-12-01

## 📞 Support

- **GitHub Issues**: [Report issues](https://github.com/a2aproject/A2A/issues)
- **Documentation**: [Full documentation](https://a2a-protocol.org)
- **Community**: [Join discussions](https://github.com/a2aproject/A2A/discussions)
- **Partner Program**: [Google Cloud Partner Program](https://goo.gle/a2a-partner)

## 📄 License

This project is licensed under the Apache License 2.0. See the [LICENSE](../../LICENSE) file for details.

---

*This documentation is part of the Agent2Agent Protocol project, an open source project under the Linux Foundation, contributed by Google.*