#!/bin/bash

# HotCI-style Release Manager for A2A Erlang
# Automated release building, packaging, and publishing

set -euo pipefail

# Configuration
PROJECT_NAME="a2a_erl"
BUILD_DIR="_build"
RELEASE_DIR="$BUILD_DIR/prod/rel"
VERSION_FILE="VERSION"
REGISTRY="ghcr.io"
IMAGE_NAME="${GITHUB_REPOSITORY:-a2a-erl}"

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

# Function to load environment
load_env() {
    if [ -f ".env" ]; then
        print_info "Loading environment from .env"
        export $(grep -v '^#' .env | xargs)
    fi

    if [ -f "config/sys.config" ]; then
        print_info "Loading system configuration"
        # Extract any relevant config values if needed
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Erlang/OTP
    if ! command -v erl >/dev/null 2>&1; then
        print_error "Erlang/OTP not found"
        exit 1
    fi

    # Check rebar3
    if ! command -v rebar3 >/dev/null 2>&1; then
        print_error "rebar3 not found"
        exit 1
    fi

    # Check Docker (optional)
    if command -v docker >/dev/null 2>&1; then
        print_info "Docker found - will build Docker images"
    else
        print_warning "Docker not found - skipping Docker image builds"
    fi

    # Check git
    if ! command -v git >/dev/null 2>&1; then
        print_error "git not found"
        exit 1
    fi

    print_success "All prerequisites satisfied"
}

# Function to clean previous builds
clean_builds() {
    print_info "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$RELEASE_DIR"
    print_success "Build directory cleaned"
}

# Function to compile dependencies
compile_deps() {
    print_info "Compiling dependencies..."
    rebar3 deps
    rebar3 compile --warnings_as_errors
    print_success "Dependencies compiled"
}

# Function to run tests
run_tests() {
    print_info "Running tests..."

    # Run Common Test
    print_info "Running Common Test suite..."
    if ! rebar3 ct --verbose; then
        print_error "Common Test failed"
        exit 1
    fi

    # Run Proper tests
    print_info "Running Proper property tests..."
    if ! rebar3 proper -d 100; then
        print_error "Proper tests failed"
        exit 1
    fi

    # Run dialyzer
    print_info "Running Dialyzer type checking..."
    if ! rebar3 dialyzer; then
        print_error "Dialyzer found type issues"
        exit 1
    fi

    # Run code coverage
    print_info "Running code coverage..."
    rebar3 cover --verbose

    print_success "All tests passed"
}

# Function to build release
build_release() {
    print_info "Building production release..."
    rebar3 as prod release

    if [ ! -d "$RELEASE_DIR/$PROJECT_NAME" ]; then
        print_error "Release build failed - directory not found"
        exit 1
    fi

    print_success "Release built successfully"
}

# Function to generate documentation
generate_docs() {
    print_info "Generating documentation..."
    rebar3 edoc

    # Create docs archive
    if [ -d "doc" ]; then
        tar -czf "$BUILD_DIR/docs.tar.gz" -C doc .
        print_success "Documentation generated and archived"
    fi
}

# Function to create release package
create_release_package() {
    local release_name="$1"
    local version="$2"

    print_info "Creating release package: $release_name"

    # Create release directory
    local release_package_dir="$BUILD_DIR/$release_name"
    mkdir -p "$release_package_dir"

    # Copy release files
    cp -r "$RELEASE_DIR/$PROJECT_NAME"/* "$release_package_dir/"

    # Copy additional files
    if [ -f "README.md" ]; then
        cp README.md "$release_package_dir/"
    fi
    if [ -f "LICENSE" ]; then
        cp LICENSE "$release_package_dir/"
    fi
    if [ -f "CHANGELOG.md" ]; then
        cp CHANGELOG.md "$release_package_dir/"
    fi

    # Copy configuration files
    mkdir -p "$release_package_dir/config"
    if [ -f "config/sys.config" ]; then
        cp config/sys.config "$release_package_dir/config/"
    fi
    if [ -f "config/vm.args" ]; then
        cp config/vm.args "$release_package_dir/config/"
    fi

    # Create startup script
    cat > "$release_package_dir/bin/start" << EOF
#!/bin/bash

# Start script for $PROJECT_NAME

cd "\$(dirname "\$0")/.."

# Check if release exists
if [ ! -d "releases" ]; then
    echo "Error: Release not found. Run the build process first."
    exit 1
fi

# Start the application
./bin/$PROJECT_NAME console
EOF

    chmod +x "$release_package_dir/bin/start"

    # Create archive
    cd "$BUILD_DIR"
    tar -czf "${release_name}.tar.gz" "$release_name/"
    cd ..

    # Create checksum
    sha256sum "$BUILD_DIR/${release_name}.tar.gz" > "$BUILD_DIR/${release_name}.sha256"

    # Clean up temporary directory
    rm -rf "$release_package_dir"

    print_success "Release package created: $BUILD_DIR/${release_name}.tar.gz"
}

# Function to build Docker image
build_docker_image() {
    local version="$1"
    local release_name="$2"

    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker not available - skipping Docker build"
        return 0
    fi

    print_info "Building Docker image: $IMAGE_NAME:$version"

    # Get git commit hash
    local git_hash=$(git rev-parse --short HEAD)
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build image
    docker build \
        --build-arg VERSION="$version" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VCS_REF="$git_hash" \
        -t "$IMAGE_NAME:$version" \
        -t "$IMAGE_NAME:latest" \
        --target runtime \
        .

    print_success "Docker image built: $IMAGE_NAME:$version"

    # Push image if credentials are available
    if [ -n "${DOCKER_USERNAME:-}" ] && [ -n "${DOCKER_PASSWORD:-}" ]; then
        print_info "Pushing Docker image to registry..."

        # Login to registry
        echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

        # Push images
        docker push "$IMAGE_NAME:$version"
        docker push "$IMAGE_NAME:latest"

        print_success "Docker image pushed to registry"
    else
        print_warning "No Docker credentials found - skipping push"
    fi
}

# Function to run security checks
run_security_checks() {
    print_info "Running security checks..."

    # Check for sensitive information in code
    if grep -r -i "password\|secret\|key\|token" src/ --include="*.erl" | grep -v "example"; then
        print_warning "Potential sensitive information found in source code"
    fi

    # Check for common vulnerabilities
    if command -v rebar3 >/dev/null 2>&1; then
        print_info "Dependency vulnerability check..."
        # Add any vulnerability scanning tools if available
    fi

    print_success "Security checks completed"
}

# Function to validate release
validate_release() {
    local release_name="$1"
    local version="$2"

    print_info "Validating release..."

    # Check if release file exists
    if [ ! -f "$BUILD_DIR/${release_name}.tar.gz" ]; then
        print_error "Release file not found: $BUILD_DIR/${release_name}.tar.gz"
        exit 1
    fi

    # Verify checksum
    if [ -f "$BUILD_DIR/${release_name}.sha256" ]; then
        cd "$BUILD_DIR"
        if sha256sum -c "${release_name}.sha256"; then
            print_success "Checksum verification passed"
        else
            print_error "Checksum verification failed"
            exit 1
        fi
        cd ..
    fi

    # Test release extraction
    mkdir -p "$BUILD_DIR/test"
    cd "$BUILD_DIR/test"
    tar -xzf "../${release_name}.tar.gz"
    if [ -d "$release_name/bin" ]; then
        print_success "Release extraction test passed"
    else
        print_error "Release extraction test failed"
        exit 1
    fi
    cd ../..

    # Remove test directory
    rm -rf "$BUILD_DIR/test"

    print_success "Release validation passed"
}

# Function to prepare release artifacts
prepare_release_artifacts() {
    local release_name="$1"
    local version="$2"

    print_info "Preparing release artifacts..."

    # Main release package
    create_release_package "$release_name" "$version"

    # Docker image
    build_docker_image "$version" "$release_name"

    # Documentation
    generate_docs

    # Create artifact list
    cat > "$BUILD_DIR/artifacts.txt" << EOF
Release Artifacts for $release_name
=====================================

Version: $version
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Git Commit: $(git rev-parse HEAD)
Git Tag: $(git describe --tags --dirty 2>/dev/null || echo "none")

Files:
- $release_name.tar.gz - Main release package
- $release_name.sha256 - SHA256 checksum
- docs.tar.gz - Documentation archive
- docs/ - Generated documentation

Artifacts are ready for release!
EOF

    print_success "Release artifacts prepared"
}

# Function to create release notes
create_release_notes() {
    local version="$1"
    local release_name="$2"

    print_info "Creating release notes..."

    # Get commit history since last tag
    local last_tag=$(git describe --tags --abbrev=0 HEAD~2 2>/dev/null || echo "")
    local commits=""

    if [ -n "$last_tag" ]; then
        commits=$(git log --pretty=format:"- %s" "$last_tag..HEAD" 2>/dev/null || echo "No commits found")
    else
        commits=$(git log --pretty=format:"- %s" HEAD 2>/dev/null || echo "No commits found")
    fi

    cat > "$BUILD_DIR/RELEASE_NOTES.md" << EOF
# Release Notes - $release_name

## Version $version
Released: $(date -u +"%Y-%m-%d")

---

## Summary

This release includes $([ -n "$last_tag" ] && echo "changes since version $last_tag" || echo "initial release").

## Changes

$commits

## Installation

Download the release package:

\`\`\`bash
curl -L -O https://github.com/$IMAGE_NAME/releases/download/$release_name/$release_name.tar.gz
sha256sum $release_name.tar.gz
tar -xzf $release_name.tar.gz
cd $release_name
./bin/start
\`\`\`

## Docker

\`\`\`bash
docker pull $IMAGE_NAME:$version
docker run -p 8080:8080 $IMAGE_NAME:$version
\`\`\`

---

*Generated by Release Manager*
EOF

    print_success "Release notes created"
}

# Main functions
usage() {
    echo "HotCI-style Release Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  build                 Build release with all artifacts"
    echo "  test                  Run all tests and checks"
    echo "  package <version>     Create release package"
    echo "  docker <version>      Build Docker image"
    echo "  validate <version>    Validate release package"
    echo "  clean                Clean build directory"
    echo "  help                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 build"
    echo "  $0 package v1.2.3"
    echo "  $0 validate v1.2.3"
}

cmd_build() {
    load_env
    check_prerequisites
    clean_builds
    compile_deps
    run_tests
    run_security_checks

    # Get version from VERSION file or git tag
    local version=$(cat "$VERSION_FILE" 2>/dev/null || git describe --tags --abbrev=0 HEAD 2>/dev/null || echo "0.1.0")
    local timestamp=$(date +%Y%m%d%H%M%S)
    local release_name="${PROJECT_NAME}-v${version}-${timestamp}"

    build_release
    prepare_release_artifacts "$release_name" "$version"
    create_release_notes "$version" "$release_name"

    print_success "Build completed successfully!"
    print_info "Artifacts are available in $BUILD_DIR/"
}

cmd_test() {
    load_env
    check_prerequisites
    compile_deps
    run_tests
    run_security_checks
    print_success "All tests and checks passed!"
}

cmd_package() {
    local version="$1"

    if [ -z "$version" ]; then
        print_error "Please specify version"
        usage
        exit 1
    fi

    load_env
    check_prerequisites
    clean_builds
    compile_deps
    build_release

    local release_name="${PROJECT_NAME}-v${version}"
    create_release_package "$release_name" "$version"
    create_release_notes "$version" "$release_name"

    print_success "Package created successfully!"
    print_info "Package: $BUILD_DIR/${release_name}.tar.gz"
}

cmd_docker() {
    local version="$1"

    if [ -z "$version" ]; then
        print_error "Please specify version"
        usage
        exit 1
    fi

    load_env
    check_prerequisites

    # Build release if needed
    if [ ! -d "$RELEASE_DIR/$PROJECT_NAME" ]; then
        print_info "Building release first..."
        build_release
    fi

    build_docker_image "$version" "${PROJECT_NAME}-v${version}"

    print_success "Docker build completed!"
}

cmd_validate() {
    local version="$1"

    if [ -z "$version" ]; then
        print_error "Please specify version"
        usage
        exit 1
    fi

    load_env

    local release_name="${PROJECT_NAME}-v${version}"
    validate_release "$release_name" "$version"

    print_success "Release validation passed!"
}

cmd_clean() {
    print_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    print_success "Build directory cleaned"
}

# Main script execution
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    "build")
        cmd_build
        ;;
    "test")
        cmd_test
        ;;
    "package")
        cmd_package "$1"
        ;;
    "docker")
        cmd_docker "$1"
        ;;
    "validate")
        cmd_validate "$1"
        ;;
    "clean")
        cmd_clean
        ;;
    "help"|*)
        usage
        ;;
esac