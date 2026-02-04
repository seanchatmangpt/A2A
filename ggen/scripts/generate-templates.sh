#!/bin/bash

# ggen Template Generation Script
# Usage: ./generate-templates.sh [pattern-type] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
QUERIES_DIR="$PROJECT_DIR/queries"
OUTPUT_DIR="$PROJECT_DIR/generated"
ONT_DIR="$PROJECT_DIR/ontology"

# Default pattern types
PATTERN_TYPES=(
    "erlang-modules"
    "cloud-infra"
    "a2a-protocol"
    "constraint-based"
    "hierarchical"
    "conditional"
    "complex-composition"
    "templates"
)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
ggen Template Generation Script

Usage: $0 [pattern-type] [options]

Pattern Types:
    erlang-modules      - Generate Erlang OTP module templates
    cloud-infra         - Generate cloud infrastructure templates
    a2a-protocol       - Generate A2A protocol handlers
    constraint-based   - Generate constraint-based patterns
    hierarchical       - Generate hierarchical patterns
    conditional        - Generate conditional templates
    complex-composition - Generate complex pattern compositions
    templates          - Generate optimized template patterns

Options:
    -h, --help              Show this help message
    -o, --output DIR        Output directory (default: $OUTPUT_DIR)
    -q, --query FILE        Custom SPARQL query file
    -f, --filter "EXPR"    Filter expression for pattern matching
    -l, --limit NUM        Limit number of generated templates
    -v, --verbose          Enable verbose output
    -d, --debug            Enable debug mode
    --clean                Clean output directory before generation
    --dry-run             Show what would be generated without actually creating files

Examples:
    $0 erlang-modules
    $0 cloud-infra --output k8s/ --limit 5
    $0 constraint-based --filter "hotci_enabled=true"
    $0 a2a-protocol --query custom-protocol.sparql
EOF
}

# Validate environment
check_environment() {
    print_info "Checking environment..."

    # Check if ggen is installed
    if ! command -v ggen &> /dev/null; then
        print_error "ggen not found. Please install ggen first."
        exit 1
    fi

    # Check if required directories exist
    if [ ! -d "$QUERIES_DIR" ]; then
        print_error "Queries directory not found: $QUERIES_DIR"
        exit 1
    fi

    if [ ! -d "$ONT_DIR" ]; then
        print_error "Ontology directory not found: $ONT_DIR"
        exit 1
    fi

    # Check if ontologies exist
    for ont in "$ONT_DIR"/*.ttl; do
        if [ ! -f "$ont" ]; then
            print_error "Ontology file not found: $ont"
            exit 1
        fi
    done

    print_success "Environment validation passed"
}

# Clean output directory
clean_output() {
    if [ "$CLEAN" = true ]; then
        print_info "Cleaning output directory: $OUTPUT_DIR"
        rm -rf "$OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
    fi
}

# Map pattern types to query files
get_query_file() {
    case "$1" in
        "erlang-modules")
            echo "$QUERIES_DIR/erlang-module-definitions.sparql"
            ;;
        "cloud-infra")
            echo "$QUERIES_DIR/cloud-infrastructure-configurations.sparql"
            ;;
        "a2a-protocol")
            echo "$QUERIES_DIR/a2a-protocol-specifications.sparql"
            ;;
        "constraint-based")
            echo "$QUERIES_DIR/constraint-based-pattern-matching.sparql"
            ;;
        "hierarchical")
            echo "$QUERIES_DIR/hierarchical-pattern-extraction.sparql"
            ;;
        "conditional")
            echo "$QUERIES_DIR/conditional-pattern-generation.sparql"
            ;;
        "complex-composition")
            echo "$QUERIES_DIR/complex-pattern-composition.sparql"
            ;;
        "templates")
            echo "$QUERIES_DIR/template-generation-patterns.sparql"
            ;;
        *)
            print_error "Unknown pattern type: $1"
            exit 1
            ;;
    esac
}

# Generate templates
generate_templates() {
    local pattern_type="$1"
    local query_file="$2"

    print_info "Generating $pattern_type templates..."
    print_info "Query file: $query_file"
    print_info "Output directory: $OUTPUT_DIR"

    # Build ggen command
    local ggen_cmd="ggen generate"

    if [ "$VERBOSE" = true ]; then
        ggen_cmd="$ggen_cmd --verbose"
    fi

    if [ "$DEBUG" = true ]; then
        ggen_cmd="$ggen_cmd --debug"
    fi

    if [ "$DRY_RUN" = true ]; then
        ggen_cmd="$ggen_cmd --dry-run"
    fi

    if [ -n "$FILTER" ]; then
        ggen_cmd="$ggen_cmd --filter \"$FILTER\""
    fi

    if [ -n "$LIMIT" ]; then
        ggen_cmd="$ggen_cmd --limit $LIMIT"
    fi

    ggen_cmd="$ggen_cmd -q \"$query_file\" -o \"$OUTPUT_DIR\""

    if [ "$VERBOSE" = true ]; then
        print_info "Executing: $ggen_cmd"
    fi

    # Execute ggen command
    if eval "$ggen_cmd"; then
        print_success "Successfully generated $pattern_type templates"

        # Show generated files
        if [ "$DRY_RUN" = false ]; then
            print_info "Generated files:"
            find "$OUTPUT_DIR" -type f -name "*.erl" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" | head -20 | while read file; do
                echo "  - $file"
            done
        fi
    else
        print_error "Failed to generate $pattern_type templates"
        exit 1
    fi
}

# Generate all pattern types
generate_all() {
    print_info "Generating all pattern types..."

    for pattern_type in "${PATTERN_TYPES[@]}"; do
        query_file=$(get_query_file "$pattern_type")
        generate_templates "$pattern_type" "$query_file"
        echo ""
    done

    print_success "All templates generated successfully"
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -q|--query)
                CUSTOM_QUERY="$2"
                shift 2
                ;;
            -f|--filter)
                FILTER="$2"
                shift 2
                ;;
            -l|--limit)
                LIMIT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            --clean)
                CLEAN=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                PATTERN_TYPE="$1"
                shift
                ;;
        esac
    done

    # Check environment
    check_environment

    # Clean output if requested
    clean_output

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Determine what to generate
    if [ -z "$PATTERN_TYPE" ] || [ "$PATTERN_TYPE" = "all" ]; then
        generate_all
    else
        # Use custom query if provided
        if [ -n "$CUSTOM_QUERY" ]; then
            query_file="$CUSTOM_QUERY"
        else
            query_file=$(get_query_file "$PATTERN_TYPE")
        fi

        generate_templates "$PATTERN_TYPE" "$query_file"
    fi

    # Generate summary
    echo ""
    print_info "Generation Summary:"
    echo "  Pattern type: ${PATTERN_TYPE:-all}"
    echo "  Output directory: $OUTPUT_DIR"
    echo "  Generated files: $(find "$OUTPUT_DIR" -type f | wc -l)"

    if [ "$DRY_RUN" = false ]; then
        echo "  Templates ready for integration"
    else
        echo "  Dry run completed"
    fi
}

# Run main function with all arguments
main "$@"