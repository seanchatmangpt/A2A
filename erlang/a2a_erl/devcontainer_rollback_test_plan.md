# DevContainer Rollback Compatibility Test Plan

## Current State Analysis
- Application Version: 0.2.0 (a2a_erl.app.src)
- VERSION file: 0.1.0 (inconsistency detected)
- DevContainer Features:
  - Erlang OTP 28 (Alpine Linux)
  - VSCode Extensions (erlang-ls, erlang-formatter, etc.)
  - Common utils feature (ghcr.io/devcontainers/features/common-utils:2)
  - Port forwarding: 8080 (HTTP), 4369 (EPMD)
  - Post-create command: rebar3 compile

## Test Scenarios

### Scenario 1: Build and Test with 0.2.0
1. Build DevContainer with current configuration
2. Test VSCode extensions
3. Verify port forwarding
4. Test rebar3 compilation
5. Verify all services running

### Scenario 2: Downgrade to 0.1.0
1. Update VERSION file to 0.1.0
2. Update a2a_erl.app.src vsn to 0.1.0
3. Rebuild application
4. Rebuild DevContainer
5. Test backwards compatibility

### Scenario 3: Verify Post-Downgrade Features
1. Test VSCode extensions still work
2. Verify port forwarding functionality
3. Test rebar3 compilation
4. Check for any compatibility issues

## Issues Found:
1. Version inconsistency between VERSION file (0.1.0) and .app.src (0.2.0)
2. Need to test if DevContainer features persist after downgrade
3. Need to verify OTP version compatibility (28 vs 27)
