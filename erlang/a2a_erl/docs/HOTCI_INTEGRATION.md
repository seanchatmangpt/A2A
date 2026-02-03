# HotCI Integration for A2A Erlang/OTP

This document describes the integration of [HotCI](https://github.com/Ahzed11/HotCI) into the A2A Erlang/OTP implementation for automated hot code upgrade testing.

## Overview

HotCI provides a CI/CD framework for testing hot code upgrades and downgrades in Erlang/OTP systems. It uses:

- **GitHub Actions** for CI/CD automation
- **Docker** with the **peer** module for isolated upgrade testing
- **Common Test** for upgrade/downgrade validation
- **rebar3_appup_plugin** for automatic appup generation

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Actions CI/CD                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │  erlang-ci   │    │   relup-ci   │    │  publish-*   │      │
│  │              │    │              │    │              │      │
│  │  • xref      │    │  • build     │    │  • test      │      │
│  │  • dialyzer  │    │  • upgrade   │    │  • annotate  │      │
│  │  • release   │    │  • downgrade │    │              │      │
│  │  • unit test │    │  • validate  │    │              │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Docker + peer Module                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              a2a_erl Docker Container                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │   Old VSN   │  │   New VSN   │  │   Upgrade   │     │   │
│  │  │  (0.1.0)    │──│  (0.2.0)    │──│   Testing   │     │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Common Test Suites                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  upgrade_downgrade_SUITE.erl:                                    │
│    • before_upgrade_case  - Verify pre-upgrade state            │
│    • upgrade_case         - Execute hot code upgrade             │
│    • after_upgrade_case   - Validate post-upgrade state         │
│    • before_downgrade_case- Prepare for downgrade               │
│    • downgrade_case       - Execute hot code downgrade           │
│    • after_downgrade_case - Validate post-downgrade state       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
erlang/a2a_erl/
├── .github/
│   ├── workflows/
│   │   ├── erlang-ci.yml      # Unit tests and validation
│   │   ├── relup-ci.yml       # Upgrade/downgrade tests
│   │   └── publish-tarball.yml # Release publishing
│   └── actions/
│       ├── setup-beam/        # Erlang/OTP setup action
│       └── publish-ct-results/ # Test result publishing
├── scripts/
│   ├── check_versions         # Version validation for relup
│   └── get_release_name       # Extract release name from config
├── test/
│   └── upgrade_downgrade_SUITE.erl  # Hot upgrade test suite
└── rebar.config               # HotCI plugin configuration
```

## Configuration

### rebar.config

The `rebar.config` includes HotCI-specific settings:

```erlang
%% HotCI: appup plugin for automatic appup generation
{plugins, [
    {rebar3_appup_plugin,
        {git, "https://github.com/lrascao/rebar3_appup_plugin", {branch, "develop"}}}
]}.

%% HotCI: Export test results as XML
{ct_opts, [{ct_hooks, [cth_surefire]}]}.

%% HotCI: Profile for upgrade testing
{profiles, [
    {hotci, [
        {erl_opts, [nowarn_export_all, debug_info]},
        {deps, [{cth_surefire, "1.2.0"}]}
    ]}
]}.
```

## Workflows

### erlang-ci.yml

Runs on every push and pull request to `main`:

1. **validation-checks**: xref and dialyzer
2. **build**: Creates release tarball
3. **unit-test**: Runs Common Test suites with coverage

### relup-ci.yml

Runs on pull requests when a previous tag exists:

1. Checks out previous version and builds release
2. Builds current version release
3. Validates appup and relup generation
4. Runs upgrade/downgrade tests in Docker

## Running Tests Locally

### Prerequisites

- Docker (for peer module testing)
- Erlang/OTP 28+
- rebar3

### Run Unit Tests

```bash
cd erlang/a2a_erl
rebar3 ct
```

### Run Upgrade/Downgrade Tests

First, create two releases with different versions:

```bash
# Build old version
git checkout v0.1.0
rebar3 release
rebar3 tar

# Build new version
git checkout main
# Bump version in rebar.config
rebar3 release
rebar3 tar

# Run upgrade tests
mkdir -p test/releases
cp _build/default/rel/a2a_erl/a2a_erl-*.tar.gz test/releases/

# Create test config
cat > test/config.config << 'EOF'
{old_version, "0.1.0"}.
{new_version, "0.2.0"}.
{release_name, "a2a_erl"}.
{release_dir, "/path/to/test/releases"}.
EOF

rebar3 ct --dir ./test --config ./test/config.config
```

## Version Bumping Strategy

HotCI uses semantic versioning for Erlang releases:

```
RESTART.RELUP.RELOAD

- RESTART: Bump for ERTS version changes
- RELUP: Bump for incompatible changes requiring full restart
- RELOAD: Bump for compatible hot code reload changes
```

Example progression:
- `0.1.0` → `0.1.1` (hot code fix)
- `0.1.1` → `0.2.0` (appup required)
- `0.2.0` → `1.0.0` (ERTS upgrade)

## Troubleshooting

### "appup missing" Error

Cause: No appup file was generated.

Solution:
```bash
# Manually generate appup
rebar3 appup generate

# Or check for missing .appup.src files
find src -name "*.appup.src"
```

### "relup missing" Error

Cause: relup was not created during release build.

Solution: Ensure version has been bumped and two releases exist.

### Docker Build Fails

Cause: Docker not available or incorrect image reference.

Solution:
```bash
# Verify Docker
docker --version
docker ps

# Check Dockerfile in test directory
cat test/Dockerfile
```

### Peer Module Connection Issues

Cause: EPMD port or distribution configuration mismatch.

Solution: Verify cookie and port settings match between nodes.

## CI/CD Pipeline Status

| Status | Description |
|--------|-------------|
| ✅ Passing | All tests passed, release ready |
| ⚠️ Skipped | No previous version tag found |
| ❌ Failed | Upgrade/downgrade test failed |

## Contributing

When adding new features:

1. Update version in `rebar.config`
2. Create corresponding `.appup.src` file if needed
3. Add test cases to upgrade_downgrade_SUITE.erl
4. Ensure CI passes before merging

## References

- [HotCI GitHub](https://github.com/Ahzed11/HotCI)
- [Erlang Release Handling](https://www.erlang.org/doc/design_principles/release_handling.html)
- [peer Module](https://www.erlang.org/doc/man/peer.html)
- [rebar3_appup_plugin](https://github.com/lrascao/rebar3_appup_plugin)
