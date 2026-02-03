#!/bin/bash

# Version Bump Script - HotCI-style
# Quick version bumping with smoothver support

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_MANAGER="$SCRIPT_DIR/version-manager.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

usage() {
    echo "Quick Version Bump Script"
    echo ""
    echo "Usage: $0 <bump_type> [commit_message]"
    echo ""
    echo "Bump types:"
    echo "  major       Major version increment (X.0.0)"
    echo "  minor       Minor version increment (0.X.0)"
    echo "  patch       Patch version increment (0.0.X)"
    echo "  prerelease  Pre-release increment (alpha, beta, rc)"
    echo "  metadata    Build metadata increment"
    echo "  snapshot    Snapshot release with timestamp"
    echo ""
    echo "Examples:"
    echo "  $0 patch"
    echo "  $0 minor 'Add new authentication feature'"
    echo "  $0 prerelease"
}

main() {
    local bump_type="$1"
    local commit_message="$2"

    if [ -z "$bump_type" ]; then
        usage
        exit 1
    fi

    # Validate bump type
    case "$bump_type" in
        major|minor|patch|prerelease|metadata|snapshot)
            ;;
        *)
            print_error "Invalid bump type: $bump_type"
            usage
            exit 1
            ;;
    esac

    print_info "Bumping version: $bump_type"

    # Get current version
    current_version="$("$VERSION_MANAGER" current)"
    print_info "Current version: $current_version"

    # Bump version
    new_version="$("$VERSION_MANAGER" bump "$bump_type")"
    release_version="$("$VERSION_MANAGER" format "$new_version")"

    print_info "New version: $new_version"
    print_info "Release version: $release_version"

    # Update version files
    "$VERSION_MANAGER" bump "$bump_type"

    # Generate commit message
    if [ -n "$commit_message" ]; then
        final_message="$commit_message"
    else
        case "$bump_type" in
            major)
                final_message="chore: Bump version to $release_version (major release)"
                ;;
            minor)
                final_message="feat: Bump version to $release_version (minor release)"
                ;;
            patch)
                final_message="fix: Bump version to $release_version (patch release)"
                ;;
            prerelease)
                final_message="chore: Bump version to $release_version (pre-release)"
                ;;
            metadata)
                final_message="chore: Bump version to $release_version (build metadata)"
                ;;
            snapshot)
                final_message="chore: Bump version to $release_version (snapshot)"
                ;;
        esac
    fi

    # Git operations
    if git diff --quiet && git diff --cached --quiet; then
        print_warning "No changes to commit"
        print_info "Version updated in files, but not committed"
        exit 0
    fi

    print_info "Committing version bump: $final_message"
    git add VERSION rebar.config Makefile 2>/dev/null || true
    git commit -m "$final_message"

    # Create tag if it's a major, minor, or patch release
    if [[ "$bump_type" =~ ^(major|minor|patch)$ ]]; then
        print_info "Creating release tag: v$release_version"
        git tag -a "v$release_version" -m "Release v$release_version"
    fi

    print_success "Version bump completed!"
    print_info "New version: $new_version"
    print_info "Release tag: v$release_version" 2>/dev/null || echo "No tag created (pre-release/snapshot)"
}

# Execute main function
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

main "$1" "$2"