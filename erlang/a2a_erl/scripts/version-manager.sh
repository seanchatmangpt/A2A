#!/bin/bash

# Smoothver Version Manager for A2A Erlang
# Implements HotCI-style version management with build metadata

set -euo pipefail

# Configuration
VERSION_FILE="VERSION"
REBAR_CONFIG="rebar.config"
CHANGELOG="CHANGELOG.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to get current version
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        # Extract from rebar.config
        grep -oP '{release, {a2a_erl, "\K[^"]+' "$REBAR_CONFIG" || echo "0.1.0"
    fi
}

# Function to validate version format
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+(\.[0-9]+)*)?$ ]]; then
        print_error "Invalid version format: $version"
        echo "Expected format: MAJOR.MINOR.PATCH[-PRERELEASE[.BUILD]]"
        exit 1
    fi
}

# Function to bump version based on type
bump_version() {
    local bump_type="$1"
    local current_version="$2"

    # Parse version components
    if [[ "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(.*)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        local metadata="${BASH_REMATCH[4]}"

        case "$bump_type" in
            "major")
                major=$((major + 1))
                minor=0
                patch=0
                metadata=""
                ;;
            "minor")
                minor=$((minor + 1))
                patch=0
                metadata=""
                ;;
            "patch")
                patch=$((patch + 1))
                metadata=""
                ;;
            "prerelease")
                if [[ -n "$metadata" ]]; then
                    # Increment existing prerelease
                    if [[ "$metadata" =~ ^\.([a-zA-Z0-9]+)(\.[0-9]+)?$ ]]; then
                        local prerelease="${BASH_REMATCH[1]}"
                        local build="${BASH_REMATCH[2]:1}"
                        build=$((10#${build:-0} + 1))
                        metadata=".$prerelease.$build"
                    else
                        # Start new prerelease sequence
                        metadata=".alpha.1"
                    fi
                else
                    # Start with alpha prerelease
                    metadata=".alpha.1"
                fi
                ;;
            "metadata")
                if [[ -n "$metadata" ]]; then
                    if [[ "$metadata" =~ ^\.([a-zA-Z0-9]+)$ ]]; then
                        local prerelease="${BASH_REMATCH[1]}"
                        metadata=".$prerelease"
                    else
                        # Add build timestamp to existing metadata
                        local timestamp=$(date +%s)
                        metadata="$metadata.$timestamp"
                    fi
                else
                    local timestamp=$(date +%s)
                    metadata=".$timestamp"
                fi
                ;;
            "snapshot")
                local timestamp=$(date +%Y%m%d%H%M%S)
                metadata="-snapshot.$timestamp"
                ;;
            *)
                print_error "Unknown bump type: $bump_type"
                echo "Available types: major, minor, patch, prerelease, metadata, snapshot"
                exit 1
                ;;
        esac

        echo "${major}.${minor}.${patch}${metadata}"
    else
        print_error "Failed to parse version: $current_version"
        exit 1
    fi
}

# Function to format version for release
format_version_for_release() {
    local version="$1"
    # Remove metadata for official releases
    echo "$version" | sed 's/-.*//'
}

# Function to update version in all files
update_version_files() {
    local new_version="$1"
    local release_version="$2"

    # Update VERSION file if it exists
    if [ -f "$VERSION_FILE" ]; then
        echo "$new_version" > "$VERSION_FILE"
        print_info "Updated $VERSION_FILE to $new_version"
    fi

    # Update rebar.config
    sed -i "s/{release, {a2a_erl, \".*\"}/{release, {a2a_erl, \"$release_version\"}/g" "$REBAR_CONFIG"
    print_info "Updated $REBAR_CONFIG to $release_version"

    # Update Docker-related files if they exist
    if [ -f "Makefile" ]; then
        sed -i "s/VERSION ?= .*/VERSION ?= $release_version/" Makefile
        print_info "Updated Makefile VERSION to $release_version"
    fi
}

# Function to generate changelog entry
generate_changelog_entry() {
    local version="$1"
    local bump_type="$2"
    local date=$(date +%Y-%m-%d)

    echo "## [$version] - $date"

    case "$bump_type" in
        "major")
            echo -e "\n### Major Changes\n"
            echo "- Breaking changes and new major version\n"
            ;;
        "minor")
            echo -e "\n### Features\n"
            echo "- New features added in this minor release\n"
            ;;
        "patch")
            echo -e "\n### Bug Fixes\n"
            echo "- Bug fixes and improvements in this patch release\n"
            ;;
        *)
            echo -e "\n### Changes\n"
            echo "- Changes in this release\n"
            ;;
    esac

    echo ""
}

# Function to create release tag
create_release_tag() {
    local version="$1"
    local message="Release v$version"

    if ! git tag -l "v$version" | grep -q "v$version"; then
        git tag -a "v$version" -m "$message"
        print_success "Created release tag: v$version"
    else
        print_warning "Tag v$version already exists"
    fi
}

# Main functions
usage() {
    echo "Smoothver Version Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  current              Show current version"
    echo "  bump <type>          Bump version (major|minor|patch|prerelease|metadata|snapshot)"
    echo "  release <type>       Perform release (bump, tag, update files)"
    echo "  format <version>     Format version for release (remove metadata)"
    echo "  validate <version>   Validate version format"
    echo "  init                Initialize version file"
    echo ""
    echo "Examples:"
    echo "  $0 current"
    echo "  $0 bump minor"
    echo "  $0 release patch"
    echo "  $0 format 1.2.3-alpha.1"
}

cmd_current() {
    get_current_version
}

cmd_bump() {
    local bump_type="$1"
    local current_version=$(get_current_version)

    if [ -z "$bump_type" ]; then
        print_error "Please specify bump type"
        usage
        exit 1
    fi

    validate_version "$current_version"
    local new_version=$(bump_version "$bump_type" "$current_version")

    print_info "Current version: $current_version"
    print_success "New version: $new_version"

    # Create git commit if we're not in CI
    if [ "${CI:-false}" != "true" ]; then
        read -p "Commit version bump? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_version_files "$new_version" "$new_version"
            git add "$VERSION_FILE" "$REBAR_CONFIG" "Makefile" 2>/dev/null || true
            git commit -m "chore: Bump version to $new_version"
            print_success "Committed version bump"
        fi
    fi
}

cmd_release() {
    local bump_type="$1"

    if [ -z "$bump_type" ]; then
        print_error "Please specify release type"
        usage
        exit 1
    fi

    local current_version=$(get_current_version)
    local new_version=$(bump_version "$bump_type" "$current_version")
    local release_version=$(format_version_for_release "$new_version")

    print_info "Current version: $current_version"
    print_info "New version: $new_version"
    print_info "Release version: $release_version"

    # Update files
    update_version_files "$new_version" "$release_version"

    # Update changelog
    if [ -f "$CHANGELOG" ]; then
        # Create temporary file with new entry
        local temp_changelog=$(mktemp)
        generate_changelog_entry "$release_version" "$bump_type" > "$temp_changelog"
        cat "$CHANGELOG" >> "$temp_changelog"
        mv "$temp_changelog" "$CHANGELOG"
        print_info "Updated $CHANGELOG"
    fi

    # Create git commit and tag
    git add "$VERSION_FILE" "$REBAR_CONFIG" "$CHANGELOG" "Makefile" 2>/dev/null || true
    git commit -m "Release v$release_version"
    create_release_tag "$release_version"

    # Push changes and tags
    if [ "${CI:-false}" != "true" ]; then
        read -p "Push changes and tags? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git push
            git push --tags
            print_success "Release pushed to remote"
        fi
    fi

    print_success "Release v$release_version completed"
}

cmd_format() {
    local version="$1"
    if [ -z "$version" ]; then
        print_error "Please specify version to format"
        usage
        exit 1
    fi

    validate_version "$version"
    local formatted=$(format_version_for_release "$version")
    echo "$formatted"
}

cmd_validate() {
    local version="$1"
    if [ -z "$version" ]; then
        print_error "Please specify version to validate"
        usage
        exit 1
    fi

    if validate_version "$version" >/dev/null 2>&1; then
        print_success "Valid version: $version"
    else
        print_error "Invalid version: $version"
        exit 1
    fi
}

cmd_init() {
    local initial_version="${1:-0.1.0}"

    validate_version "$initial_version"

    if [ -f "$VERSION_FILE" ]; then
        read -p "VERSION file already exists. Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    echo "$initial_version" > "$VERSION_FILE"
    print_success "Initialized version: $initial_version"

    # Commit initial version file
    if [ "${CI:-false}" != "true" ]; then
        git add "$VERSION_FILE"
        git commit -m "chore: Initialize version to $initial_version" 2>/dev/null || true
    fi
}

# Main script execution
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    "current")
        cmd_current
        ;;
    "bump")
        cmd_bump "$1"
        ;;
    "release")
        cmd_release "$1"
        ;;
    "format")
        cmd_format "$1"
        ;;
    "validate")
        cmd_validate "$1"
        ;;
    "init")
        cmd_init "$1"
        ;;
    *)
        print_error "Unknown command: $command"
        usage
        exit 1
        ;;
esac