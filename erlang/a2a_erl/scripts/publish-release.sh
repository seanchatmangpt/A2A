#!/bin/bash

# HotCI-style Release Publisher
# Automated GitHub release publishing with artifacts

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

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check gh CLI
    if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI (gh) not found. Please install it from https://github.com/cli/cli"
        exit 1
    fi

    # Check if authenticated
    if ! gh auth status >/dev/null 2>&1; then
        print_error "GitHub CLI not authenticated. Run 'gh auth login'"
        exit 1
    fi

    # Check VERSION file
    if [ ! -f "$VERSION_FILE" ]; then
        print_error "VERSION file not found at $VERSION_FILE"
        exit 1
    fi

    print_success "Prerequisites satisfied"
}

# Function to get release information
get_release_info() {
    local version=$(cat "$VERSION_FILE")
    local timestamp=$(date +%Y%m%d%H%M%S)
    local release_name="a2a-erl-v${version}"
    local git_hash=$(git rev-parse --short HEAD)
    local git_branch=$(git rev-parse --abbrev-ref HEAD)

    echo "$version|$release_name|$timestamp|$git_hash|$git_branch"
}

# Function to generate release notes
generate_release_notes() {
    local version="$1"
    local release_name="$2"
    local git_hash="$3"
    local git_branch="$4"

    print_info "Generating release notes for v$version"

    # Get commit history since last tag
    local last_tag=$(git describe --tags --abbrev=0 HEAD~2 2>/dev/null || echo "")
    local commits=""
    local features=""
    local fixes=""
    local docs=""

    if [ -n "$last_tag" ]; then
        # Get commits since last tag
        while IFS= read -r line; do
            if [[ "$line" =~ feat:[[:space:]](.*) ]]; then
                features="$features- ${BASH_REMATCH[1]}\n"
            elif [[ "$line" =~ fix:[[:space:]](.*) ]]; then
                fixes="$fixes- ${BASH_REMATCH[1]}\n"
            elif [[ "$line" =~ docs:[[:space:]](.*) ]]; then
                docs="$docs- ${BASH_REMATCH[1]}\n"
            else
                commits="$commits- $line\n"
            fi
        done < <(git log --pretty=format:"%s" "$last_tag..HEAD" 2>/dev/null || echo "No commits found")
    else
        # All commits
        commits=$(git log --pretty=format:"- %s" HEAD 2>/dev/null || echo "No commits found")
    fi

    cat << EOF
# A2A Erlang Release $version

## What's Changed

$(if [ -n "$features" ]; then echo "### Features"; echo -e "$features"; fi)
$(if [ -n "$fixes" ]; then echo "### Bug Fixes"; echo -e "$fixes"; fi)
$(if [ -n "$docs" ]; then echo "### Documentation"; echo -e "$docs"; fi)
$(if [ -n "$commits" ]; then echo "### Changes"; echo -e "$commits"; fi)

## Technical Details

- **Version**: $version
- **Git Commit**: $git_hash
- **Branch**: $git_branch
- **Build Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Installation

### Binary Release

Download the tarball:

\`\`\`bash
curl -L -O https://github.com/${GITHUB_REPOSITORY:-$(git remote get-url origin)}/releases/download/v$version/$release_name.tar.gz
sha256sum $release_name.tar.gz
\`\`\`

Extract and run:

\`\`\`bash
tar -xzf $release_name.tar.gz
cd $release_name
./bin/start
\`\`\`

### Docker

Pull the Docker image:

\`\`\`bash
docker pull ghcr.io/${GITHUB_REPOSITORY:-$(git remote get-url origin | sed 's|https://||' | sed 's|/.*||')}:$version
\`\`\`

Run the container:

\`\`\`bash
docker run -p 8080:8080 ghcr.io/${GITHUB_REPOSITORY:-$(git remote get-url origin | sed 's|https://||' | sed 's|/.*||')}:$version
\`\`\`

## Configuration

See the [Configuration Guide](docs/configuration.md) for detailed configuration options.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
EOF
}

# Function to create GitHub release
create_github_release() {
    local version="$1"
    local release_name="$2"
    local is_pre_release="$3"
    local is_draft="$4"

    print_info "Creating GitHub release v$version"

    # Generate release notes
    local release_notes=$(mktemp)
    generate_release_notes "$version" "$release_name" > "$release_notes"

    # Create release
    gh release create \
        "v$version" \
        --title "Release v$version" \
        --notes-file "$release_notes" \
        --prerelease="$is_pre_release" \
        --draft="$is_draft" \
        --target "$(git rev-parse HEAD)" \
        *.tar.gz *.sha256 2>/dev/null || true

    # Clean up
    rm -f "$release_notes"

    print_success "GitHub release created: v$version"
}

# Function to publish to Docker Hub
publish_to_docker() {
    local version="$1"
    local image_name="${GITHUB_REPOSITORY:-$(git remote get-url origin | sed 's|https://||' | sed 's|/.*||')}"

    print_info "Publishing to Docker registry"

    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker not available - skipping Docker publish"
        return 0
    fi

    # Check if already logged in
    if ! docker info >/dev/null 2>&1; then
        print_warning "Not logged into Docker registry - skipping Docker publish"
        return 0
    fi

    # Build and push
    docker build -t "ghcr.io/$image_name:$version" .
    docker push "ghcr.io/$image_name:$version"

    # Push latest tag for non-prerelease versions
    if [[ "$version" != *"-"* ]]; then
        docker tag "ghcr.io/$image_name:$version" "ghcr.io/$image_name:latest"
        docker push "ghcr.io/$image_name:latest"
    fi

    print_success "Published to Docker registry: ghcr.io/$image_name:$version"
}

# Function to notify about release
notify_release() {
    local version="$1"
    local release_name="$2"
    local is_pre_release="$3"

    print_info "Sending release notifications"

    # Slack notification (if webhook configured)
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🎉 A2A Erlang v$version released! $(if [ "$is_pre_release" = "true" ]; then echo '(Pre-release)'; fi)\n\nRelease: https://github.com/${GITHUB_REPOSITORY:-$(git remote get-url origin)}/releases/tag/v$version\nDocker: ghcr.io/${GITHUB_REPOSITORY:-$(git remote get-url origin | sed 's|https://||' | sed 's|/.*||')}:$version\"}" \
            "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
    fi

    # Email notification (if configured)
    if [ "${EMAIL_NOTIFICATION:-false}" = "true" ] && [ -n "${EMAIL_TO:-}" ]; then
        echo "A2A Erlang v$version has been released." | mail -s "A2A Erlang v$version Released" "$EMAIL_TO" || true
    fi

    print_success "Notifications sent"
}

# Function to verify release
verify_release() {
    local version="$1"
    local release_name="$2"

    print_info "Verifying release v$version"

    # Check if release exists on GitHub
    if ! gh release view "v$version" >/dev/null 2>&1; then
        print_error "GitHub release not found: v$version"
        return 1
    fi

    # Check if artifacts are attached
    local artifacts=$(gh release view "v$version" --json assets --jq '.assets | length' 2>/dev/null || echo 0)
    if [ "$artifacts" -eq 0 ]; then
        print_warning "No artifacts attached to release"
    else
        print_success "Release verified with $artifacts artifacts"
    fi
}

# Main functions
usage() {
    echo "HotCI-style Release Publisher"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  publish             Create GitHub release with artifacts"
    echo "  publish-docker      Publish to Docker registry"
    echo "  notify             Send release notifications"
    echo "  verify <version>    Verify release exists"
    echo "  help               Show this help"
    echo ""
    echo "Options:"
    echo "  --pre-release       Create pre-release"
    echo "  --draft             Create draft release"
    echo ""
    echo "Examples:"
    echo "  $0 publish"
    echo "  $0 publish --pre-release"
    echo "  $0 verify 1.2.3"
}

cmd_publish() {
    check_prerequisites

    # Parse arguments
    local is_pre_release=false
    local is_draft=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --pre-release)
                is_pre_release=true
                shift
                ;;
            --draft)
                is_draft=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    # Get release information
    IFS='|' read -r version release_name timestamp git_hash git_branch <<< "$(get_release_info)"

    print_info "Publishing release: $release_name"
    print_info "Version: $version"
    print_info "Pre-release: $is_pre_release"
    print_info "Draft: $is_draft"

    # Create GitHub release
    create_github_release "$version" "$release_name" "$is_pre_release" "$is_draft"

    # Publish to Docker
    publish_to_docker "$version"

    # Notify
    notify_release "$version" "$release_name" "$is_pre_release"

    print_success "Release publishing completed!"
}

cmd_publish_docker() {
    check_prerequisites

    # Get version
    local version=$(cat "$VERSION_FILE")
    local image_name="${GITHUB_REPOSITORY:-$(git remote get-url origin | sed 's|https://||' | sed 's|/.*||')}"

    print_info "Publishing Docker image: $version"

    # Build and push
    publish_to_docker "$version"

    print_success "Docker publishing completed!"
}

cmd_notify() {
    check_prerequisites

    # Get release information
    IFS='|' read -r version release_name timestamp git_hash git_branch <<< "$(get_release_info)"

    print_info "Notifying about release: $release_name"

    # Get pre-release status from GitHub
    local is_pre_release=$(gh release view "v$version" --json isPrerelease --jq '.isPrerelease' 2>/dev/null || echo "false")

    notify_release "$version" "$release_name" "$is_pre_release"

    print_success "Notifications completed!"
}

cmd_verify() {
    local version="$1"

    if [ -z "$version" ]; then
        print_error "Please specify version to verify"
        usage
        exit 1
    fi

    local release_name="a2a-erl-v$version"

    print_info "Verifying release: $release_name"

    verify_release "$version" "$release_name"

    print_success "Verification completed!"
}

# Main script execution
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    "publish")
        cmd_publish "$@"
        ;;
    "publish-docker")
        cmd_publish_docker
        ;;
    "notify")
        cmd_notify
        ;;
    "verify")
        cmd_verify "$1"
        ;;
    "help"|*)
        usage
        ;;
esac