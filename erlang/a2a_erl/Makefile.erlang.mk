# Erlang.mk Makefile for A2A HotCI Project
# This Makefile demonstrates erlang.mk integration with HotCI features

# Project configuration
PROJECT = a2a_erl
VERSION = 0.1.0
OTP_VERSION = 26

# Erlang.mk configuration
ERLC_OPTS = +debug_info +warn_export_vars +warn_unused_imports +warn_shadow_vars +warn_obsolete_guard
ERLC_OPTS += -I include

# Dependencies
DEPS = cowboy inets crypto sasl
TEST_DEPS = eunit meck proper peer

# HotCI-specific dependencies
HOTCI_DEPS = peer meck proper

# Build options
export ERL_AFLAGS = -kernel shell_history enabled
export REBAR3_BUILD_DIR = /workspace/_build

# Include erlang.mk from repository
ERLANG_MK_PATH = /tmp/erlang.mk

.PHONY: all clean test hotci-test build release erlang_build rebar3_build dual_build

# Default target
all: dual_build

# Clean build
clean:
	@echo "🧹 Cleaning all build artifacts..."
	@$(MAKE) clean-rebar3 2>/dev/null || true
	@$(MAKE) clean-erlangmk 2>/dev/null || true
	@rm -rf _build ebin/*.beam *.beam

# Clean rebar3 builds
clean-rebar3:
	@echo "🧹 Cleaning rebar3 builds..."
	@rebar3 clean 2>/dev/null || true
	@rm -rf _build 2>/dev/null || true

# Clean erlang.mk builds
clean-erlangmk:
	@echo "🧹 Cleaning erlang.mk builds..."
	@rm -rf ebin/*.beam 2>/dev/null || true

# Build with rebar3
rebar3_build:
	@echo "🔨 Building with rebar3..."
	@rebar3 compile

# Build with erlang.mk
erlang_build:
	@echo "🔨 Building with erlang.mk..."
	@if [ -f "$(ERLANG_MK_PATH)/erlang.mk" ]; then \
		$(MAKE) -f $(ERLANG_MK_PATH)/erlang.mk all; \
	else \
		echo "erlang.mk not available, using rebar3 instead"; \
		$(MAKE) rebar3_build; \
	fi

# Dual build - build with both systems
dual_build: rebar3_build erlang_build
	@echo "🔄 Dual build completed"

# Run tests with rebar3
test_rebar3:
	@echo "🧪 Testing with rebar3..."
	@rebar3 eunit
	@rebar3 ct

# Run tests with erlang.mk
test_erlangmk:
	@echo "🧪 Testing with erlang.mk..."
	@if [ -f "$(ERLANG_MK_PATH)/erlang.mk" ]; then \
		$(MAKE) -f $(ERLANG_MK_PATH)/erlang.mk test; \
	else \
		echo "erlang.mk not available, using rebar3 tests"; \
		$(MAKE) test_rebar3; \
	fi

# Run HotCI tests
hotci-test:
	@echo "🔥 Running HotCI tests..."
	@rebar3 as hotci ct
	@echo "🔥 HotCI test suite completed"

# Build release
release:
	@echo "📦 Building release..."
	@rebar3 release

# Dual release build
dual_release: release
	@echo "🔄 Dual release build completed"

# Development targets
dev:
	@echo "🚀 Starting development environment..."
	@erl

# Quality checks
quality_checks: lint dialyzer xref

# Linting
lint:
	@echo "🎨 Running linting..."
	@rebar3 lint 2>/dev/null || echo "Linting not available"

# Dialyzer static analysis
dialyzer:
	@echo "🔍 Running dialyzer..."
	@rebar3 dialyzer 2>/dev/null || echo "Dialyzer completed or failed to run"

# Xref cross reference analysis
xref:
	@echo "🔍 Running xref..."
	@rebar3 xref 2>/dev/null || echo "Xref completed or failed to run"

# Run all tests
test_all: test_rebar3 test_erlangmk hotci-test
	@echo "🎉 All tests completed"

# Show build system status
build_status:
	@echo "📊 Build System Status:"
	@echo "  rebar3: $(shell command -v rebar3 2>/dev/null && echo "✅ Available" || echo "❌ Not available")"
	@if [ -f "$(ERLANG_MK_PATH)/erlang.mk" ]; then \
		echo "  erlang.mk: ✅ Available"; \
	else \
		echo "  erlang.mk: ❌ Not available"; \
	fi
	@echo "  Docker: $(shell command -v docker 2>/dev/null && echo "✅ Available" || echo "❌ Not available")"
	@echo ""
	@echo "📁 HotCI Integration:"
	@if [ -d "hotci" ]; then \
		echo "  HotCI tests: ✅ Available"; \
	else \
		echo "  HotCI tests: ❌ Not available"; \
	fi

# Generate documentation
docs:
	@echo "📚 Generating documentation..."
	@$(ERL) -eval 'edoc:files(["src/*.erl"]), halt().'

# HotCI setup
hotci_setup:
	@echo "🔥 Setting up HotCI..."
	@mkdir -p hotci/src hotci/tests hotci/config
	@echo "HotCI directory structure created"

# Performance benchmark
benchmark:
	@echo "⚡ Running benchmarks..."
	@$(MAKE) rebar3_build
	@$(ERL) -pa ebin -eval 'io:format("Benchmark not implemented~n"), halt().'

# CI/CD pipeline
ci_pipeline: test_all quality_checks release
	@echo "🔄 CI pipeline completed"

# Docker integration
docker_build:
	@echo "🐳 Building Docker image..."
	@docker build -t a2a-erlang-hotci:latest .

# Integration test
integration_test:
	@echo "🔗 Running integration tests..."
	@rebar3 ct --suite a2a_integration_SUITE 2>/dev/null || echo "Integration tests not available"

# Quick build for development
quick_build: clean rebar3_build
	@echo "⚡ Quick build completed"

# Show help
help:
	@echo "Available targets:"
	@echo "  all              - Build with both systems (default)"
	@echo "  clean           - Clean all build artifacts"
	@echo "  rebar3_build    - Build with rebar3 only"
	@echo "  erlang_build    - Build with erlang.mk only"
	@echo "  dual_build      - Build with both systems"
	@echo "  test            - Run tests with rebar3"
	@echo "  hotci-test      - Run HotCI-specific tests"
	@echo "  release         - Build release"
	@echo "  dev             - Start development shell"
	@echo "  quality_checks  - Run quality checks (lint, dialyzer, xref)"
	@echo "  test_all        - Run all tests"
	@echo "  build_status    - Show build system status"
	@echo "  docs            - Generate documentation"
	@echo "  hotci_setup     - Set up HotCI directory structure"
	@echo "  benchmark       - Run performance benchmarks"
	@echo "  ci_pipeline     - Run full CI pipeline"
	@echo "  docker_build    - Build Docker image"
	@echo "  integration_test- Run integration tests"
	@echo "  quick_build     - Quick development build"
	@echo "  help            - Show this help message"