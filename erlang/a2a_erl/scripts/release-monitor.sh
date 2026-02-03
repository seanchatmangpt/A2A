#!/bin/bash

# HotCI-style Release Monitor
# Monitor release status, health, and metrics

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/_build"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_metrics() {
    echo -e "${PURPLE}[METRICS]${NC} $1"
}

# Function to show help
usage() {
    echo "HotCI-style Release Monitor"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status             Show overall release status"
    echo "  health             Check release health"
    echo "  metrics            Show release metrics"
    echo "  versions          Show version history"
    echo "  artifacts          List available artifacts"
    echo "  compare <v1> <v2>  Compare two versions"
    echo "  trends            Show release trends"
    echo "  alerts            Check for alerts"
    echo "  help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 metrics"
    echo "  $0 compare 1.0.0 1.1.0"
}

# Function to get overall release status
get_release_status() {
    print_info "Release Status Overview"
    echo "========================"

    # Current version
    if [ -f "$VERSION_FILE" ]; then
        print_success "Current Version: $(cat "$VERSION_FILE")"
    else
        print_warning "No VERSION file found"
    fi

    # Git status
    echo ""
    print_info "Git Status:"
    if git diff --quiet && git diff --cached --quiet; then
        print_success "Working directory clean"
    else
        print_error "Working directory has uncommitted changes"
    fi

    # Branch information
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    print_info "Current Branch: $current_branch"

    # Recent commits
    echo ""
    print_info "Recent Commits (5):"
    git log --oneline -5

    # Git tags
    echo ""
    print_info "Git Tags (5 most recent):"
    git tag | grep -E "v[0-9]" | head -5 | while read tag; do
        local tag_date=$(git log -1 --format="%ci" "$tag")
        echo "  $tag - $tag_date"
    done
}

# Function to check release health
check_release_health() {
    print_info "Release Health Check"
    echo "===================="

    local health_score=0
    local max_score=10

    # Check version file
    if [ -f "$VERSION_FILE" ]; then
        ((health_score += 2))
        print_success "Version file present"
    else
        print_error "Version file missing"
    fi

    # Check rebar.config
    if [ -f "rebar.config" ]; then
        ((health_score += 1))
        print_success "rebar.config present"
    else
        print_error "rebar.config missing"
    fi

    # Check build artifacts
    if [ -d "$BUILD_DIR" ]; then
        local artifact_count=$(find "$BUILD_DIR" -name "*.tar.gz" | wc -l)
        if [ "$artifact_count" -gt 0 ]; then
            ((health_score += 2))
            print_success "Found $artifact_count build artifacts"
        else
            print_warning "No build artifacts found"
        fi
    else
        print_warning "No build directory found"
    fi

    # Check CHANGELOG.md
    if [ -f "CHANGELOG.md" ]; then
        ((health_score += 1))
        print_success "CHANGELOG.md present"
    else
        print_warning "CHANGELOG.md missing"
    else
        print_warning "CHANGELOG.md missing"
    fi

    # Check Dockerfile
    if [ -f "Dockerfile" ]; then
        ((health_score += 1))
        print_success "Dockerfile present"
    else
        print_warning "Dockerfile missing"
    fi

    # Check GitHub Actions
    if [ -d ".github/workflows" ]; then
        ((health_score += 2))
        print_success "GitHub Actions workflows present"
    else
        print_warning "No GitHub Actions workflows"
    fi

    # Check documentation
    if [ -d "doc" ]; then
        ((health_score += 1))
        print_success "Documentation directory present"
    else
        print_warning "No documentation directory"
    fi

    # Calculate health percentage
    local health_percentage=$((health_score * 10 / max_score))

    echo ""
    print_metrics "Overall Health Score: $health_score/$max_score ($health_percentage%)"

    # Health status
    if [ "$health_percentage" -ge 80 ]; then
        print_success "✓ Excellent health"
    elif [ "$health_percentage" -ge 60 ]; then
        print_success "✓ Good health"
    elif [ "$health_percentage" -ge 40 ]; then
        print_warning "⚠ Fair health"
    else
        print_error "✗ Poor health - immediate attention needed"
    fi
}

# Function to show release metrics
show_release_metrics() {
    print_info "Release Metrics"
    echo "==============="

    # Version metrics
    echo ""
    print_metrics "Version Metrics:"
    if [ -f "$VERSION_FILE" ]; then
        local current_version=$(cat "$VERSION_FILE")
        local major=$(echo "$current_version" | cut -d. -f1)
        local minor=$(echo "$current_version" | cut -d. -f2)
        local patch=$(echo "$current_version" | cut -d. -f3)

        echo "  Current: $current_version"
        echo "  Major: $major"
        echo "  Minor: $minor"
        echo "  Patch: $patch"
    fi

    # Build metrics
    echo ""
    print_metrics "Build Metrics:"
    if [ -d "$BUILD_DIR" ]; then
        local total_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)
        local artifact_count=$(find "$BUILD_DIR" -name "*.tar.gz" | wc -l)
        local doc_count=$(find "$BUILD_DIR" -name "doc*" | wc -l)

        echo "  Build Directory Size: $total_size"
        echo "  Release Artifacts: $artifact_count"
        echo "  Documentation Files: $doc_count"
    fi

    # Git metrics
    echo ""
    print_metrics "Git Metrics:"
    local total_commits=$(git rev-list --count HEAD)
    local tag_count=$(git tag | wc -l)
    local branch_count=$(git branch -a | wc -l)

    echo "  Total Commits: $total_commits"
    echo "  Tags: $tag_count"
    echo "  Branches: $branch_count"

    # Release frequency (if tags exist)
    if [ "$tag_count" -gt 1 ]; then
        echo ""
        print_metrics "Release Frequency:"
        local first_tag=$(git tag | sort -V | head -1)
        local last_tag=$(git tag | sort -V | tail -1)
        local days_between=$(( ( $(date -d $(git log -1 --format=%ci "$last_tag" | cut -d' ' -f1) +%s) - $(date -d $(git log -1 --format=%ci "$first_tag" | cut -d' ' -f1) +%s) ) / 86400 ))
        local releases_per_day=$(echo "scale=2; $tag_count / $days_between" | bc 2>/dev/null || echo "N/A")

        echo "  First Release: $first_tag"
        echo "  Latest Release: $last_tag"
        echo "  Days between first and last: $days_between"
        echo "  Releases per day: $releases_per_day"
    fi
}

# Function to show version history
show_version_history() {
    print_info "Version History"
    echo "==============="

    # Get version history from git tags
    echo ""
    print_metrics "Git Tag History:"
    git tag | grep -E "v[0-9]" | sort -V | while read tag; do
        local tag_date=$(git log -1 --format="%ci" "$tag")
        local tag_author=$(git log -1 --format="%an" "$tag")
        local commit_count=$(git log --oneline "$tag^..$tag" | wc -l)

        echo "  $tag - $tag_date"
        echo "    Author: $tag_author"
        echo "    Commits: $commit_count"

        # Show release notes if available
        if command -v gh >/dev/null 2>&1 && gh release view "$tag" --json body --jq '.body' 2>/dev/null | grep -q .; then
            echo "    Release notes available"
        fi
        echo ""
    done

    # Show current development
    if [ -f "$VERSION_FILE" ]; then
        local current_version=$(cat "$VERSION_FILE")
        print_metrics "Development Status:"
        echo "  Current Version: $current_version"

        # Check if it's a release or development version
        if [[ "$current_version" =~ .*-.* ]]; then
            echo "  Status: Development/Snapshot"
        else
            echo "  Status: Release"
        fi
    fi
}

# Function to list available artifacts
list_artifacts() {
    print_info "Available Artifacts"
    echo "=================="

    if [ ! -d "$BUILD_DIR" ]; then
        print_warning "No build directory found"
        return 0
    fi

    # List all artifacts
    find "$BUILD_DIR" -type f -name "*.tar.gz" -o -name "*.sha256" -o -name "*docs*" | sort | while read file; do
        local file_size=$(du -h "$file" 2>/dev/null | cut -f1)
        local file_date=$(date -r "$file" "+%Y-%m-%d %H:%M")

        echo "  📦 $(basename "$file")"
        echo "     Size: $file_size"
        echo "     Date: $file_date"
        echo ""
    done

    # Show artifact summary
    local total_artifacts=$(find "$BUILD_DIR" -type f \( -name "*.tar.gz" -o -name "*.sha256" \) | wc -l)
    local total_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)

    print_metrics "Summary:"
    echo "  Total Artifacts: $total_artifacts"
    echo "  Total Size: $total_size"
}

# Function to compare two versions
compare_versions() {
    local v1="$1"
    local v2="$2"

    if [ -z "$v1" ] || [ -z "$v2" ]; then
        print_error "Please specify both versions to compare"
        usage
        return 1
    fi

    print_info "Version Comparison: $v1 vs $v2"
    echo "========================="

    # Version comparison
    if [[ "$v1" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && [[ "$v2" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major1="${BASH_REMATCH[1]}"
        local minor1="${BASH_REMATCH[2]}"
        local patch1="${BASH_REMATCH[3]}"
        local major2="${BASH_REMATCH[1]}"
        local minor2="${BASH_REMATCH[2]}"
        local patch2="${BASH_REMATCH[3]}"

        echo ""
        print_metrics "Component Comparison:"
        echo "  Major: $major1 vs $major2"
        echo "  Minor: $minor1 vs $minor2"
        echo "  Patch: $patch1 vs $patch2"

        # Determine which is newer
        if [ "$major1" -gt "$major2" ]; then
            echo ""
            print_success "$v1 is newer than $v2 (Major version difference)"
        elif [ "$major1" -lt "$major2" ]; then
            echo ""
            print_success "$v2 is newer than $v1 (Major version difference)"
        elif [ "$minor1" -gt "$minor2" ]; then
            echo ""
            print_success "$v1 is newer than $v2 (Minor version difference)"
        elif [ "$minor1" -lt "$minor2" ]; then
            echo ""
            print_success "$v2 is newer than $v1 (Minor version difference)"
        elif [ "$patch1" -gt "$patch2" ]; then
            echo ""
            print_success "$v1 is newer than $v2 (Patch version difference)"
        elif [ "$patch1" -lt "$patch2" ]; then
            echo ""
            print_success "$v2 is newer than $v1 (Patch version difference)"
        else
            echo ""
            print_info "$v1 and $v2 are the same version"
        fi
    else
        print_warning "Invalid version format for comparison"
    fi

    # Check if versions exist as tags
    echo ""
    print_metrics "Tag Status:"
    if git tag -l "v$v1" | grep -q "v$v1"; then
        print_success "Tag v$v1 exists"
    else
        print_warning "Tag v$v1 not found"
    fi

    if git tag -l "v$v2" | grep -q "v$v2"; then
        print_success "Tag v$v2 exists"
    else
        print_warning "Tag v$v2 not found"
    fi
}

# Function to show release trends
show_release_trends() {
    print_info "Release Trends"
    echo "==============="

    # Get tag history with dates
    echo ""
    print_metrics "Version Timeline:"
    git tag | grep -E "v[0-9]" | sort -V | while read tag; do
        local tag_date=$(git log -1 --format="%ci" "$tag" | cut -d' ' -f1-2)
        echo "  $tag - $tag_date"
    done

    # Calculate trends
    local tag_count=$(git tag | grep -E "v[0-9]" | wc -l)
    if [ "$tag_count" -gt 1 ]; then
        echo ""
        print_metrics "Trend Analysis:"

        # Time-based analysis
        local first_tag=$(git tag | grep -E "v[0-9]" | sort -V | head -1)
        local last_tag=$(git tag | grep -E "v[0-9]" | sort -V | tail -1)
        local first_date=$(git log -1 --format="%ci" "$first_tag" | cut -d' ' -f1)
        local last_date=$(git log -1 --format="%ci" "$last_tag" | cut -d' ' -f1)

        local days_between=$(( ( $(date -d "$last_date" +%s) - $(date -d "$first_date" +%s) ) / 86400 ))
        local releases_per_month=$(( tag_count * 30 / days_between ))

        echo "  Project span: $days_between days"
        echo "  Average releases per month: $releases_per_month"

        # Version pattern analysis
        echo ""
        print_metrics "Version Pattern:"
        local latest_tag=$(git tag | grep -E "v[0-9]" | sort -V | tail -1)
        local major_changes=$(git tag | grep -E "v[0-9]+\.[0-0]+\.[0-0]" | wc -l)
        local minor_changes=$(git tag | grep -E "v[0-9]+\.[1-9][0-9]*\.[0-9]+" | wc -l)
        local patch_changes=$(git tag | grep -E "v[0-9]+\.[0-9]+\.[1-9][0-9]*" | wc -l)

        echo "  Major releases: $major_changes"
        echo "  Minor releases: $minor_changes"
        echo "  Patch releases: $patch_changes"
    fi
}

# Function to check for alerts
check_alerts() {
    print_info "Release Alerts"
    echo "=============="

    local alert_count=0

    # Check for uncommitted changes
    if ! git diff --quiet && git diff --cached --quiet; then
        ((alert_count++))
        print_error "ALERT: Uncommitted changes in working directory"
    fi

    # Check for multiple development versions
    if git tag | grep -E "v[0-9]+-[a-zA-Z]" | wc -l | grep -q "2"; then
        ((alert_count++))
        print_warning "ALERT: Multiple pre-release versions"
    fi

    # Check for old releases
    if [ -f "$VERSION_FILE" ]; then
        local current_version=$(cat "$VERSION_FILE")
        if [[ "$current_version" =~ .*-.* ]]; then
            print_warning "NOTE: Development version detected: $current_version"
        fi
    fi

    # Check artifact age
    if [ -d "$BUILD_DIR" ]; then
        local oldest_artifact=$(find "$BUILD_DIR" -name "*.tar.gz" -printf '%T@ %p\n' | sort -n | head -1)
        if [ -n "$oldest_artifact" ]; then
            local artifact_age=$(( ( $(date +%s) - ${oldest_artifact%% *} ) / 86400 ))
            if [ "$artifact_age" -gt 30 ]; then
                ((alert_count++))
                print_error "ALERT: Artifacts are $artifact_age days old"
            fi
        fi
    fi

    # Check tag consistency
    local tag_count=$(git tag | wc -l)
    if [ "$tag_count" -eq 0 ]; then
        ((alert_count++))
        print_error "ALERT: No version tags found"
    fi

    # Summary
    echo ""
    if [ "$alert_count" -eq 0 ]; then
        print_success "✓ No alerts - Release system healthy"
    else
        print_metrics "Total Alerts: $alert_count"
        print_warning "Review and address the alerts above"
    fi
}

# Main commands
cmd_status() {
    get_release_status
}

cmd_health() {
    check_release_health
}

cmd_metrics() {
    show_release_metrics
}

cmd_versions() {
    show_version_history
}

cmd_artifacts() {
    list_artifacts
}

cmd_compare() {
    compare_versions "$1" "$2"
}

cmd_trends() {
    show_release_trends
}

cmd_alerts() {
    check_alerts
}

# Main script execution
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    "status")
        cmd_status
        ;;
    "health")
        cmd_health
        ;;
    "metrics")
        cmd_metrics
        ;;
    "versions")
        cmd_versions
        ;;
    "artifacts")
        cmd_artifacts
        ;;
    "compare")
        cmd_compare "$1" "$2"
        ;;
    "trends")
        cmd_trends
        ;;
    "alerts")
        cmd_alerts
        ;;
    "help"|*)
        usage
        ;;
esac