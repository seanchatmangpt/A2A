#!/bin/bash

# Example usage of the Erlang OTP ontology with ggen
# This script demonstrates various template generation scenarios

set -e

# Configuration
ONTOLOGY_PATH="ontology/erlang-otp.ttl"
OUTPUT_DIR="generated_templates"

echo "🚀 Erlang OTP Template Generation Examples"
echo "==========================================="

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Example 1: Generate a basic GenServer
echo "📝 Example 1: Generating basic GenServer template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:gen_server" \
    --property "a2a:module_name=my_cache" \
    --property "a2a:description=Simple cache gen_server implementation" \
    --output "$OUTPUT_DIR/gen_server_example"

echo "✅ Generated GenServer template at: $OUTPUT_DIR/gen_server_example"

# Example 2: Generate a supervisor with specific configuration
echo "📝 Example 2: Generating supervisor template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:supervisor" \
    --property "a2a:module_name=my_app_supervisor" \
    --property "a2a:supervisor_strategy=one_for_one" \
    --property "a2a:supervisor_intensity=5" \
    --property "a2a:supervisor_period=10" \
    --property "a2a:description=Main application supervisor" \
    --output "$OUTPUT_DIR/supervisor_example"

echo "✅ Generated supervisor template at: $OUTPUT_DIR/supervisor_example"

# Example 3: Generate ETS table with cache pattern
echo "📝 Example 3: Generating ETS cache template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:ets_cache" \
    --property "a2a:ets_table_name=process_cache" \
    --property "a2a:ets_table_type=set" \
    --property "a2a:ets_table_key_type=pid" \
    --property "a2a:ets_table_value_type=term" \
    --property "a2a:ets_table_size=1000" \
    --property "a2a:description=Process cache using ETS" \
    --output "$OUTPUT_DIR/ets_cache_example"

echo "✅ Generated ETS cache template at: $OUTPUT_DIR/ets_cache_example"

# Example 4: Generate HotCI-enabled module
echo "📝 Example 4: Generating HotCI module template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:hotci_module" \
    --property "a2a:module_name=my_hotci_service" \
    --property "a2a:hotci_enabled=true" \
    --property "a2a:version_compatibility=2.0.0" \
    --property "a2a:rollback_supported=true" \
    --property "a2a:upgrade_monitoring=true" \
    --property "a2a:description=HotCI-enabled service module" \
    --output "$OUTPUT_DIR/hotci_example"

echo "✅ Generated HotCI module template at: $OUTPUT_DIR/hotci_example"

# Example 5: Generate metric collector
echo "📝 Example 5: Generating metric collector template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:metric_collector" \
    --property "a2a:metric_name=request_count" \
    --property "a2a:metric_type=counter" \
    --property "a2a:collection_interval=1000" \
    --property "a2a:description=Request counter metric" \
    --output "$OUTPUT_DIR/metrics_example"

echo "✅ Generated metric collector template at: $OUTPUT_DIR/metrics_example"

# Example 6: Generate error handler with retry logic
echo "📝 Example 6: Generating retry handler template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:retry_handler" \
    --property "a2a:module_name=my_retry_handler" \
    --property "a2a:max_retries=3" \
    --property "a2a:retry_delay=1000" \
    --property "a2a:backoff_type=exponential" \
    --property "a2a:description=Exponential backoff retry handler" \
    --output "$OUTPUT_DIR/retry_example"

echo "✅ Generated retry handler template at: $OUTPUT_DIR/retry_example"

# Example 7: Generate request-reply protocol
echo "📝 Example 7: Generating protocol template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:request_reply" \
    --property "a2a:protocol_type=request_reply" \
    --property "a2a:message_format=json" \
    --property "a2a:timeout=5000" \
    --property "a2a:description=REST API request-reply protocol" \
    --output "$OUTPUT_DIR/protocol_example"

echo "✅ Generated protocol template at: $OUTPUT_DIR/protocol_example"

# Example 8: Generate alert handler
echo "📝 Example 8: Generating alert handler template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:alert_handler" \
    --property "a2a:metric_name=memory_usage" \
    --property "a2a:alert_threshold=0.8" \
    --property "a2a:alert_level=warning" \
    --property "a2a:description=Memory usage alert handler" \
    --output "$OUTPUT_DIR/alert_example"

echo "✅ Generated alert handler template at: $OUTPUT_DIR/alert_example"

# Example 9: Generate logging handler
echo "📝 Example 9: Generating logging template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:logging_handler" \
    --property "a2a:log_level=info" \
    --property "a2a:log_format=json" \
    --property "a2a:log_rotation=10485760" \
    --property "a2a:log_retention=30" \
    --property "a2a:description=Application JSON logger" \
    --output "$OUTPUT_DIR/logging_example"

echo "✅ Generated logging handler template at: $OUTPUT_DIR/logging_example"

# Example 10: Generate complex application with multiple components
echo "📝 Example 10: Generating complete application template..."
ggen generate \
    --ontology "$ONTOLOGY_PATH" \
    --pattern "erl:application" \
    --property "a2a:application_name=my_awesome_app" \
    --property "a2a:version=1.0.0" \
    --property "a2a:description=Complete OTP application with multiple components" \
    --property "a2a:hotci_enabled=true" \
    --output "$OUTPUT_DIR/app_example"

echo "✅ Generated complete application template at: $OUTPUT_DIR/app_example"

# Validation
echo ""
echo "🔍 Validating generated templates..."
echo "=================================="

# Validate a few key templates
for template in "$OUTPUT_DIR"/gen_server_example "$OUTPUT_DIR"/supervisor_example "$OUTPUT_DIR"/hotci_example; do
    echo "📋 Validating $template..."
    ggen validate --ontology "$ONTOLOGY_PATH" --template "$template"
done

echo ""
echo "🎉 All examples generated successfully!"
echo "📁 Generated templates are in: $OUTPUT_DIR/"
echo ""
echo "💡 Next steps:"
echo "1. Review generated templates"
echo "2. Customize for your specific needs"
echo "3. Integrate into your development workflow"
echo "4. Run validation in CI/CD pipeline"