#!/bin/bash

# GGen Test Data Generator
# Script to generate test data for ggen testing

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test data directories
TEST_DATA_DIR="test/test_data"
FIXTURES_DIR="$TEST_DATA_DIR/fixtures"
ONT_DIR="$FIXTURES_DIR/ontologies"
CONFIG_DIR="$FIXTURES_DIR/configs"
MODULE_DIR="$FIXTURES_DIR/modules"

# Function to print status
print_status() {
    local status=$1
    local message=$2

    case $status in
        "SUCCESS") echo -e "${GREEN}✅ $message${NC}" ;;
        "INFO") echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}⚠️  $message${NC}" ;;
    esac
}

# Function to create directories
create_directories() {
    print_status "INFO" "Creating test data directories..."

    mkdir -p "$ONT_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$MODULE_DIR"

    print_status "SUCCESS" "Directories created"
}

# Function to generate ontology files
generate_ontology_files() {
    print_status "INFO" "Generating test ontology files..."

    # Basic ontology
    cat > "$ONT_DIR/basic_ontology.ttl" << 'EOF'
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix a2a: <http://a2a.io/schema/> .

a2a:Component rdf:type owl:Class .
a2a:Behaviour rdf:type owl:Class .

a2a:GenServerBehaviour rdf:type owl:Class ;
    rdfs:subClassOf a2a:Behaviour .

a2a:GenStatemBehaviour rdf:type owl:Class ;
    rdfs:subClassOf a2a:Behaviour .

a2a:hasBehaviour rdf:type owl:ObjectProperty ;
    rdfs:domain a2a:Component ;
    rdfs:range a2a:Behaviour .

a2a:component_name rdf:type owl:DatatypeProperty ;
    rdfs:domain a2a:Component ;
    rdfs:range xsd:string .
EOF

    # Complex ontology
    cat > "$ONT_DIR/complex_ontology.ttl" << 'EOF'
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix a2a: <http://a2a.io/schema/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

a2a:TaskStore rdf:type owl:Class ;
    rdfs:subClassOf a2a:Component ;
    a2a:component_name "task_store" ;
    a2a:hasBehaviour a2a:GenServerBehaviour .

a2a:MetricsCollector rdf:type owl:Class ;
    rdfs:subClassOf a2a:Component ;
    a2a:component_name "metrics_collector" ;
    a2a:hasBehaviour a2a:GenStatemBehaviour .

a2a:hasProperty rdf:type owl:ObjectProperty ;
    rdfs:domain a2a:Component ;
    rdfs:range a2a:Property .

a2a:Property rdf:type owl:Class .

a2a:propertyName rdf:type owl:DatatypeProperty ;
    rdfs:domain a2a:Property ;
    rdfs:range xsd:string .

a2a:propertyType rdf:type owl:DatatypeProperty ;
    rdfs:domain a2a:Property ;
    rdfs:range xsd:string .

a2a:task_queue rdf:type a2a:Property ;
    a2a:propertyName "task_queue" ;
    a2a:propertyType "queue()" .

a2a:metrics_data rdf:type a2a:Property ;
    a2a:propertyName "metrics_data" ;
    a2a:propertyType "map()" .
EOF

    print_status "SUCCESS" "Ontology files generated"
}

# Function to generate configuration files
generate_config_files() {
    print_status "INFO" "Generating test configuration files..."

    # Basic config
    cat > "$CONFIG_DIR/basic_config.json" << 'EOF'
{
    "project_name": "basic_a2a_app",
    "version": "0.1.0",
    "modules": [
        {
            "name": "basic_server",
            "type": "gen_server",
            "properties": []
        }
    ]
}
EOF

    # Full config
    cat > "$CONFIG_DIR/full_config.json" << 'EOF'
{
    "project_name": "full_a2a_app",
    "version": "1.0.0",
    "modules": [
        {
            "name": "task_store",
            "type": "gen_server",
            "properties": [
                {
                    "name": "task_queue",
                    "type": "queue()"
                }
            ]
        },
        {
            "name": "metrics_collector",
            "type": "gen_statem",
            "properties": []
        }
    ]
}
EOF

    print_status "SUCCESS" "Configuration files generated"
}

# Function to generate test modules
generate_test_modules() {
    print_status "INFO" "Generating test module files..."

    # Simple gen_server
    cat > "$MODULE_DIR/simple_gen_server.erl" << 'EOF'
-module(simple_gen_server).
-behaviour(gen_server).

-export([start_link/0, get_state/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_state() ->
    gen_server:call(?MODULE, get_state).

init([]) ->
    {ok, #{}}.

handle_call(get_state, _From, State) ->
    {reply, State, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
EOF

    # Complex gen_statem
    cat > "$MODULE_DIR/complex_gen_statem.erl" << 'EOF'
-module(complex_gen_statem).
-behaviour(gen_statem).

-export([start_link/0, get_metrics/0]).
-export([init/1, callback_mode/0, handle_event/4, terminate/2, code_change/3]).

start_link() ->
    gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).

get_metrics() ->
    gen_statem:call(?MODULE, get_metrics).

init([]) ->
    {ok, idle, #{metrics => #{}}}.

callback_mode() ->
    state_functions.

handle_event({call, From}, get_metrics, idle, State) ->
    {reply, From, State#state.metrics, idle}.

handle_event(_EventType, _Event, State, Data) ->
    {keep_state, Data}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
EOF

    print_status "SUCCESS" "Test module files generated"
}

# Function to generate test SQL files
generate_sql_files() {
    print_status "INFO" "Generating test SQL files..."

    # MySQL schema
    cat > "$FIXTURES_DIR/schema.mysql.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS tasks (
    id VARCHAR(36) PRIMARY KEY,
    type VARCHAR(50) NOT NULL,
    data JSON NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS metrics (
    id VARCHAR(36) PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DOUBLE NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_metric_name (metric_name),
    INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF

    # PostgreSQL schema
    cat > "$FIXTURES_DIR/schema.pgsql.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(50) NOT NULL,
    data JSONB NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
);

CREATE TABLE IF NOT EXISTS metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_name VARCHAR(100) NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_metric_name (metric_name),
    INDEX idx_timestamp (timestamp)
);
EOF

    print_status "SUCCESS" "SQL files generated"
}

# Function to generate sample template files
generate_template_samples() {
    print_status "INFO" "Generating sample template files..."

    # Sample gen_server template
    cat > "$FIXTURES_DIR/gen_server_sample.tera" << 'EOF'
---
description: "Sample gen_server template"
output_dir: "src/"
file_extension: ".erl"
---

-module({{ module.name }}).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
EOF

    print_status "SUCCESS" "Template samples generated"
}

# Function to generate test data documentation
generate_documentation() {
    print_status "INFO" "Generating test data documentation..."

    cat > "$TEST_DATA_DIR/README.md" << 'EOF'
# GGen Test Data

This directory contains test data for ggen system testing.

## Structure

- `fixtures/` - Test fixtures and sample data
  - `ontologies/` - Sample ontology files (Turtle format)
  - `configs/` - Sample configuration files (JSON format)
  - `modules/` - Sample Erlang module files
  - `schema.*.sql` - Database schema files
- `generated/` - Auto-generated test data
- `validation/` - Test validation files

## Files

### Ontologies

- `basic_ontology.ttl` - Basic ontology with simple component definitions
- `complex_ontology.ttl` - Complex ontology with multiple components and properties

### Configurations

- `basic_config.json` - Basic project configuration
- `full_config.json` - Full project configuration with multiple modules

### Modules

- `simple_gen_server.erl` - Simple gen_server implementation
- `complex_gen_statem.erl` - Complex gen_statem implementation

### Schemas

- `schema.mysql.sql` - MySQL database schema
- `schema.pgsql.sql` - PostgreSQL database schema

## Usage

These test files can be used by:

1. Unit tests - validating generation logic
2. Integration tests - end-to-end generation workflows
3. Validation tests - testing generated code compilation
4. Performance tests - measuring generation performance
EOF

    print_status "SUCCESS" "Documentation generated"
}

# Function to generate CSV test data
generate_csv_data() {
    print_status "INFO" "Generating CSV test data..."

    cat > "$FIXTURES_DIR/test_data.csv" << 'EOF'
module_name,behaviour_type,property_name,property_type,default_value,is_optional
task_store,gen_server,task_queue,queue(),"#{}",false
task_store,gen_server,max_tasks,integer(),"1000",false
task_store,gen_server,timeout,integer(),"30000",true
metrics_collector,gen_statem,metrics_data,map(),"#{}",false
metrics_collector,gen_statem,interval,integer(),"1000",false
cache_manager,gen_server,size,integer(),"1000",false
cache_manager,gen_server,ttl,integer(),"3600",false
notification_service,supervisor,channels,list(),"[]",false
database_pool,supervisor,pool_size,integer(),"10",false
EOF

    print_status "SUCCESS" "CSV data generated"
}

# Function to generate XML test data
generate_xml_data() {
    print_status "INFO" "Generating XML test data..."

    cat > "$FIXTURES_DIR/test_data.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<modules>
    <module name="task_store" type="gen_server">
        <properties>
            <property name="task_queue" type="queue()" default="#{}" optional="false"/>
            <property name="max_tasks" type="integer()" default="1000" optional="false"/>
        </properties>
    </module>
    <module name="metrics_collector" type="gen_statem">
        <properties>
            <property name="metrics_data" type="map()" default="#{}" optional="false"/>
        </properties>
    </module>
    <module name="cache_manager" type="gen_server">
        <properties>
            <property name="cache_size" type="integer()" default="1000" optional="false"/>
        </properties>
    </module>
</modules>
EOF

    print_status "SUCCESS" "XML data generated"
}

# Function to clean up test data
cleanup_test_data() {
    print_status "INFO" "Cleaning up test data..."

    rm -rf "$TEST_DATA_DIR"
    print_status "SUCCESS" "Test data cleaned up"
}

# Function to show help
show_help() {
    echo "GGen Test Data Generator"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --clean         Clean up existing test data"
    echo "  -a, --all           Generate all test data (default)"
    echo "  -o, --ontologies    Generate only ontology files"
    echo "  -f, --config        Generate only configuration files"
    echo "  -m, --modules       Generate only module files"
    echo "  -s, --sql           Generate only SQL schema files"
    echo "  -t, --templates     Generate only template samples"
    echo "  -d, --docs          Generate only documentation"
    echo "  -v, --csv           Generate only CSV data"
    echo "  -x, --xml           Generate only XML data"
    echo ""
    echo "Examples:"
    echo "  $0 --all"
    echo "  $0 --clean"
    echo "  $0 --ontologies"
}

# Main function
main() {
    print_status "INFO" "Starting GGen test data generation..."

    # Parse command line arguments
    local clean=false
    local generate_all=true
    local generate_ontologies=false
    local generate_config=false
    local generate_modules=false
    local generate_sql=false
    local generate_templates=false
    local generate_docs=false
    local generate_csv=false
    local generate_xml=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                clean=true
                shift
                ;;
            -a|--all)
                generate_all=true
                shift
                ;;
            -o|--ontologies)
                generate_ontologies=true
                generate_all=false
                shift
                ;;
            -f|--config)
                generate_config=true
                generate_all=false
                shift
                ;;
            -m|--modules)
                generate_modules=true
                generate_all=false
                shift
                ;;
            -s|--sql)
                generate_sql=true
                generate_all=false
                shift
                ;;
            -t|--templates)
                generate_templates=true
                generate_all=false
                shift
                ;;
            -d|--docs)
                generate_docs=true
                generate_all=false
                shift
                ;;
            -v|--csv)
                generate_csv=true
                generate_all=false
                shift
                ;;
            -x|--xml)
                generate_xml=true
                generate_all=false
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Clean up if requested
    if [ "$clean" = true ]; then
        cleanup_test_data
        exit 0
    fi

    # Create base directory
    mkdir -p "$TEST_DATA_DIR"

    # Generate test data based on options
    if [ "$generate_all" = true ] || [ "$generate_ontologies" = true ]; then
        create_directories
        generate_ontology_files
    fi

    if [ "$generate_all" = true ] || [ "$generate_config" = true ]; then
        create_directories
        generate_config_files
    fi

    if [ "$generate_all" = true ] || [ "$generate_modules" = true ]; then
        create_directories
        generate_test_modules
    fi

    if [ "$generate_all" = true ] || [ "$generate_sql" = true ]; then
        create_directories
        generate_sql_files
    fi

    if [ "$generate_all" = true ] || [ "$generate_templates" = true ]; then
        create_directories
        generate_template_samples
    fi

    if [ "$generate_all" = true ] || [ "$generate_docs" = true ]; then
        create_directories
        generate_documentation
    fi

    if [ "$generate_all" = true ] || [ "$generate_csv" = true ]; then
        create_directories
        generate_csv_data
    fi

    if [ "$generate_all" = true ] || [ "$generate_xml" = true ]; then
        create_directories
        generate_xml_data
    fi

    if [ "$generate_all" = true ]; then
        generate_documentation
    fi

    print_status "SUCCESS" "Test data generation completed"
}

# Run main function
main "$@"