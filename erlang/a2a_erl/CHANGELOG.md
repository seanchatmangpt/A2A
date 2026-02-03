# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- WebSocket support for real-time bidirectional streaming
- Advanced authentication schemes (OAuth2, mTLS)
- Enhanced observability with OpenTelemetry tracing
- Multi-tenant isolation improvements
- Performance optimizations for high-throughput scenarios

## [0.1.0] - 2025-01-XX

### Added
- Initial implementation of A2A Protocol v0.4 specification
- **Core Task Management**
  - gen_statem-based task lifecycle with state_functions callback mode
  - Task states: submitted, working, completed, failed, canceled, input_required, auth_required, rejected
  - State enter calls for automatic event notifications
  - Process monitoring for robust cleanup
- **HTTP/JSON Interface**
  - JSON-RPC 2.0 protocol binding
  - Cowboy 2.12.0 web server integration
  - RESTful endpoints for all A2A operations
  - CORS support for cross-origin requests
- **Server-Sent Events (SSE)**
  - Real-time task status updates via streaming
  - Artifact streaming for progressive output
  - Keepalive mechanism for connection maintenance
  - Automatic connection cleanup on task completion
- **Push Notifications**
  - Webhook-based notifications for task state changes
  - HTTP authentication support (Bearer, Basic)
  - Configurable notification endpoints per task
- **Agent Discovery**
  - RFC 8615 compliant agent card at `/.well-known/agent-card.json`
  - Extended agent card support for authenticated clients
  - Dynamic skill and capability management
- **Storage**
  - ETS-backed task store with optimized concurrency
  - write_concurrency and read_concurrency for OTP 28
  - Context-based task indexing
  - Automatic cleanup of old terminal tasks (24h retention)
- **Handler Behaviour**
  - `a2a_handler` behaviour for custom task processing
  - Support for multi-turn conversations
  - Interrupted states for user input and authentication
- **Multi-Turn Conversations**
  - Message history tracking
  - Context-based conversation grouping
  - Reference task ID support for task chains
- **Developer Tools**
  - rebar3 build configuration
  - OTP release packaging with relx
  - EDoc documentation generation
  - Dialyzer type checking support
- **Example Implementation**
  - Echo handler demonstrating the a2a_handler behaviour
  - Default agent card with sample skills
  - Example clients and usage patterns
- **OTP 28 Features**
  - gen_statem with state_functions and state_enter
  - Enhanced crypto:strong_rand_bytes for ID generation
  - Native JSON encoding/decoding
  - ETS concurrency optimizations

### Configuration
- HTTP server port (default: 8080)
- Host and scheme configuration for agent card URLs
- Configurable task retention period
- SSE keepalive interval (30 seconds)
- Cleanup interval (5 minutes)

### Dependencies
- Erlang/OTP 28 or later
- Cowboy 2.12.0 (HTTP server)
- rebar3 3.x or later (build tool)

### Documentation
- README with quick start guide
- Code documentation with EDoc tags
- Inline examples for all major APIs
- Architecture documentation
- API reference documentation
- Deployment guide

### Testing
- Common Test suite structure
- PropEr property-based testing support
- Meck mocking library for unit tests
- Code coverage reporting with covertool

## [0.0.1] - Development

### Added
- Initial project structure
- Basic OTP application skeleton
- rebar3 configuration

---

## Version Classification

- **Major**: Incompatible API changes, architectural redesigns
- **Minor**: Backwards-compatible functionality additions
- **Patch**: Backwards-compatible bug fixes

## Error Codes

### JSON-RPC Standard Errors
- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

### A2A Specific Errors
- `-32001`: Task not found
- `-32002`: Task already in terminal state
- `-32003`: Unsupported operation
- `-32004`: Authentication required

---

[Unreleased]: https://github.com/a2aproject/a2a-erlang/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/a2aproject/a2a-erlang/releases/tag/v0.1.0
