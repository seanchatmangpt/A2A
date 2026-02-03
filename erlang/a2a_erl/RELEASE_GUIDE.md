# A2A Erlang Release Management Guide

This guide covers HotCI-style release management for the A2A Erlang project, including versioning, building, and publishing releases.

## Table of Contents

- [Release Workflow](#release-workflow)
- [Version Management](#version-management)
- [Building Releases](#building-releases)
- [Publishing Releases](#publishing-releases)
- [Automation](#automation)
- [Troubleshooting](#troubleshooting)

## Release Workflow

### CI/CD Pipeline

The release management system is integrated into GitHub Actions with the following workflow:

1. **Validate Release Conditions** - Checks if this is a tag release, snapshot, or manual trigger
2. **Compile and Build** - Compiles the Erlang application
3. **Run Tests** - Executes Common Test, Proper, and other quality checks
4. **Build Release** - Creates the production release package
5. **Build Docker Images** - Builds and pushes Docker images
6. **Publish Release** - Creates GitHub releases with artifacts
7. **Notification** - Sends release notifications

### Trigger Types

- **Push to main branch** - Creates snapshot releases
- **Git tags (v*)** - Creates official releases
- **Manual workflow dispatch** - Allows choosing release type

## Version Management

### Smoothver Versioning

The project uses Smoothver versioning scheme that extends SemVer with build metadata:

```
MAJOR.MINOR.PATCH[-PRERELEASE[.BUILD]]
```

Examples:
- `1.0.0` - Official release
- `1.0.1-alpha.1` - Pre-release with alpha version
- `1.0.2-beta.5` - Pre-release with beta version
- `1.1.0-snapshot.20231201` - Snapshot with build timestamp

### Version Bumping

Use the version manager to bump versions:

```bash
# Current version: 1.0.0
./scripts/version-manager.sh bump major      # 2.0.0
./scripts/version-manager.sh bump minor      # 1.1.0
./scripts/version-manager.sh bump patch      # 1.0.1
./scripts/version-manager.sh bump prerelease # 1.0.1-alpha.1
./scripts/version-manager.sh bump metadata   # 1.0.1-alpha.1.1234567890
./scripts/version-manager.sh bump snapshot   # 1.0.1-snapshot.20231201
```

### Quick Version Bumping

For common version bumping scenarios:

```bash
# Bump patch version and commit
make bump-version TYPE=patch

# Bump minor version with custom message
make bump-version TYPE=minor "feat: Add new authentication feature"
```

## Building Releases

### Manual Release Build

```bash
# Build release with all artifacts
make build

# Run tests first
make test
make build

# Create release package only
make package

# Build Docker image only
make docker
```

### Release Manager Script

The release manager provides comprehensive release building:

```bash
./scripts/release-manager.sh build    # Complete build process
./scripts/release-manager.sh test     # Run all tests and checks
./scripts/release-manager.sh clean    # Clean build artifacts
```

### Build Artifacts

Each build generates the following artifacts:

```
_build/
├── a2a-erl-v<version>-<timestamp>.tar.gz  # Main release package
├── a2a-erl-v<version>-<timestamp>.sha256  # SHA256 checksum
├── docs.tar.gz                            # Documentation archive
├── artifacts.txt                          # Artifact list
└── RELEASE_NOTES.md                       # Release notes
```

## Publishing Releases

### GitHub Release Publishing

Create a GitHub release with all artifacts:

```bash
# Build and publish release
make release

# Manual publishing using the script
./scripts/publish-release.sh

# Publish as pre-release
./scripts/publish-release.sh --pre-release

# Publish as draft
./scripts/publish-release.sh --draft
```

### Docker Registry Publishing

Docker images are automatically built and pushed to GitHub Container Registry:

```bash
# Build and push Docker image
make docker

# Manual Docker publishing
./scripts/publish-release.sh publish-docker
```

### Release Automation

For automatic releases, you can use GitHub Actions:

1. **Tag-based releases**: Push a version tag to trigger release
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **Manual releases**: Use GitHub Actions workflow dispatch
   - Go to Actions tab
   - Select "Release Management"
   - Choose release type and trigger

## Automation

### GitHub Actions Workflows

- **CI Workflow** (`ci.yml`): Continuous integration and quality checks
- **Release Workflow** (`release-workflow.yml`): Automated release management

### Environment Configuration

Copy the environment template and customize:

```bash
cp .env.example .env
# Edit .env with your configuration
```

Key environment variables:

```bash
# GitHub
GITHUB_TOKEN=your-token
GITHUB_REPOSITORY=your-username/a2a-erl

# Docker Registry
REGISTRY=ghcr.io
DOCKER_USERNAME=your-username
DOCKER_PASSWORD=your-token

# Release settings
PRE_RELEASE=false
DRAFT_RELEASE=false
```

### Release Notifications

Configure notifications in `.env`:

```bash
# Slack notifications
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...

# Email notifications
EMAIL_NOTIFICATION=true
EMAIL_TO=your-email@example.com
```

## Troubleshooting

### Common Issues

#### Version File Not Found

```bash
# Initialize version file
echo "0.1.0" > VERSION
git add VERSION
git commit -m "chore: Initialize version"
```

#### GitHub CLI Not Authenticated

```bash
# Authenticate with GitHub
gh auth login
```

#### Docker Build Failures

```bash
# Check Docker daemon
docker info

# Rebuild dependencies
make clean
make build
```

#### Release Creation Fails

```bash
# Check git status
git status

# Ensure clean working directory
git add .
git commit -m "Release preparation"

# Try release creation again
make release
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Enable bash debug mode
bash -x ./scripts/release-manager.sh build

# Enable GitHub Actions debug
# Add steps to workflow with:
#   - name: Debug
#     run: echo "Debug information..."
```

### Rollback

If a release fails, you can rollback:

```bash
# Remove failed tag
git tag -d v1.0.0

# Reset commit if needed
git reset --hard HEAD~1

# Cleanup artifacts
make clean-all
```

## Best Practices

### Versioning

- Use semantic versioning for official releases
- Include pre-release identifiers for unstable builds
- Use snapshots for development builds
- Keep version numbers consistent across all files

### Quality Assurance

- Always run tests before releasing
- Use dialyzer for type safety
- Check code coverage (minimum 80%)
- Review changes before committing

### Release Process

1. Test thoroughly in development
2. Bump appropriate version type
3. Update changelog
4. Build and test release
5. Create GitHub release
6. Monitor deployment
7. Collect feedback

### Security

- Never commit secrets or credentials
- Use GitHub secrets for sensitive data
- Regularly update dependencies
- Scan for vulnerabilities

## Support

For issues or questions:
- Check the troubleshooting section
- Review GitHub Actions logs
- Create an issue in the repository
- Contact the development team

---

*This guide is part of the HotCI-style release management system for A2A Erlang.*