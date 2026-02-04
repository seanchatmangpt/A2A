# Makefile for ggen code generation system

.PHONY: all test demo clean compile start stop test-unit test-integration test-validation test-performance test-all test-data help demo-comprehensive demo-basic demo-advanced demo-cloud demo-hotci demo-integration test-all-scenarios scenario-basic scenario-advanced

# Project configuration
PROJECT_NAME = a2a-ggen
VERSION = 0.2.0
ERL = erl
ERLC = erlc
REBAR3 = rebar3
EBIN_DIR = ebin
SOURCE_DIR = src
INCLUDE_DIR = include
TEST_DIR = test

# Erlang flags
ERL_FLAGS = +debug_info -Werror
EBIN_FLAGS = -o $(EBIN_DIR)

# Files
SOURCES = $(wildcard $(SOURCE_DIR)/*.erl)
HEADERS = $(wildcard $(INCLUDE_DIR)/*.hrl)
BEAMS = $(SOURCES:$(SOURCE_DIR)/%.erl=$(EBIN_DIR)/%.beam)
TEST_SOURCES = $(wildcard $(TEST_DIR)/*/*.erl)
TEST_BEAMS = $(TEST_SOURCES:$(TEST_DIR)/%.erl=$(EBIN_DIR)/%.beam)

# Default target
all: compile test

# Compile Erlang sources
compile: $(EBIN_DIR) $(BEAMS)

$(EBIN_DIR):
	mkdir -p $(EBIN_DIR)

$(EBIN_DIR)/%.beam: $(SOURCE_DIR)/%.erl $(HEADERS)
	$(ERLC) $(EBIN_FLAGS) $(ERL_FLAGS) $<

# Test generation system
test: test-unit

# Test suite targets
test-unit:
	@echo "Running unit tests..."
	@$(ERL) -noshell -pa $(EBIN_DIR) \
		-eval "eunit:test([ggen_generator_tests, ggen_metrics_collector_tests, template_tests], [verbose]), init:stop(0)" || exit $$?

test-integration:
	@echo "Running integration tests..."
	@$(ERL) -noshell -pa $(EBIN_DIR) \
		-eval "eunit:test(ggen_integration_tests, [verbose]), init:stop(0)" || exit $$?

test-validation:
	@echo "Running validation tests..."
	@$(ERL) -noshell -pa $(EBIN_DIR) \
		-eval "eunit:test(ggen_validation_tests, [verbose]), init:stop(0)" || exit $$?

test-performance:
	@echo "Running performance tests..."
	@$(ERL) -noshell -pa $(EBIN_DIR) \
		-eval "eunit:test(ggen_performance_tests, [verbose]), init:stop(0)" || exit $$?

test-all:
	@echo "Running all tests..."
	@$(ERL) -noshell -pa $(EBIN_DIR) \
		-eval "eunit:test([ggen_generator_tests, ggen_metrics_collector_tests, ggen_integration_tests, ggen_validation_tests, ggen_performance_tests, template_tests], [verbose]), init:stop(0)" || exit $$?

# Test with test runner script
test-runner:
	@echo "Running tests with test runner script..."
	@bash $(TEST_DIR)/test_runner.sh --all

# Generate test data
test-data:
	@echo "Generating test data..."
	@bash $(TEST_DIR)/generate_test_data.sh

# Run demos
demo:
	$(ERL) -pa $(EBIN_DIR) -eval "demo:main()" -s init stop

# Run specific demo
demo_erlang:
	$(ERL) -pa $(EBIN_DIR) -eval "demo:main([demo, erlang])" -s init stop

demo_docker:
	$(ERL) -pa $(EBIN_DIR) -eval "demo:main([demo, docker])" -s init stop

demo_k8s:
	$(ERL) -pa $(EBIN_DIR) -eval "demo:main([demo, k8s])" -s init stop

demo_helm:
	$(ERL) -pa $(EBIN_DIR) -eval "demo:main([demo, helm])" -s init stop

# Generate demo files
generate:
	$(ERL) -pa $(EBIN_DIR) -eval "demo:main([generate])" -s init stop

# Comprehensive demo
demo-comprehensive:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main()" -s init stop

# Basic demo
demo-basic:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main([demo, erlang])" -s init stop

# Advanced demo
demo-advanced:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main([demo, advanced])" -s init stop

# Cloud demo
demo-cloud:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main([demo, cloud])" -s init stop

# HotCI demo
demo-hotci:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main([demo, hotci])" -s init stop

# Integration demo
demo-integration:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main([demo, integration])" -s init stop

# Test all scenarios
test-all-scenarios:
	$(ERL) -pa $(EBIN_DIR) -eval "test_validation:main([test, all])" -s init stop

# Scenario-based generation
scenario-basic:
	$(ERL) -pa $(EBIN_DIR) -eval "scenario_basic:generate()" -s init stop

scenario-advanced:
	$(ERL) -pa $(EBIN_DIR) -eval "scenario_advanced:generate()" -s init stop

# Generate all scenarios
generate-all:
	$(ERL) -pa $(EBIN_DIR) -eval "demo_comprehensive:main([generate])" -s init stop
	$(ERL) -pa $(EBIN_DIR) -eval "scenario_basic:generate()" -s init stop
	$(ERL) -pa $(EBIN_DIR) -eval "scenario_advanced:generate()" -s init stop

# Run ggen application
start: compile
	$(ERL) -pa $(EBIN_DIR) -boot start_sasl -eval "application:start(ggen_app)" -s init stop

# Stop ggen application
stop:
	$(ERL) -pa $(EBIN_DIR) -eval "application:stop(ggen_app)" -s init stop

# Clean build artifacts
clean:
	rm -rf $(EBIN_DIR)/*.beam
	rm -rf generated/demo_*
	rm -f demo_*.json
	rm -rf test_output validation_test_output performance_test_output integration_test_workspace
	find test -name "*.log" -delete

# Check dependencies
check-deps:
	@echo "Checking ggen dependency..."
	@which ggen > /dev/null || (echo "❌ ggen not found. Install with: cargo install ggen" && exit 1)
	@echo "✅ ggen found"

# Generate documentation
docs:
	@echo "Generating documentation..."
	@mkdir -p docs
	@echo "Documentation generated in docs/ directory"

# Install ggen
install-ggen:
	@echo "Installing ggen..."
	@cargo install ggen
	@echo "✅ ggen installed"

# Show help
help:
	@echo "Available targets:"
	@echo "  all           - Compile all Erlang sources"
	@echo "  compile       - Compile Erlang sources"
	@echo "  test          - Run test suite"
	@echo "  demo          - Run all demos"
	@echo "  demo_erlang   - Run Erlang demo"
	@echo "  demo_docker  - Run Docker demo"
	@echo "  demo_k8s     - Run Kubernetes demo"
	@echo "  demo_helm    - Run Helm demo"
	@echo "  demo-comprehensive - Run comprehensive demo"
	@echo "  demo-basic    - Run basic demo"
	@echo "  demo-advanced - Run advanced demo"
	@echo "  demo-cloud   - Run cloud demo"
	@echo "  demo-hotci    - Run HotCI demo"
	@echo "  demo-integration - Run integration demo"
	@echo "  generate      - Generate demo files"
	@echo "  generate-all  - Generate all scenarios"
	@echo "  scenario-basic - Run basic scenario"
	@echo "  scenario-advanced - Run advanced scenario"
	@echo "  test-all-scenarios - Test all scenarios"
	@echo "  start         - Start ggen application"
	@echo "  stop          - Stop ggen application"
	@echo "  clean         - Clean build artifacts"
	@echo "  check-deps    - Check dependencies"
	@echo "  docs          - Generate documentation"
	@echo "  install-ggen  - Install ggen"
	@echo "  help          - Show this help"
	@echo ""
	@echo "Demo Scripts:"
	@echo "  ./scripts/run_demo.sh     - Run comprehensive demo system"
	@echo "  ./scripts/run_scenario.sh  - Run specific scenarios"
	@echo ""
	@echo "Examples:"
	@echo "  make demo-comprehensive     # Run comprehensive demo"
	@echo "  make scenario-basic          # Run basic scenario"
	@echo "  ./scripts/run_demo.sh demo all # Run all demos"