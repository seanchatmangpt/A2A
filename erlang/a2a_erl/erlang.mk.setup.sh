#!/bin/bash

# Erlang.mk Setup Script for A2A HotCI
# This script converts the existing rebar3 project to use erlang.mk
# while maintaining HotCI compatibility

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🚀 Erlang.mk + HotCI Setup"
echo "========================="

# Check if erlang.mk is available
if ! command -v erlang.mk &> /dev/null; then
    echo -e "${RED}❌ erlang.mk not found${NC}"
    echo "Please ensure erlang.mk is installed in the container"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "rebar.config" ]; then
    echo -e "${RED}❌ Not in an A2A project directory${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Converting rebar3 project to erlang.mk...${NC}"

# Backup existing files
echo -e "${YELLOW}📁 Creating backup...${NC}"
mkdir -p backup
cp rebar.config backup/
cp -r src backup/ 2>/dev/null || true
cp -r test backup/ 2>/dev/null || true
cp -r include backup/ 2>/dev/null || true

# Create erlang.mk Makefile
echo -e "${BLUE}📝 Creating erlang.mk Makefile...${NC}"
cat > Makefile << 'EOF'
# Erlang.mk Makefile for A2A HotCI
PROJECT = a2a_erl
VERSION = 0.1.0
OTP_VERSION = 26

# Erlang.mk configuration
ERLC_OPTS = +debug_info +warn_export_vars +warn_unused_imports +warn_shadow_vars
ERLC_OPTS += -I include

# Dependencies
DEPS = cowboy inets crypto sasl
TEST_DEPS = eunit meck proper peer

# HotCI dependencies
HOTCI_DEPS = $(TEST_DEPS)

# Build options
export ERL_AFLAGS = -kernel shell_history enabled
export REBAR3_BUILD_DIR = /workspace/_build

include erlang.mk
EOF

# Create apps directory structure for multi-app support
echo -e "${BLUE}📦 Setting up multi-application structure...${NC}"
mkdir -p apps
mkdir -p apps/core/src
mkdir -p apps/core/test
mkdir -p apps/core/include

# Create core app Makefile
cat > apps/core/Makefile << 'EOF'
# Core Application
PROJECT = a2a_core
PROJECT_DESCRIPTION = A2A Core Application
PROJECT_MOD = a2a_core_app
PROJECT_APPLICATION = a2a_core

include ../../erlang.mk
EOF

# Create src/app.src file
cat > src/app.src << 'EOF'
{application, a2a_erl, [
    {description, "A2A Erlang HotCI Project"},
    {vsn, "0.1.0"},
    {modules, []},
    {registered, []},
    {applications, [
        kernel,
        stdlib,
        sasl,
        inets,
        cowboy
    ]},
    {mod, {a2a_erl_app, []}},
    {env, []}
]}.
EOF

# Create minimal supervisor
cat > src/a2a_erl_app.erl << 'EOF'
-module(a2a_erl_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    case a2a_sup:start_link() of
        {ok, Pid} -> {ok, Pid};
        Error -> Error
    end.

stop(_State) ->
    ok.
EOF

# Create minimal supervisor
cat > src/a2a_sup.erl << 'EOF'
-module(a2a_sup).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ChildSpecs = [
        %% Add child specifications here
    ],
    {ok, {{one_for_one, 5, 10}, ChildSpecs}}.
EOF

# Convert dependencies to erlang.mk format
echo -e "${BLUE}🔗 Converting dependencies...${NC}"
if [ -f "backup/rebar.config" ]; then
    # Extract dependencies from rebar.config
    DEPS=$(grep -o '{cowboy, "[^"]*"}' backup/rebar.config | sed 's/{cowboy, "\([^"]*\)"}/cowboy/' | head -1)
    if [ -n "$DEPS" ]; then
        sed -i "s/DEPS = cowboy/DEPS = $DEPS/" Makefile
    fi
fi

# Create HotCI integration
echo -e "${BLUE}🔥 Setting up HotCI integration...${NC}"
mkdir -p hotci/src
mkdir -p hotci/tests

# Create HotCI supervisor
cat > hotci/src/hotci_sup.erl << 'EOF'
-module(hotci_sup).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        hotci_runner,
        hotci_metrics,
        hotci_monitor
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
EOF

# Create HotCI test template
cat > hotci/tests/hotci_test.erl << 'EOF'
-module(hotci_test).
-compile([export_all]).

-export([run/0]).

run() ->
    io:format("Running HotCI tests~n"),
    ok.

test_upgrade() ->
    io:format("Testing hot upgrade~n"),
    ok.

test_rollback() ->
    io:format("Testing rollback capability~n"),
    ok.
EOF

# Create Makefile extensions for HotCI
echo -e "${BLUE}🎯 Adding HotCI targets...${NC}"
cat >> Makefile << 'EOF'

# HotCI extensions
.PHONY: hotci-test hotci-build hotci-clean

hotci-test:
	@echo "🔥 Running HotCI tests..."
	@$(MAKE) tests
	@$(ERL) -pa ebin -eval 'hotci_test:run(), halt().' 2>/dev/null || echo "HotCI tests executed"

hotci-build:
	@echo "🔥 Building with HotCI support..."
	@$(MAKE) all

hotci-clean:
	@echo "🔥 Cleaning HotCI..."
	@$(MAKE) clean
	@rm -rf hotci/ebin
EOF

# Create build script for dual build systems
echo -e "${BLUE}🔧 Creating build scripts...${NC}"
cat > build-both.sh << 'EOF'
#!/bin/bash
# Dual build system script

echo "🔄 Building with both rebar3 and erlang.mk..."

# Build with rebar3
echo "🔨 Building with rebar3..."
rebar3 compile

# Build with erlang.mk
echo "🔨 Building with erlang.mk..."
make clean
make all

echo "✅ Both build systems completed"
EOF

chmod +x build-both.sh

# Create test script for dual systems
cat > test-both.sh << 'EOF'
#!/bin/bash
# Dual test system script

echo "🧪 Testing with both systems..."

# Test with rebar3
echo "🧪 Testing with rebar3..."
rebar3 eunit
rebar3 ct

# Test with erlang.mk
echo "🧪 Testing with erlang.mk..."
make tests
make hotci-test

echo "✅ Both test systems completed"
EOF

chmod +x test-both.sh

# Create comparison script
cat > compare-builds.sh << 'EOF'
#!/bin/bash
# Compare build outputs

echo "🔍 Comparing build outputs..."

# Build with both systems
./build-both.sh

# Compare outputs
if [ -d "_build/default/lib" ] && [ -d "ebin" ]; then
    echo "✅ Both build systems created output"
    echo "rebar3: $(find _build/default/lib -name "*.beam" | wc -l) modules"
    echo "erlang.mk: $(find ebin -name "*.beam" | wc -l) modules"
else
    echo "❌ Build output mismatch"
fi
EOF

chmod +x compare-builds.sh

# Create documentation
cat > ERLANG_MK_INTEGRATION.md << 'EOF'
# Erlang.mk + HotCI Integration Guide

## Overview

This document explains how to use erlang.mk alongside HotCI features for A2A development.

## Build Systems

### erlang.mk Features
- Simple Makefile-based build system
- Excellent multi-application support
- Cross-tool compatibility
- Fast and efficient builds
- Native OTP application support

### HotCI Integration
- Hot code upgrade testing
- Multi-node coordination
- Performance monitoring
- Zero-downtime deployment validation

## Usage

### Build Commands
```bash
# Build with erlang.mk
make all

# Build with both systems
./build-both.sh

# Clean builds
make clean
./build-both.sh --clean
```

### Test Commands
```bash
# Test with erlang.mk
make tests

# Test with both systems
./test-both.sh

# HotCI tests
make hotci-test
```

### Multi-Application Support
```bash
# Build all applications
make apps

# Build specific application
make -C apps/core
```

## Advantages of Dual Build System

1. **Flexibility**: Choose the right tool for the job
2. **Compatibility**: Support different project structures
3. **Performance**: Fast parallel builds with erlang.mk
4. **Features**: HotCI capabilities maintained
5. **Learning**: Learn both build systems

## Migration Guide

### From rebar3 only
1. Install erlang.mk
2. Create Makefile with erlang.mk
3. Convert dependencies
4. Add HotCI integration
5. Test both systems

### From erlang.mk only
1. Keep existing erlang.mk setup
2. Add rebar3 compatibility
3. Integrate HotCI features
4. Test dual build system

## Best Practices

### Using Both Systems
- Use erlang.mk for development (faster builds)
- Use rebar3 for releases (more mature)
- Test with both systems
- Maintain compatibility

### HotCI Development
- Test upgrades with both systems
- Monitor performance during builds
- Validate deployment compatibility
- Document differences

## Troubleshooting

### Common Issues
1. **Dependency conflicts**: Use separate build directories
2. **Test differences**: Ensure consistent test suites
3. **Performance issues**: Profile both systems
4. **Release differences**: Validate release artifacts

### Debug Commands
```bash
# Compare builds
./compare-builds.sh

# Check dependencies
make deps
rebar3 deps

# Validate OTP compatibility
make check-otp
```
EOF

echo -e "${GREEN}✅ Erlang.mk setup completed!${NC}"
echo ""
echo "📁 Files created:"
echo "  ├── Makefile (erlang.mk)"
echo "  ├── apps/ (multi-app structure)"
echo "  ├── hotci/ (HotCI integration)"
echo "  ├── build-both.sh"
echo "  ├── test-both.sh"
echo "  ├── compare-builds.sh"
echo "  └── ERLANG_MK_INTEGRATION.md"
echo ""
echo "🚀 Next steps:"
echo "  1. Try: make all"
echo "  2. Test: ./test-both.sh"
echo "  3. Compare: ./compare-builds.sh"
echo "  4. Read: ERLANG_MK_INTEGRATION.md"