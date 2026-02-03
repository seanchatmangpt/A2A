#!/bin/bash

# HotCI Release Management CLI
# Unified command-line interface for release management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_MANAGER="$SCRIPT_DIR/version-manager.sh"
RELEASE_MANAGER="$SCRIPT_DIR/release-manager.sh"
PUBLISH_MANAGER="$SCRIPT_DIR/publish-release.sh"
ROLLBACK_MANAGER="$SCRIPT_DIR/rollback-manager.sh"
MONITOR="$SCRIPT_DIR/release-monitor.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}HotCI Release Management CLI${NC}"
    echo "=================================="
}

print_command() {
    echo -e "${BLUE}Command:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Main menu
show_main_menu() {
    print_header
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "1. Version Management"
    echo "2. Build & Package"
    echo "3. Publishing"
    echo "4. Monitoring & Health"
    echo "5. Rollback & Recovery"
    echo "6. Quick Actions"
    echo "7. Help"
    echo "8. Exit"
    echo ""
    read -p "Enter your choice [1-8]: " choice
}

# Version Management submenu
show_version_menu() {
    print_header
    echo ""
    echo "Version Management"
    echo "=================="
    echo ""
    echo "1. Show current version"
    echo "2. Bump version (major|minor|patch)"
    echo "3. Bump version (prerelease|metadata|snapshot)"
    echo "4. Format version for release"
    echo "5. Validate version format"
    echo "6. Initialize version file"
    echo "7. Back to main menu"
    echo ""
    read -p "Enter your choice [1-7]: " choice

    case $choice in
        1)
            print_command "show current version"
            $VERSION_MANAGER current
            ;;
        2)
            print_command "bump version"
            echo "Available types: major, minor, patch"
            read -p "Enter version type: " type
            if [[ "$type" =~ ^(major|minor|patch)$ ]]; then
                $VERSION_MANAGER bump $type
                print_success "Version bumped to $(cat VERSION)"
            else
                print_error "Invalid version type"
            fi
            ;;
        3)
            print_command "bump pre-release version"
            echo "Available types: prerelease, metadata, snapshot"
            read -p "Enter version type: " type
            if [[ "$type" =~ ^(prerelease|metadata|snapshot)$ ]]; then
                $VERSION_MANAGER bump $type
                print_success "Version bumped to $(cat VERSION)"
            else
                print_error "Invalid version type"
            fi
            ;;
        4)
            print_command "format version for release"
            read -p "Enter version to format: " version
            formatted=$($VERSION_MANAGER format $version)
            print_success "Formatted version: $formatted"
            ;;
        5)
            print_command "validate version format"
            read -p "Enter version to validate: " version
            if $VERSION_MANAGER validate $version; then
                print_success "Version $version is valid"
            else
                print_error "Invalid version format"
            fi
            ;;
        6)
            print_command "initialize version file"
            read -p "Enter initial version (default: 0.1.0): " initial
            initial=${initial:-0.1.0}
            $VERSION_MANAGER init $initial
            print_success "Version file initialized to $initial"
            ;;
        7)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

# Build & Package submenu
show_build_menu() {
    print_header
    echo ""
    echo "Build & Package"
    echo "==============="
    echo ""
    echo "1. Build complete release"
    echo "2. Run tests and checks"
    echo "3. Create release package only"
    echo "4. Build Docker image only"
    echo "5. Validate release package"
    echo "6. Clean build artifacts"
    echo "7. Back to main menu"
    echo ""
    read -p "Enter your choice [1-7]: " choice

    case $choice in
        1)
            print_command "build complete release"
            $RELEASE_MANAGER build
            print_success "Release build completed"
            ;;
        2)
            print_command "run tests and checks"
            $RELEASE_MANAGER test
            print_success "Tests completed"
            ;;
        3)
            print_command "create release package"
            VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
            $RELEASE_MANAGER package $VERSION
            print_success "Package created"
            ;;
        4)
            print_command "build Docker image"
            VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
            $RELEASE_MANAGER docker $VERSION
            print_success "Docker image built"
            ;;
        5)
            print_command "validate release package"
            VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
            $RELEASE_MANAGER validate $VERSION
            print_success "Release validated"
            ;;
        6)
            print_command "clean build artifacts"
            $RELEASE_MANAGER clean
            print_success "Build artifacts cleaned"
            ;;
        7)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

# Publishing submenu
show_publish_menu() {
    print_header
    echo ""
    echo "Publishing"
    echo "==========="
    echo ""
    echo "1. Publish to GitHub"
    echo "2. Publish to Docker Registry"
    echo "3. Create draft release"
    echo "4. Create pre-release"
    echo "5. List GitHub releases"
    echo "6. Back to main menu"
    echo ""
    read -p "Enter your choice [1-6]: " choice

    case $choice in
        1)
            print_command "publish to GitHub"
            $PUBLISH_MANAGER publish
            print_success "Published to GitHub"
            ;;
        2)
            print_command "publish to Docker Registry"
            $PUBLISH_MANAGER publish-docker
            print_success "Published to Docker Registry"
            ;;
        3)
            print_command "create draft release"
            $PUBLISH_MANAGER publish --draft
            print_success "Draft release created"
            ;;
        4)
            print_command "create pre-release"
            $PUBLISH_MANAGER publish --pre-release
            print_success "Pre-release created"
            ;;
        5)
            print_command "list GitHub releases"
            if command -v gh >/dev/null 2>&1; then
                gh release list --limit 10
            else
                print_error "GitHub CLI not installed"
            fi
            ;;
        6)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

# Monitoring submenu
show_monitor_menu() {
    print_header
    echo ""
    echo "Monitoring & Health"
    echo "==================="
    echo ""
    echo "1. Show release status"
    echo "2. Check release health"
    echo "3. Show release metrics"
    echo "4. Show version history"
    echo "5. List artifacts"
    echo "6. Compare versions"
    echo "7. Show release trends"
    echo "8. Check alerts"
    echo "9. Back to main menu"
    echo ""
    read -p "Enter your choice [1-9]: " choice

    case $choice in
        1)
            print_command "show release status"
            $MONITOR status
            ;;
        2)
            print_command "check release health"
            $MONITOR health
            ;;
        3)
            print_command "show release metrics"
            $MONITOR metrics
            ;;
        4)
            print_command "show version history"
            $MONITOR versions
            ;;
        5)
            print_command "list artifacts"
            $MONITOR artifacts
            ;;
        6)
            print_command "compare versions"
            read -p "Enter first version: " v1
            read -p "Enter second version: " v2
            $MONITOR compare $v1 $v2
            ;;
        7)
            print_command "show release trends"
            $MONITOR trends
            ;;
        8)
            print_command "check alerts"
            $MONITOR alerts
            ;;
        9)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

# Rollback submenu
show_rollback_menu() {
    print_header
    echo ""
    echo "Rollback & Recovery"
    echo "==================="
    echo ""
    echo "1. Show rollback status"
    echo "2. List available rollback versions"
    echo "3. Rollback to last version"
    echo "4. Rollback to specific version"
    echo "5. Create rollback tag"
    echo "6. Recover from rollback tag"
    echo "7. Back to main menu"
    echo ""
    read -p "Enter your choice [1-7]: " choice

    case $choice in
        1)
            print_command "show rollback status"
            $ROLLBACK_MANAGER status
            ;;
        2)
            print_command "list available rollback versions"
            $ROLLBACK_MANAGER list
            ;;
        3)
            print_command "rollback to last version"
            $ROLLBACK_MANAGER rollback-last
            print_success "Rolled back to last version"
            ;;
        4)
            print_command "rollback to specific version"
            read -p "Enter version to rollback to: " version
            $ROLLBACK_MANAGER rollback $version
            print_success "Rolled back to version $version"
            ;;
        5)
            print_command "create rollback tag"
            read -p "Enter tag name: " tag
            $ROLLBACK_MANAGER tag $tag
            print_success "Rollback tag created: $tag"
            ;;
        6)
            print_command "recover from rollback tag"
            read -p "Enter rollback tag: " tag
            $ROLLBACK_MANAGER recover $tag
            print_success "Recovered from tag: $tag"
            ;;
        7)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

# Quick Actions
show_quick_actions() {
    print_header
    echo ""
    echo "Quick Actions"
    echo "============="
    echo ""
    echo "1. Release workflow (build + publish)"
    echo "2. Version bump + commit"
    echo "3. Health check"
    echo "4. Clean all artifacts"
    echo "5. Show current version"
    echo "6. Back to main menu"
    echo ""
    read -p "Enter your choice [1-6]: " choice

    case $choice in
        1)
            print_command "release workflow"
            echo "Building release..."
            $RELEASE_MANAGER build
            echo "Publishing release..."
            $PUBLISH_MANAGER publish
            print_success "Release workflow completed"
            ;;
        2)
            print_command "version bump + commit"
            echo "Available types: major, minor, patch"
            read -p "Enter version type: " type
            if [[ "$type" =~ ^(major|minor|patch)$ ]]; then
                echo "Commit message (optional):"
                read -p "> " message
                ./scripts/bump-version.sh $type "$message"
                print_success "Version bumped and committed"
            else
                print_error "Invalid version type"
            fi
            ;;
        3)
            print_command "health check"
            $MONITOR health
            ;;
        4)
            print_command "clean all artifacts"
            $RELEASE_MANAGER clean
            echo "Cleaning Docker images..."
            docker images | grep a2a-erl | awk '{print $3}' | xargs -r docker rmi 2>/dev/null || true
            print_success "All artifacts cleaned"
            ;;
        5)
            print_command "show current version"
            cat VERSION 2>/dev/null || echo "No VERSION file found"
            ;;
        6)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
}

# Show help
show_help() {
    print_header
    echo ""
    echo "HotCI Release Management CLI Help"
    echo "================================="
    echo ""
    echo "This CLI provides an interactive interface for managing releases."
    echo ""
    echo "Main Features:"
    echo "- Version Management: Smoothver version handling"
    echo "- Build & Package: Create release artifacts"
    echo "- Publishing: GitHub and Docker publishing"
    echo "- Monitoring: Release health and metrics"
    echo "- Rollback: Safe version rollback"
    echo ""
    echo "Usage:"
    echo "  $0                   Interactive CLI"
    echo "  $0 <command>         Direct command execution"
    echo ""
    echo "Direct Commands:"
    echo "  version              Show current version"
    echo "  build                Build release"
    echo "  publish              Publish release"
    echo "  monitor              Monitor releases"
    echo "  rollback             Rollback release"
    echo "  help                 Show this help"
    echo ""
}

# Main execution
if [ $# -eq 0 ]; then
    # Interactive mode
    while true; do
        show_main_menu
        echo ""
        case $choice in
            1)
                show_version_menu
                ;;
            2)
                show_build_menu
                ;;
            3)
                show_publish_menu
                ;;
            4)
                show_monitor_menu
                ;;
            5)
                show_rollback_menu
                ;;
            6)
                show_quick_actions
                ;;
            7)
                show_help
                ;;
            8)
                print_header
                echo "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                echo ""
                ;;
        esac
    done
else
    # Direct command execution
    command="$1"
    shift

    case "$command" in
        "version")
            $VERSION_MANAGER current
            ;;
        "build")
            $RELEASE_MANAGER build
            ;;
        "publish")
            $PUBLISH_MANAGER publish
            ;;
        "monitor")
            $MONITOR status
            ;;
        "rollback")
            $ROLLBACK_MANAGER rollback-last
            ;;
        "help")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
fi