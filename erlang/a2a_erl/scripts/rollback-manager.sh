#!/bin/bash

# HotCI-style Rollback Manager
# Safe rollback mechanism for releases

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_MANAGER="$SCRIPT_DIR/version-manager.sh"
RELEASE_MANAGER="$SCRIPT_DIR/release-manager.sh"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_ROOT/VERSION"

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

# Function to show help
usage() {
    echo "HotCI-style Rollback Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list             List available releases for rollback"
    echo "  last             Get last released version"
    echo "  rollback <version>  Rollback to specific version"
    echo "  rollback-last     Rollback to last released version"
    echo "  tag <version>     Create rollback tag"
    echo "  recover <tag>     Recover from rollback tag"
    echo "  status           Show rollback status"
    echo "  help             Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 rollback 1.0.0"
    echo "  $0 rollback-last"
    echo "  $0 tag rollback-v1.0.0"
}

# Function to get list of releases from GitHub
get_release_list() {
    if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI not found"
        return 1
    fi

    gh release list --json tagName,createdAt,author --jq '.[] | "\(.tagName) - \(.createdAt) - \(.author.login)"' 2>/dev/null || echo "No releases found"
}

# Function to get last released version
get_last_release() {
    if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI not found"
        return 1
    fi

    local last_tag=$(gh release list --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")

    if [ -n "$last_tag" ]; then
        echo "$last_tag"
    else
        # Check local VERSION file
        if [ -f "$VERSION_FILE" ]; then
            cat "$VERSION_FILE"
        else
            echo ""
        fi
    fi
}

# Function to check if rollback is safe
check_rollback_safety() {
    local target_version="$1"
    local current_version=$(cat "$VERSION_FILE" 2>/dev/null || echo "")

    if [ -z "$target_version" ]; then
        print_error "No target version specified"
        return 1
    fi

    print_info "Target version: $target_version"
    print_info "Current version: $current_version"

    # Check if target version is newer than current
    if [ "$target_version" = "$current_version" ]; then
        print_warning "Target version is same as current version"
        return 0
    fi

    # Check git status
    if ! git diff --quiet && git diff --cached --quiet; then
        print_error "Working directory is not clean"
        print_info "Please commit or stash changes before rolling back"
        return 1
    fi

    return 0
}

# Function to backup current state
backup_current_state() {
    local backup_name="rollback-backup-$(date +%Y%m%d%H%M%S)"

    print_info "Creating backup: $backup_name"

    # Create backup directory
    local backup_dir="_build/backups/$backup_name"
    mkdir -p "$backup_dir"

    # Backup version file
    if [ -f "$VERSION_FILE" ]; then
        cp "$VERSION_FILE" "$backup_dir/"
    fi

    # Backup rebar.config
    cp "rebar.config" "$backup_dir/"

    # Backup git state
    git log --oneline -5 > "$backup_dir/git-log.txt"
    git status > "$backup_dir/git-status.txt"

    # Create archive
    cd "_build/backups"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    cd "$PROJECT_ROOT"

    print_success "Backup created: $backup_dir"
    echo "$backup_name"
}

# Function to restore from backup
restore_from_backup() {
    local backup_name="$1"
    local backup_dir="_build/backups/$backup_name"

    if [ ! -d "$backup_dir" ]; then
        print_error "Backup not found: $backup_name"
        return 1
    fi

    print_info "Restoring from backup: $backup_name"

    # Restore version file
    if [ -f "$backup_dir/VERSION" ]; then
        cp "$backup_dir/VERSION" "$VERSION_FILE"
    fi

    # Restore rebar.config
    if [ -f "$backup_dir/rebar.config" ]; then
        cp "$backup_dir/rebar.config" "rebar.config"
    fi

    # Commit the changes
    git add VERSION rebar.config
    git commit -m "chore: Restore from backup $backup_name"

    print_success "Backup restored: $backup_name"
}

# Function to rollback version
rollback_version() {
    local target_version="$1"

    # Check safety
    if ! check_rollback_safety "$target_version"; then
        return 1
    fi

    # Backup current state
    local backup_name=$(backup_current_state)

    # Update version files
    print_info "Updating version to: $target_version"

    # Update VERSION file
    echo "$target_version" > "$VERSION_FILE"

    # Update rebar.config
    sed -i "s/{release, {a2a_erl, \".*\"}/{release, {a2a_erl, \"$target_version\"}/g" rebar.config

    # Commit the rollback
    git add VERSION rebar.config
    git commit -m "chore: Rollback to version $target_version"

    # Create rollback tag
    git tag -a "rollback-$(date +%Y%m%d-%H%M%S)" -m "Rollback to $target_version"

    print_success "Rolled back to version: $target_version"
    print_info "Backup created: $backup_name"
    print_info "Rollback tag: rollback-$(date +%Y%m%d-%H%M%S)"

    # Warn about rebuild needed
    print_warning "Run 'make build-release' to rebuild artifacts for version $target_version"
}

# Function to recover from rollback tag
recover_from_rollback_tag() {
    local tag="$1"

    if [ -z "$tag" ]; then
        print_error "Please specify rollback tag to recover from"
        usage
        return 1
    fi

    if ! git tag -l "$tag" | grep -q "$tag"; then
        print_error "Rollback tag not found: $tag"
        return 1
    fi

    print_info "Recovering from rollback tag: $tag"

    # Get the version from the tag
    local target_version=$(git show "$tag:VERSION" 2>/dev/null || git describe --tags --abbrev=0 "$tag" 2>/dev/null || echo "")

    if [ -z "$target_version" ]; then
        print_error "Could not determine version from tag: $tag"
        return 1
    fi

    # Checkout the tag
    git checkout "$tag"

    # Update current files if needed
    if [ -f "VERSION" ]; then
        git add VERSION
        git commit -m "chore: Recover VERSION from tag $tag" || true
    fi

    print_success "Recovered from tag: $tag"
    print_info "Current version: $target_version"
}

# Function to create rollback tag
create_rollback_tag() {
    local tag_name="$1"

    if [ -z "$tag_name" ]; then
        print_error "Please specify tag name"
        usage
        return 1
    fi

    # Check if tag already exists
    if git tag -l "$tag_name" | grep -q "$tag_name"; then
        print_error "Tag already exists: $tag_name"
        return 1
    fi

    print_info "Creating rollback tag: $tag_name"

    # Create tag with current state
    git tag -a "$tag_name" -m "Rollback point: $(cat "$VERSION_FILE" 2>/dev/null || echo unknown)"

    print_success "Rollback tag created: $tag_name"
}

# Function to show rollback status
show_rollback_status() {
    print_info "Rollback Status"
    echo ""

    # Current version
    if [ -f "$VERSION_FILE" ]; then
        print_info "Current Version: $(cat "$VERSION_FILE")"
    fi

    # Git status
    print_info "Git Status:"
    if git diff --quiet && git diff --cached --quiet; then
        print_success "Working directory is clean"
    else
        print_warning "Working directory has changes"
    fi

    # Git tags
    print_info "Available Rollback Tags:"
    git tag | grep -E "rollback-|v[0-9]" | head -10 | while read tag; do
        local tag_date=$(git log -1 --format="%ci" "$tag")
        local tag_version=$(git show "$tag:VERSION" 2>/dev/null || git describe --tags --abbrev=0 "$tag" 2>/dev/null || echo "unknown")
        echo "  $tag ($tag_version) - $tag_date"
    done

    # GitHub releases
    if command -v gh >/dev/null 2>&1; then
        print_info "GitHub Releases:"
        gh release list --limit 5 --json tagName,createdAt --jq '.[] | "  \(.tagName) - \(.createdAt)"' 2>/dev/null || echo "  No releases found"
    fi

    # Backups
    if [ -d "_build/backups" ]; then
        print_info "Local Backups:"
        ls -1 "_build/backups/" 2>/dev/null | grep "\.tar.gz$" | while read backup; do
            echo "  $backup"
        done
    fi
}

# Main commands
cmd_list() {
    print_info "Available Releases"
    echo ""
    get_release_list
}

cmd_last() {
    local last_version=$(get_last_release)
    if [ -n "$last_version" ]; then
        print_success "Last released version: $last_version"
    else
        print_warning "No releases found"
    fi
}

cmd_rollback() {
    local target_version="$1"

    if [ -z "$target_version" ]; then
        print_error "Please specify version to rollback to"
        usage
        return 1
    fi

    rollback_version "$target_version"
}

cmd_rollback_last() {
    local last_version=$(get_last_release)

    if [ -z "$last_version" ]; then
        print_error "No releases found to rollback to"
        return 1
    fi

    rollback_version "$last_version"
}

cmd_tag() {
    local tag_name="$1"

    if [ -z "$tag_name" ]; then
        print_error "Please specify tag name"
        usage
        return 1
    fi

    create_rollback_tag "$tag_name"
}

cmd_recover() {
    local tag="$1"

    if [ -z "$tag" ]; then
        print_error "Please specify rollback tag"
        usage
        return 1
    fi

    recover_from_rollback_tag "$tag"
}

cmd_status() {
    show_rollback_status
}

# Main script execution
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    "list")
        cmd_list
        ;;
    "last")
        cmd_last
        ;;
    "rollback")
        cmd_rollback "$1"
        ;;
    "rollback-last")
        cmd_rollback_last
        ;;
    "tag")
        cmd_tag "$1"
        ;;
    "recover")
        cmd_recover "$1"
        ;;
    "status")
        cmd_status
        ;;
    "help"|*)
        usage
        ;;
esac