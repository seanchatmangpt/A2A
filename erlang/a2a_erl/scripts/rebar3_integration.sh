#!/bin/bash

# A2A HotCI + rebar3 Canonical Generator Integration
# This script demonstrates how to use rebar3's canonical project generators
# with HotCI enhancements for Erlang/OTP development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 A2A HotCI + rebar3 Canonical Generator Integration"
echo "=================================================="

# Check if we're in an Erlang project
if [ ! -f "$PROJECT_ROOT/rebar.config" ]; then
    echo "❌ Error: Not an Erlang project (rebar.config not found)"
    exit 1
fi

# Extract project info from rebar.config
PROJECT_NAME=$(grep -o '{name, [^}]*}' rebar.config | sed 's/{name, "\([^"]*\)"}/\1/' | head -1)
PROJECT_VERSION=$(grep -o '{vsn, "[^"]*"}' rebar.config | sed 's/{vsn, "\([^"]*\)"}/\1/' | head -1)

echo "📁 Project: $PROJECT_NAME v$PROJECT_VERSION"
echo ""

# Function to generate a canonical release project
generate_release_project() {
    local name="$1"
    local version="${2:-0.1.0}"
    local otp_version="${3:-28}"

    echo "🏗️  Generating canonical release project: $name"
    echo "   Version: $version"
    echo "   OTP Version: $otp_version"
    echo ""

    # Use the enhanced generator
    ./scripts/generate_project.sh generate release "$name" "$version" "$otp_version" \
        --hotci \
        --output "$PROJECT_ROOT/examples"

    echo "✅ Release project generated: $PROJECT_ROOT/examples/$name"
    echo ""
}

# Function to generate an umbrella project
generate_umbrella_project() {
    local name="$1"
    local apps="$2"
    local version="${3:-0.1.0}"
    local otp_version="${4:-28}"

    echo "🏗️  Generating canonical umbrella project: $name"
    echo "   Applications: $apps"
    echo "   Version: $version"
    echo "   OTP Version: $otp_version"
    echo ""

    # Generate umbrella with multiple apps
    ./scripts/generate_project.sh generate umbrella "$name" "$version" "$otp_version" "$apps" \
        --hotci \
        --output "$PROJECT_ROOT/examples"

    echo "✅ Umbrella project generated: $PROJECT_ROOT/examples/$name"
    echo ""
}

# Function to generate a single application
generate_application() {
    local name="$1"
    local version="${2:-0.1.0}"

    echo "📦 Generating canonical application: $name"
    echo "   Version: $version"
    echo ""

    ./scripts/generate_project.sh generate app "$name" \
        --output "$PROJECT_ROOT/examples/apps"

    echo "✅ Application generated: $PROJECT_ROOT/examples/apps/$name"
    echo ""
}

# Function to demonstrate HotCI integration
demonstrate_hotci_integration() {
    echo "🔥 Demonstrating HotCI Integration"
    echo "=================================="

    # Create HotCI-enhanced project
    ./scripts/generate_project.sh generate hotci "a2a_hotci_demo" \
        --version "1.0.0" \
        --otp "28" \
        --output "$PROJECT_ROOT/examples"

    echo "✅ HotCI-enhanced project created"
    echo ""

    # Show HotCI features
    echo "📋 HotCI Features Included:"
    echo "   • Hot code upgrade testing"
    echo "   • Multi-node coordination"
    echo "   • Performance monitoring"
    echo "   • Zero-downtime deployment validation"
    echo "   • Rolling upgrade support"
    echo "   • Blue-green deployment support"
    echo "   • Canary deployment support"
    echo "   • Automated rollback validation"
    echo ""
}

# Function to demonstrate rebar3 workflow
demonstrate_rebar3_workflow() {
    echo "⚙️  Demonstrating rebar3 Workflow Integration"
    echo "=========================================="

    cd "$PROJECT_ROOT"

    # Build with rebar3
    echo "🔨 Building with rebar3..."
    rebar3 compile

    # Run tests
    echo "🧪 Running tests..."
    rebar3 eunit
    rebar3 ct

    # Generate documentation
    echo "📚 Generating documentation..."
    rebar3 docs

    # Create release
    echo "📦 Creating release..."
    rebar3 release

    echo "✅ rebar3 workflow completed"
    echo ""
}

# Function to validate project structure
validate_project_structure() {
    echo "✅ Validating Project Structure"
    echo "=============================="

    # Check canonical rebar3 structure
    local structure_ok=true

    for dir in "src" "test" "config" "include"; do
        if [ -d "$dir" ]; then
            echo "   ✓ $dir/"
        else
            echo "   ❌ $dir/ (missing)"
            structure_ok=false
        fi
    done

    # Check HotCI integration
    if [ -d "hotci" ]; then
        echo "   ✓ hotci/ (HotCI integration)"
    else
        echo "   ⚠️  hotci/ (HotCI not yet integrated)"
    fi

    # Check rebar3 configuration
    if [ -f "rebar.config" ]; then
        echo "   ✓ rebar.config"

        # Check for HotCI profile
        if grep -q "hotci" rebar.config; then
            echo "   ✓ HotCI profile in rebar.config"
        fi

        # Check for proper OTP version
        if grep -q "minimum_otp_vsn" rebar.config; then
            echo "   ✓ OTP version specification"
        fi
    else
        echo "   ❌ rebar.config (missing)"
        structure_ok=false
    fi

    if [ "$structure_ok" = true ]; then
        echo ""
        echo "🎉 Project structure is valid and follows rebar3 canonical patterns!"
    else
        echo ""
        echo "⚠️  Project structure needs attention"
    fi
}

# Function to show best practices
show_best_practices() {
    echo "📖 rebar3 + HotCI Best Practices"
    echo "=============================="
    echo ""
    echo "🏗️  Project Structure:"
    echo "   • Use rebar3 new release for release projects"
    echo "   • Use rebar3 new umbrella for multi-app projects"
    echo "   • Use rebar3 new app for individual applications"
    echo "   • Follow canonical directory structure"
    echo ""
    echo "🔥 HotCI Integration:"
    echo "   • Enable hotci profile in rebar.config"
    echo "   • Include peer dependency for upgrade testing"
    echo "   • Use proper_test for property-based testing"
    echo "   • Implement upgrade_downgrade_SUITE"
    echo ""
    echo "📦 Version Management:"
    echo "   • Use semantic versioning (MAJOR.MINOR.PATCH)"
    echo "   • Include build metadata for snapshots"
    echo "   • Use relx for release management"
    echo ""
    echo "🧪 Testing Strategy:"
    echo "   • Unit tests with eunit"
    echo "   • Integration tests with common_test"
    echo "   • Hot upgrade tests with peer module"
    echo "   • Performance regression testing"
    echo ""
    echo "🚀 CI/CD Integration:"
    echo "   • GitHub Actions for automated builds"
    echo "   • Quality gates (dialyzer, cover)"
    echo "   • Artifact generation and deployment"
    echo "   • Release automation"
}

# Main execution
echo "🌟 Welcome to A2A HotCI + rebar3 Integration!"
echo ""

# Menu system
case "${1:-demo}" in
    demo)
        echo "🎬 Running demonstration..."
        echo ""

        validate_project_structure

        demonstrate_hotci_integration

        generate_release_project "api_service" "0.1.0" "28"

        generate_umbrella_project "microservice_platform" "core,gateway,auth,api" "1.0.0" "28"

        generate_application "user_service" "0.1.0"

        demonstrate_rebar3_workflow

        show_best_practices
        ;;

    generate)
        case "$2" in
            release)
                generate_release_project "$3" "$4" "$5"
                ;;
            umbrella)
                generate_umbrella_project "$3" "$4" "$5" "$6"
                ;;
            app)
                generate_application "$3" "$4"
                ;;
            hotci)
                demonstrate_hotci_integration
                ;;
            *)
                echo "Usage: $0 generate [release|umbrella|app|hotci] [args]"
                exit 1
                ;;
        esac
        ;;

    validate)
        validate_project_structure
        ;;

    best-practices)
        show_best_practices
        ;;

    help|--help|-h)
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  demo              Run complete demonstration"
        echo "  generate          Generate projects"
        echo "    release         Generate release project"
        echo "    umbrella        Generate umbrella project"
        echo "    app             Generate application"
        echo "    hotci           Generate HotCI project"
        echo "  validate          Validate project structure"
        echo "  best-practices    Show best practices"
        echo "  help              Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 generate release myapi 1.0.0 28"
        echo "  $0 generate umbrella myapp core,auth 1.0.0 28"
        echo "  $0 generate myapp"
        ;;

    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac

echo ""
echo "🎉 Integration complete! Happy coding with A2A HotCI + rebar3!"