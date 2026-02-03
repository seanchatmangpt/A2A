# A2A Erlang/OTP Implementation

An implementation of the [A2A (Agent-to-Agent) Protocol](https://github.com/a2aproject/A2A) using Erlang/OTP's `gen_statem` behavior and OTP 28 primitives.

## Features

- **Full A2A Protocol Support**: Implements the A2A v0.4 specification
- **gen_statem Task Management**: Each task runs as an independent state machine
- **State Functions**: Clean state-based callback handling for task lifecycle
- **Server-Sent Events (SSE)**: Real-time streaming of task updates
- **Push Notifications**: Webhook-based notifications for task state changes
- **Agent Discovery**: RFC 8615 compliant agent card at `/.well-known/agent-card.json`
- **JSON-RPC 2.0**: Standard protocol binding for all operations
- **High Performance**: ETS-backed storage with write/read concurrency
- **OTP 28 Optimizations**: Leverages latest OTP features

## Requirements

- Erlang/OTP 28 or later
- rebar3

## Quick Start

### Build

```bash
cd erlang/a2a_erl
rebar3 compile
```

### Run in Development

```bash
rebar3 shell
```

The server starts on `http://localhost:8080` by default.

### Build Release

```bash
rebar3 release
_build/default/rel/a2a_erl/bin/a2a_erl foreground
```

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    a2a_erl_sup                              │
│                  (Top Supervisor)                           │
└─────────────────────────────────────────────────────────────┘
         │              │                │
         ▼              ▼                ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ a2a_task_   │  │ a2a_agent_  │  │ a2a_task_   │
│   store     │  │   card      │  │   sup       │
│ (ETS Store) │  │ (gen_server)│  │(simple_one_ │
│             │  │             │  │ for_one)    │
└─────────────┘  └─────────────┘  └─────────────┘
                                        │
                        ┌───────────────┼───────────────┐
                        ▼               ▼               ▼
                 ┌───────────┐   ┌───────────┐   ┌───────────┐
                 │ Task 1    │   │ Task 2    │   │ Task N    │
                 │gen_statem │   │gen_statem │   │gen_statem │
                 └───────────┘   └───────────┘   └───────────┘
```

### Task State Machine

```
                    ┌──────────────┐
                    │  submitted   │
                    └──────────────┘
                           │
                           ▼
        ┌─────────────────────────────────────────┐
        │                working                   │
        └─────────────────────────────────────────┘
         │        │           │          │        │
         ▼        ▼           ▼          ▼        ▼
    ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
    │completed│ │ failed │ │canceled│ │input_  │ │auth_   │
    │   ✓    │ │   ✓    │ │   ✓    │ │required│ │required│
    └────────┘ └────────┘ └────────┘ └────────┘ └────────┘
      Terminal   Terminal   Terminal   │          │
                                       └──► working ◄──┘
```

## API Endpoints

### Message Operations

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/message:send` | POST | Send a message, get task/message response |
| `/message:stream` | POST | Send message with SSE streaming response |

### Task Operations

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/tasks` | GET | List tasks with filtering |
| `/tasks/{id}` | GET | Get task by ID |
| `/tasks/{id}:cancel` | POST | Cancel a task |
| `/tasks/{id}:subscribe` | GET | Subscribe to task updates (SSE) |

### Agent Discovery

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/.well-known/agent-card.json` | GET | Public agent card |
| `/extendedAgentCard` | GET | Extended agent card (auth required) |

## Usage Examples

### Send a Message (curl)

```bash
curl -X POST http://localhost:8080/message:send \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "message/send",
    "params": {
      "message": {
        "messageId": "msg-001",
        "role": "ROLE_USER",
        "parts": [
          {"text": "Hello, A2A Agent!"}
        ]
      }
    }
  }'
```

### Stream a Message (curl)

```bash
curl -N -X POST http://localhost:8080/message:stream \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "message/stream",
    "params": {
      "message": {
        "messageId": "msg-002",
        "role": "ROLE_USER",
        "parts": [
          {"text": "Process this with streaming"}
        ]
      }
    }
  }'
```

### Get Task

```bash
curl http://localhost:8080/tasks/task-id-here
```

### Subscribe to Task Updates

```bash
curl -N http://localhost:8080/tasks/task-id-here:subscribe
```

## Implementing Custom Handlers

Create a module implementing the `a2a_handler` behaviour:

```erlang
-module(my_custom_handler).
-behaviour(a2a_handler).

-export([init/2, process/2, handle_message/2, terminate/2]).

init(Task, Message) ->
    %% Initialize handler state
    {ok, #{task => Task}}.

process(Task, State) ->
    %% Process the task and return result
    Artifact = create_artifact(...),
    {ok, #{artifacts => [Artifact]}}.

handle_message(Message, State) ->
    %% Handle additional messages
    {continue, State}.

terminate(Reason, State) ->
    ok.
```

Then start a task with your handler:

```erlang
Opts = #{handler_module => my_custom_handler},
{ok, Pid} = a2a_task_statem:start_link(Message, Opts).
```

## Configuration

Edit `config/sys.config`:

```erlang
[
  {a2a_erl, [
    {port, 8080},         % HTTP server port
    {host, "localhost"},  % Host for agent card URL
    {scheme, "http"}      % URL scheme (http/https)
  ]}
].
```

## Testing

```bash
rebar3 ct
rebar3 proper  # Property-based tests
```

## Type Checking

```bash
rebar3 dialyzer
```

## Documentation

Generate EDoc documentation:

```bash
rebar3 edoc
```

## License

Apache-2.0

## Contributing

See the main [A2A repository](https://github.com/a2aproject/A2A) for contribution guidelines.
