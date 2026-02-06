# YAWL Development Environment Setup

## Overview

This tutorial guides you through setting up a complete YAWL development environment. We'll cover installing Erlang/OTP, configuring the development tools, and running your first YAWL workflow.

## Prerequisites

- Operating System: macOS, Linux, or Windows (WSL)
- 4GB+ RAM recommended
- Basic command line knowledge
- Git installed

## Step 1: Install Erlang/OTP

### macOS (using Homebrew)

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Erlang (OTP 27+ required)
brew install erlang@27

# Add to PATH (if not automatically added)
echo 'export PATH="/opt/homebrew/opt/erlang@27/libexec/erlang/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Linux (Ubuntu/Debian)

```bash
# Add Erlang Solutions repository
wget https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc
sudo apt-key add erlang_solutions.asc
echo "deb https://packages.erlang-solutions.com/ubuntu focal contrib" | sudo tee /etc/apt/sources.list.d/erlang.list

# Update package lists and install Erlang
sudo apt update
sudo apt install erlang elixir

# Verify installation
erl -version
```

### Windows (using WSL2)

```bash
# Install WSL2
wsl --install

# Install Ubuntu (if not already)
wsl --install -d Ubuntu

# In Ubuntu terminal:
sudo apt update
sudo apt install erlang elixir
```

### Verify Installation

```bash
# Check Erlang version
erl -v

# Expected output:
% Erlang/OTP 27 [erts-14.2.1] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit:ns]

# Check OTP applications
erl
Eshell V14.2.1  (abort with ^G)
1> application:which_applications().
```

## Step 2: Install Development Tools

### rebar3 (Build Tool)

```bash
# Install rebar3
cd /usr/local/bin
sudo wget https://s3.amazonaws.com/rebar3/rebar3
sudo chmod +x rebar3

# Verify installation
rebar3 version
```

### VS Code with Erlang Support

```bash
# Install VS Code
# Download from: https://code.visualstudio.com/

# Install Erlang extensions
code --install-extension erlang-solutions.erlang
code --install-extension pgourlain.erlang
code --install-extension jasonszhang.vscode-basic-formatter
```

### Alternative: Emacs + Erlang Mode

```bash
# Install Emacs
brew install emacs  # macOS
sudo apt install emacs  # Linux

# Install Erlang mode (included with Erlang)
```

## Step 3: Clone and Build YAWL

```bash
# Clone the repository
git clone https://github.com/your-org/a2a_erl.git
cd a2a_erl

# Install dependencies
rebar3 deps

# Build the project
rebar3 compile

# Run tests
rebar3 eunit
rebar3 ct
```

### Project Structure

```
a2a_erl/
├── src/                    # Source code
│   ├── yawl_*.erl         # YAWL modules
│   ├── a2a_*.erl          # A2A integration
│   └── *.hrl             # Header files
├── tests/                 # Test suites
│   ├── unit/             # Unit tests
│   ├── integration/      # Integration tests
│   └── *.erl            # Common test files
├── examples/             # Example workflows
│   ├── ordering_workflow.erl
│   ├── payment_workflow.erl
│   └── ...
├── config/               # Configuration files
│   ├── sys.config       # System configuration
│   └── vm.args          # VM arguments
├── rebar.config         # Rebar3 configuration
└── README.md            # Project documentation
```

## Step 4: Configure Development Environment

### System Configuration (`config/sys.config`)

```erlang
{a2a_erl, [
    %% Enable YAWL logging
    {yawl_log_level, debug},
    {yawl_log_file, "/tmp/yawl.log"},

    %% Enable REST API
    {rest_api_enabled, true},
    {rest_api_port, 8080},
    {rest_api_host, "localhost"},

    %% Enable XES logging
    {xes_enabled, true},
    {xes_output_mode, file},
    {xes_file_path, "/tmp/yawl_workflow.xes"},

    %% Enable metrics
    {metrics_enabled, true},
    {metrics_port, 9090},

    %% Database configuration (for persistence)
    {db_type, mnesia},
    {db_node, 'yawl@localhost'}
]}.
```

### VM Arguments (`config/vm.args`)

```erlang
-name yawl@localhost
-setcookie yawl_dev
-smp auto
+pc unicode
-kernel inet_dist_listen_min 9100
-kernel inet_dist_listen_max 9200
-pa /path/to/a2a_erl/_build/default/lib/a2a_erl/ebin
```

### Development Shell

```bash
# Start development shell
rebar3 shell

# This starts an Erlang shell with the application loaded
Eshell V14.2.1  (abort with ^G)
(yawl@localhost)1>
```

## Step 5: Configure Development IDE

### VS Code Configuration (`.vscode/settings.json`)

```json
{
    "erlang.formatting.path": "rebar3 format",
    "erlang.linting.enabled": true,
    "erlang.linting.path": "rebar3 dialyzer",
    "files.associations": {
        "*.hrl": "erlang"
    },
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
        "source.fixAll": true
    }
}
```

### VS Code Tasks (`.vscode/tasks.json`)

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Compile",
            "type": "shell",
            "command": "rebar3 compile",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            }
        },
        {
            "label": "Test",
            "type": "shell",
            "command": "rebar3 ct",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            }
        },
        {
            "label": "Shell",
            "type": "shell",
            "command": "rebar3 shell",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            }
        },
        {
            "label": "Run Example",
            "type": "shell",
            "command": "erl -pa ebin -s ordering_workflow simulate_normal_approval -s init stop",
            "group": "run",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            }
        }
    ]
}
```

## Step 6: Setup Testing Environment

### Common Test Configuration

```bash
# Create test data directory
mkdir -p /tmp/yawl_test_data

# Create .cover directory for coverage
mkdir -p /tmp/.cover

# Run specific test groups
rebar3 ct --suite yawl_business_tests
rebar3 ct --suite yawl_workflow_integration_tests
```

### Test Data

Create `test/data/` directory with sample workflow data:

```json
{
    "orders": [
        {
            "id": "order-001",
            "items": [
                {"id": "item-001", "quantity": 10, "price": 50.00}
            ],
            "total": 500.00,
            "status": "pending"
        }
    ],
    "workflows": [
        {
            "id": "workflow-001",
            "type": "ordering",
            "definition": {
                "places": ["start", "pending", "completed"],
                "transitions": ["start", "complete"],
                "initial_marking": {"start": ["token"]}
            }
        }
    ]
}
```

## Step 7: Development Workflow

### 1. Make Changes

```bash
# Edit your workflow module
vim src/yawl_ordering_workflow.erl
```

### 2. Compile Changes

```bash
# Compile specific module
rebar3 compile -m yawl_ordering_workflow

# Or compile everything
rebar3 compile
```

### 3. Run Tests

```bash
# Run all tests
rebar3 ct

# Run specific test
rebar3 ct --module yawl_ordering_workflow --case test_order_processing_low
```

### 4. Run Examples

```bash
# Start shell and run examples
rebar3 shell
(yawl@localhost)1> ordering_workflow:simulate_normal_approval().
{ok, #{...}}

# Run specific example directly
erl -pa ebin -s yawl_examples -s init stop
```

### 5. Debugging

```bash
# Start with debug logging
rebar3 shell
(yawl@localhost)1> application:set_env(a2a_erl, yawl_log_level, debug).

# Enable crash dump on error
erl +pc unicode +K true +hms 1024 -name debug@localhost
```

## Step 8: Docker Development (Optional)

### Dockerfile

```dockerfile
FROM erlang:27.0-alpine

# Install dependencies
RUN apk add --no-cache git build-base

# Install rebar3
RUN cd /tmp && \
    wget https://s3.amazonaws.com/rebar3/rebar3 && \
    chmod +x rebar3 && \
    mv rebar3 /usr/local/bin/

# Create app directory
WORKDIR /app

# Copy source code
COPY . .

# Build the application
RUN rebar3 compile

# Expose ports
EXPOSE 8080 9090

# Start the application
CMD ["rebar3", "shell"]
```

### Docker Compose

```yaml
version: '3.8'
services:
  yawl:
    build: .
    ports:
      - "8080:8080"
      - "9090:9090"
    environment:
      - YAWL_LOG_LEVEL=debug
      - YAWL_NODE_NAME=yawl@localhost
    volumes:
      - ./config:/app/config
      - ./logs:/app/logs
  database:
    image: mnesia
    ports:
      - "11211:11211"
```

## Step 9: Validation

### Verify Installation

```bash
# 1. Check Erlang version
erl -v

# 2. Check rebar3
rebar3 version

# 3. Build project
rebar3 compile

# 4. Run tests
rebar3 ct

# 5. Run example workflow
erl -pa ebin -s ordering_workflow simulate_normal_approval -s init stop
```

### Expected Output

```erlang
% Example workflow execution
(yawl@localhost)1> ordering_workflow:simulate_normal_approval().
{ok,#{...}} % Should return a success result
```

## Troubleshooting

### Common Issues

1. **Erlang version too old**
   ```bash
   # Check minimum version
   erl -v  # Should show OTP 27+
   ```

2. **Rebar3 compilation fails**
   ```bash
   # Clean and rebuild
   rebar3 clean
   rm -rf _build
   rebar3 compile
   ```

3. **Tests fail**
   ```bash
   # Check test logs
   rebar3 ct --verbose
   ```

4. **Module not found**
   ```bash
   # Ensure ebin directory is in path
   erl -pa ebin -s module_name -s init stop
   ```

### Getting Help

1. **Documentation**
   - Check `docs/` directory
   - Run `rebar3 docs` to generate docs

2. **Community**
   - Erlang Slack: https://erlang-solutions.slack.com/
   - Stack Overflow: #erlang tag
   - YAWL mailing lists

3. **Debug Commands**
   ```erlang
   % In Erlang shell
   application:which_applications().
   application:start(a2a_erl).
   code:get_path().
   ```

## Next Steps

Once your environment is set up, you're ready to:

1. **Create Your First Workflow**: Follow the step-by-step tutorial
2. **Learn YAWL Patterns**: Understand workflow patterns and their usage
3. **Explore the REST API**: Learn to interact with YAWL via HTTP
4. **Business Workflows**: Dive into real-world workflow examples

## Key Takeaways

1. **Erlang/OTP 27+** is required for YAWL development
2. **rebar3** is the build tool of choice
3. **Configuration** is in `config/sys.config` and `config/vm.args`
4. **Testing** uses Common Test framework
5. **Docker** support for consistent development environments

Your YAWL development environment is now ready! You can proceed to create your first workflow.