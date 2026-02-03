# =============================================================================
# Makefile for A2A Erlang Docker Operations
# =============================================================================
# Provides convenient targets for building, running, and managing Docker
# containers for the A2A Erlang/OTP application.

# Configuration
VERSION ?= $(shell cat VERSION 2>/dev/null || echo "0.1.0")
IMAGE_NAME ?= a2a-erl
REGISTRY ?= localhost:5000
PORT ?= 8080
HOST ?= localhost

# Docker image names
IMAGE_DEV = $(IMAGE_NAME):dev
IMAGE_PROD = $(IMAGE_NAME):$(VERSION)
IMAGE_LATEST = $(IMAGE_NAME):latest

# Colors for output
BLUE = \033[0;34m
GREEN = \033[0;32m
RED = \033[0;31m
YELLOW = \033[0;33m
NC = \033[0m # No Color

.PHONY: help build dev prod test run stop clean logs shell release release-management version rollback monitor build_status erlang_build dual_build erlang_test hotci_erlang_test erlint init_erlangmk apps_build quality_checks

# Default target
.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Help Target
# -----------------------------------------------------------------------------
help: ## Show this help message
	@echo "$(BLUE)A2A Erlang/OTP Docker Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make build              # Build production image"
	@echo "  make dev                # Run development container"
	@echo "  make prod               # Run production container"
	@echo "  make test               # Run tests in container"

# -----------------------------------------------------------------------------
# Build Targets
# -----------------------------------------------------------------------------
build: ## Build production Docker image
	@echo "$(BLUE)Building production image $(IMAGE_PROD)...$(NC)"
	docker build \
		--build-arg VERSION=$(VERSION) \
		--build-arg BUILD_DATE=$$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
		--build-arg VCS_REF=$$(git rev-parse --short HEAD 2>/dev/null || echo "unknown") \
		-t $(IMAGE_PROD) \
		-t $(IMAGE_LATEST) \
		--target runtime \
		.
	@echo "$(GREEN)Build complete: $(IMAGE_PROD)$(NC)"

build-dev: ## Build development Docker image
	@echo "$(BLUE)Building development image $(IMAGE_DEV)...$(NC)"
	docker build \
		--build-arg VERSION=$(VERSION) \
		-t $(IMAGE_DEV) \
		--target development \
		.
	@echo "$(GREEN)Build complete: $(IMAGE_DEV)$(NC)"

build-no-cache: ## Build without cache
	@echo "$(YELLOW)Building without cache...$(NC)"
	docker build --no-cache -t $(IMAGE_PROD) --target runtime .
	@echo "$(GREEN)Build complete$(NC)"

# -----------------------------------------------------------------------------
# Development Targets
# -----------------------------------------------------------------------------
dev: build-dev ## Run development container with volume mounts
	@echo "$(BLUE)Starting development container...$(NC)"
	docker run -it --rm \
		-p $(PORT):8080 \
		-p 4369:4369 \
		-v $$(pwd)/src:/build/src \
		-v $$(pwd)/include:/build/include \
		-v $$(pwd)/config:/build/config \
		-v $$(pwd)/test:/build/test \
		-v $$(pwd)/rebar.config:/build/rebar.config \
		-e RELEASE_NODE=a2a-dev@localhost \
		-e PORT=$(PORT) \
		--name a2a-erl-dev \
		$(IMAGE_DEV)

dev-bash: ## Run development container with bash shell
	@echo "$(BLUE)Starting bash in development container...$(NC)"
	docker run -it --rm \
		-p $(PORT):8080 \
		-v $$(pwd):/build \
		-e RELEASE_NODE=a2a-dev@localhost \
		--name a2a-erl-bash \
		$(IMAGE_DEV) \
		bash

# -----------------------------------------------------------------------------
# Production Targets
# -----------------------------------------------------------------------------
prod: build ## Run production container
	@echo "$(BLUE)Starting production container...$(NC)"
	docker run -d \
		-p $(PORT):8080 \
		-p 4369:4369 \
		-e RELEASE_NODE=a2a@$(HOST) \
		-e PORT=$(PORT) \
		-e HOST=$(HOST) \
		--name a2a-erl \
		--restart unless-stopped \
		$(IMAGE_PROD)
	@echo "$(GREEN)Container started: http://localhost:$(PORT)$(NC)"

run: prod ## Alias for 'prod' target

# -----------------------------------------------------------------------------
# Testing Targets
# -----------------------------------------------------------------------------
test: build-dev ## Run tests in container
	@echo "$(BLUE)Running tests...$(NC)"
	docker run --rm \
		-v $$(pwd)/src:/build/src:ro \
		-v $$(pwd)/include:/build/include:ro \
		-v $$(pwd)/config:/build/config:ro \
		-v $$(pwd)/test:/build/test:ro \
		-v $$(pwd)/rebar.config:/build/rebar.config:ro \
		-v $$(pwd)/_build/test:/build/_build/test \
		-e RELEASE_NODE=a2a-test@localhost \
		--name a2a-erl-test \
		$(IMAGE_DEV) \
		rebar3 ct --cover
	@echo "$(GREEN)Tests complete$(NC)"

test-unit: build-dev ## Run unit tests only
	@echo "$(BLUE)Running unit tests...$(NC)"
	docker run --rm \
		-v $$(pwd):/build \
		$(IMAGE_DEV) \
		rebar3 ct --suite test/*_SUITE.erl

test-proper: build-dev ## Run property-based tests
	@echo "$(BLUE)Running property-based tests...$(NC)"
	docker run --rm \
		-v $$(pwd):/build \
		$(IMAGE_DEV) \
		rebar3 proper

# -----------------------------------------------------------------------------
# Docker Compose Targets
# -----------------------------------------------------------------------------
compose-up: ## Start all services with docker-compose
	@echo "$(BLUE)Starting services with docker-compose...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)Services started$(NC)"

compose-dev: ## Start development service
	@echo "$(BLUE)Starting development service...$(NC)"
	docker-compose --profile dev up a2a-dev

compose-test: ## Run tests with docker-compose
	@echo "$(BLUE)Running tests with docker-compose...$(NC)"
	docker-compose --profile test run --rm a2a-test

compose-down: ## Stop all services
	@echo "$(BLUE)Stopping services...$(NC)"
	docker-compose down

compose-logs: ## Show logs from docker-compose
	docker-compose logs -f

# -----------------------------------------------------------------------------
# Management Targets
# -----------------------------------------------------------------------------
stop: ## Stop running container
	@echo "$(BLUE)Stopping container...$(NC)"
	docker stop a2a-erl 2>/dev/null || echo "Container not running"
	docker rm a2a-erl 2>/dev/null || echo "Container not found"
	@echo "$(GREEN)Container stopped$(NC)"

restart: stop prod ## Restart production container

logs: ## Show logs from running container
	docker logs -f a2a-erl

logs-dev: ## Show logs from development container
	docker logs -f a2a-erl-dev

shell: ## Open shell in running container
	docker exec -it a2a-erl bash

shell-dev: ## Open shell in development container
	docker exec -it a2a-erl-dev bash

# -----------------------------------------------------------------------------
# Inspection Targets
# -----------------------------------------------------------------------------
health: ## Check container health
	@echo "$(BLUE)Container health status:$(NC)"
	@docker inspect --format='{{.State.Health.Status}}' a2a-erl 2>/dev/null || echo "Container not running"
	@echo ""
	@echo "$(BLUE)HTTP health check:$(NC)"
	@curl -s http://localhost:$(PORT)/.well-known/agent-card.json > /dev/null && \
		echo "$(GREEN)✓ Service is healthy$(NC)" || \
		echo "$(RED)✗ Service is unhealthy$(NC)"

status: ## Show container status
	@echo "$(BLUE)Container status:$(NC)"
	docker ps -a | grep a2a-erl || echo "No containers found"

inspect: ## Inspect container configuration
	docker inspect a2a-erl

# -----------------------------------------------------------------------------
# Release Targets
# -----------------------------------------------------------------------------
release: build ## Tag and push release image
	@echo "$(BLUE)Tagging release image...$(NC)"
	docker tag $(IMAGE_PROD) $(REGISTRY)/$(IMAGE_PROD)
	docker tag $(IMAGE_PROD) $(REGISTRY)/$(IMAGE_LATEST)
	@echo "$(GREEN)Pushing to registry: $(REGISTRY)$(NC)"
	docker push $(REGISTRY)/$(IMAGE_PROD)
	docker push $(REGISTRY)/$(IMAGE_LATEST)
	@echo "$(GREEN)Release complete$(NC)"

# -----------------------------------------------------------------------------
# Cleanup Targets
# -----------------------------------------------------------------------------
clean: ## Remove stopped containers and dangling images
	@echo "$(BLUE)Cleaning up...$(NC)"
	docker container prune -f
	docker image prune -f
	@echo "$(GREEN)Cleanup complete$(NC)"

clean-all: stop ## Remove all containers and images
	@echo "$(YELLOW)Removing all containers and images...$(NC)"
	docker rm -f a2a-erl a2a-erl-dev a2a-erl-test 2>/dev/null || true
	docker rmi $(IMAGE_PROD) $(IMAGE_DEV) $(IMAGE_LATEST) 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"

# -----------------------------------------------------------------------------
# Info Targets
# -----------------------------------------------------------------------------
info: ## Show build information
	@echo "$(BLUE)A2A Erlang Docker Configuration$(NC)"
	@echo ""
	@echo "Version:      $(VERSION)"
	@echo "Image Name:   $(IMAGE_NAME)"
	@echo "Dev Image:    $(IMAGE_DEV)"
	@echo "Prod Image:   $(IMAGE_PROD)"
	@echo "Registry:     $(REGISTRY)"
	@echo "Port:         $(PORT)"
	@echo "Host:         $(HOST)"
	@echo ""
	@echo "$(BLUE)Docker Images:$(NC)"
	@docker images | grep $(IMAGE_NAME) || echo "No images found"
	@echo ""
	@echo "$(BLUE)Running Containers:$(NC)"
	@docker ps | grep a2a-erl || echo "No containers running"

# -----------------------------------------------------------------------------
# Release Management Targets
# -----------------------------------------------------------------------------
release-management: ## Show release management options
	@echo "$(BLUE)A2A Erlang Release Management$(NC)"
	@echo ""
	@echo "$(GREEN)Quick Commands:$(NC)"
	@echo "  make bump-version TYPE=patch  # Bump patch version"
	@echo "  make release                 # Build and release"
	@echo "  make build                   # Build release artifacts"
	@echo ""
	@echo "$(GREEN)Release Commands:$(NC)"
	@echo "  make build-release           # Complete release build"
	@echo "  make test-release            # Test release package"
	@echo "  make publish                 # Publish to GitHub"
	@echo "  make clean-release           # Clean release artifacts"
	@echo ""
	@echo "Use 'make help-release' for detailed release commands"
	@echo ""
	@echo "$(GREEN)Release Information:$(NC)"
	@echo "Current Version: $(VERSION)"
	@echo "Release Name: a2a-erl-v$(VERSION)"
	@echo "Registry: $(REGISTRY)"

version: ## Show current version
	@echo "$(VERSION)"

bump-major: ## Bump major version
	./scripts/bump-version.sh major

bump-minor: ## Bump minor version
	./scripts/bump-version.sh minor

bump-patch: ## Bump patch version
	./scripts/bump-version.sh patch

build-release: ## Build complete release
	./scripts/release-manager.sh build

test-release: ## Test release package
	./scripts/release-manager.sh validate $(VERSION)

publish-release: ## Publish release to GitHub
	./scripts/publish-release.sh publish

clean-release: ## Clean release artifacts
	./scripts/release-manager.sh clean

rollback: ## Rollback to previous version
	./scripts/rollback-manager.sh rollback-last

rollback-to: ## Rollback to specific version
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)Usage: make rollback-to VERSION=1.0.0$(NC)"; \
		exit 1; \
	fi
	./scripts/rollback-manager.sh rollback $(VERSION)

rollback-status: ## Show rollback status
	./scripts/rollback-manager.sh status

rollback-list: ## List available rollback versions
	./scripts/rollback-manager.sh list

monitor: ## Monitor release status and health
	./scripts/release-monitor.sh status

monitor-health: ## Check release health
	./scripts/release-monitor.sh health

monitor-metrics: ## Show release metrics
	./scripts/release-monitor.sh metrics

monitor-alerts: ## Check for release alerts
	./scripts/release-monitor.sh alerts

# =============================================================================
# End of Release Management Targets
# =============================================================================

# HotCI targets
hotci-build:
	rebar3 as hotci compile

hotci-test:
	rebar3 as hotci ct

hotci-upgrade:
	rebar3 as hotci ct --suite hotci_upgrade_SUITE

hotci-integration:
	rebar3 as hotci ct --suite hotci_integration_SUITE

# Erlang.mk integration targets
.ERLANG_MK_CHECK = $(shell command -v erlang.mk 2>/dev/null)
ERLANG_MK_AVAILABLE := $(if $(.ERLANG_MK_CHECK),1,0)

# Include erlang.mk if available
ifeq ($(ERLANG_MK_AVAILABLE),1)
    include erlang.mk
endif

# Dual build system targets
erlang_build:
ifeq ($(ERLANG_MK_AVAILABLE),1)
	@echo "$(BLUE)Building with erlang.mk...$(NC)"
	@if [ -f "Makefile.erlang.mk" ]; then \
		$(MAKE) -f Makefile.erlang.mk all; \
	else \
		$(MAKE) -f Makefile.erlang.mk rebar3_build; \
	fi
else
	@echo "$(RED)erlang.mk not available$(NC)"
	@exit 1
endif

dual_build: build erlang_build
	@echo "$(GREEN)Dual build system completed$(NC)"

# Test targets with erlang.mk
erlang_test:
ifeq ($(ERLANG_MK_AVAILABLE),1)
	@echo "$(BLUE)Testing with erlang.mk...$(NC)"
	@if [ -f "Makefile.erlang.mk" ]; then \
		$(MAKE) -f Makefile.erlang.mk tests; \
	fi
else
	@echo "$(RED)erlang.mk not available$(NC)"
	@exit 1
endif

hotci_erlang_test:
ifeq ($(ERLANG_MK_AVAILABLE),1)
	@echo "$(BLUE)Running HotCI tests with erlang.mk...$(NC)"
	@if [ -f "Makefile.erlang.mk" ]; then \
		$(MAKE) -f Makefile.erlang.mk hotci-test; \
	fi
else
	@echo "$(RED)erlang.mk not available$(NC)"
	@exit 1
endif

# Quality targets
quality_checks: lint dialyzer xref

erlint:
ifeq ($(ERLANG_MK_AVAILABLE),1)
	@echo "$(BLUE)Running erlang.mk linting...$(NC)"
	@if [ -f "Makefile.erlang.mk" ]; then \
		$(MAKE) -f Makefile.erlang.mk format-check 2>/dev/null || true; \
	fi
else
	@echo "$(RED)erlang.mk not available$(NC)"
	@exit 1
endif

# Status check
build_status:
	@echo "$(BLUE)Build System Status:$(NC)"
	@echo "  rebar3: $(if $(REBAR3_AVAILABLE),$(GREEN)✅$(NC),$(RED)❌$(NC))"
	@echo "  erlang.mk: $(if $(ERLANG_MK_AVAILABLE),$(GREEN)✅$(NC),$(RED)❌$(NC))"
	@echo "  Docker: $(if $(DOCKER_AVAILABLE),$(GREEN)✅$(NC),$(RED)❌$(NC))"
	@echo ""
	@echo "$(BLUE)HotCI Integration:$(NC)"
	@echo "  HotCI tests: $(if $(wildcard hotci),$(GREEN)✅$(NC),$(RED)❌$(NC))"

# Initialize erlang.mk if not available
init_erlangmk:
ifeq ($(ERLANG_MK_AVAILABLE),1)
	@echo "$(GREEN)erlang.mk already available$(NC)"
else
	@echo "$(BLUE)Installing erlang.mk...$(NC)"
	@curl -Lo bootstrap.sh https://github.com/ninenines/erlang.mk/raw/master/bootstrap.sh && \
		chmod +x bootstrap.sh && \
		./bootstrap.sh && \
		rm bootstrap.sh
	@echo "$(GREEN)erlang.mk installed successfully$(NC)"
endif

# Multi-application support
apps_build:
ifeq ($(ERLANG_MK_AVAILABLE),1)
	@echo "$(BLUE)Building all applications...$(NC)"
	@for app in $(wildcard apps/*/); do \
		if [ -f "$$app/Makefile" ]; then \
			$(MAKE) -C "$$app"; \
		else \
			echo "Making erlang.mk app for $$app"; \
			(cd "$$app" && echo 'include ../../erlang.mk' > Makefile && $(MAKE)); \
		fi; \
	done
else
	@echo "$(RED)erlang.mk not available$(NC)"
	@exit 1
endif
