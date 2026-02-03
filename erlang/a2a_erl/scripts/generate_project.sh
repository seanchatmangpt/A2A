#!/bin/bash

# A2A HotCI Project Generator
# Enhanced rebar3 canonical project generator with HotCI capabilities
# Based on rebar3's release, umbrella, and app generators

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PROJECT_ROOT/templates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage
usage() {
    cat << EOF
A2A HotCI Project Generator - Enhanced rebar3 canonical generator

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    generate release <name>          Generate a canonical release project
    generate umbrella <name>         Generate an umbrella project
    generate app <name>              Generate an application
    generate hotci <name>           Generate HotCI-enabled project
    enhance <project>               Enhance existing project with HotCI
    list-templates                 List available templates
    validate <project>             Validate project structure

OPTIONS:
    --version <version>           Project version (default: 0.1.0)
    --otp <version>               Minimum OTP version (default: 28)
    --apps <apps>                Comma-separated app list for umbrellas
    --deps <deps>               Comma-separated dependency list
    --no-hotci                  Disable HotCI features
    --force                     Force overwrite existing files
    --template <path>           Use custom template
    --output <dir>              Output directory (default: current)

GLOBAL OPTIONS:
    --help                      Show this help message
    --verbose                   Verbose output
    --dry-run                   Show what would be done

EXAMPLES:
    $0 generate release myapi
    $0 generate umbrella myapp --apps core,web,auth
    $0 generate app myservice --deps cowboy,jsx
    $0 enhance ./existing-project
    $0 generate hotci myproject --version 1.0.0

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v rebar3 &> /dev/null; then
        missing_deps+=("rebar3")
    fi

    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Get current version from rebar.config
get_current_version() {
    local project_dir="$1"
    local config_file="$project_dir/rebar.config"

    if [ -f "$config_file" ]; then
        grep -o '{vsn, "[^"]*"}' "$config_file" | sed 's/{vsn, "\([^"]*\)"}/\1/' | head -1
    fi
}

# Bump version
bump_version() {
    local current_version="$1"
    local part="$2"

    if [ -z "$current_version" ]; then
        echo "0.1.0"
        return
    fi

    local major minor patch prerelease build metadata

    # Parse version
    if [[ $current_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[^+]*)?(\\+[^]*)?$ ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
        patch=${BASH_REMATCH[3]}
        prerelease=${BASH_REMATCH[4]}
        build=${BASH_REMATCH[5]}

        case "$part" in
            major)
                major=$((major + 1))
                minor=0
                patch=0
                prerelease=""
                build=""
                ;;
            minor)
                minor=$((minor + 1))
                patch=0
                prerelease=""
                build=""
                ;;
            patch)
                patch=$((patch + 1))
                prerelease=""
                build=""
                ;;
            prerelease)
                # Generate new prerelease
                local new_prerelease
                if [[ $prerelease =~ -alpha\.([0-9]+) ]]; then
                    local num=${BASH_REMATCH[1]}
                    new_prerelease="-alpha.$((num + 1))"
                elif [[ $prerelease =~ -beta\.([0-9]+) ]]; then
                    local num=${BASH_REMATCH[1]}
                    new_prerelease="-beta.$((num + 1))"
                else
                    new_prerelease="-alpha.1"
                fi
                prerelease="$new_prerelease"
                ;;
            *)
                log_error "Unknown version part: $part"
                return 1
                ;;
        esac

        echo "${major}.${minor}.${patch}${prerelease}${build}"
    else
        log_error "Invalid version format: $current_version"
        return 1
    fi
}

# Generate release project
generate_release() {
    local name="$1"
    local version="${2:-0.1.0}"
    local otp_version="${3:-28}"
    local hotci_enabled=true
    local force=false
    local output_dir="."

    # Parse additional options
    shift 3
    while [ $# -gt 0 ]; do
        case $1 in
            --no-hotci) hotci_enabled=false ;;
            --force) force=true ;;
            --output) output_dir="$2"; shift ;;
        esac
        shift
    done

    local project_dir="$output_dir/$name"

    if [ -d "$project_dir" ] && [ "$force" = false ]; then
        log_error "Directory $project_dir already exists. Use --force to overwrite."
        exit 1
    fi

    log_info "Generating canonical release project: $name"

    # Create directory structure
    mkdir -p "$project_dir/src"
    mkdir -p "$project_dir/test"
    mkdir -p "$project_dir/config"
    mkdir -p "$project_dir/scripts"
    mkdir -p "$project_dir/docs"
    mkdir -p "$project_dir/rel"

    # HotCI directories
    if [ "$hotci_enabled" = true ]; then
        mkdir -p "$project_dir/hotci/src"
        mkdir -p "$project_dir/hotci/tests"
        mkdir -p "$project_dir/hotci/config"
    fi

    # Generate rebar.config
    cat > "$project_dir/rebar.config" << EOF
%% -*- mode: erlang; -*-
%% A2A Release Project - rebar3 configuration
%% Generated by A2A HotCI Project Generator
{minimum_otp_vsn, "$otp_version"}.

{erl_opts, [
    debug_info,
    warnings_as_errors,
    warn_export_vars,
    warn_unused_import,
    warn_shadow_vars,
    {i, "include"}
]}.

{deps, []}.

%% Shell configuration for development
{shell, [
    {apps, [$name]},
    {config, "config/sys.config"}
]}.

%% Release configuration with HotCI enhancements
{relx, [
    {release, {$name, "$version"}, [
        sasl,
        inets,
        crypto,
        $name
    ]},
    {dev_mode, true},
    {include_erts, false},
    {extended_start_script, true},
    {sys_config, "config/sys.config"},
    {vm_args, "config/vm.args"},
    {include_src, true}
]}.

{profiles, [
    {prod, [
        {relx, [
            {dev_mode, false},
            {include_erts, true},
            {sys_config, "config/prod.sys.config"},
            {vm_args, "config/prod.vm.args"}
        ]}
    ]},
    {test, [
        {deps, [
            {meck, "0.9.2"},
            {proper, "1.4.0"},
            {eunit, "2.3.5"}
        ]},
        {erl_opts, [nowarn_export_all, debug_info]},
        {cover_enabled, true}
    ]},
EOF

    # Add HotCI profile if enabled
    if [ "$hotci_enabled" = true ]; then
        cat >> "$project_dir/rebar.config" << EOF
    {hotci, [
        {deps, [
            {meck, "0.9.2"},
            {proper, "1.4.0"},
            {eunit, "2.3.5"},
            {peer, "4.6.0"}
        ]},
        {erl_opts, [nowarn_export_all, debug_info]},
        {cover_enabled, true},
        {steps, [
            {"unit", "ect"},
            {"hot_upgrade", "test/hotci/upgrade_downgrade_SUITE"}
        ]}
    ]},
EOF
    fi

    cat >> "$project_dir/rebar.config" << EOF
]}.

%% HotCI-specific plugins
{plugins, []}.

%% Dialyzer type checking
{dialyzer, [
    {warnings, [
        unmatched_returns,
        error_handling,
        unknown,
        no_return
    ]},
    {plt_apps, all_deps},
    {plt_extra_apps, [inets, crypto]}
]}.

%% Code coverage
{cover_enabled, true}.
{cover_opts, [verbose]}.

%% EDoc documentation
{edoc_opts, [
    {preprocess, true},
    {includes, ["include"]},
    {source_path, ["src"]}
]}.
EOF

    # Generate app.src
    cat > "$project_dir/src/$name.app.src" << EOF
{application, $name, [
    {description, "A2A Application"},
    {vsn, "$version"},
    {modules, []},
    {registered, []},
    {applications, [
        kernel,
        stdlib,
        sasl,
        inets
    ]},
    {mod, {$name\_app, []}},
    {env, []}
]}.
EOF

    # Generate app module
    cat > "$project_dir/src/$name_app.erl" << EOF
-module($name_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    case $name_sup:start_link() of
        {ok, Pid} -> {ok, Pid};
        Error -> Error
    end.

stop(_State) ->
    ok.
EOF

    # Generate supervisor
    cat > "$project_dir/src/$name_sup.erl" << EOF
-module($name_sup).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ChildSpecs = [
        %% Add your child specifications here
        % {$name_worker, {$name_worker, start_link, []},
        %  permanent, 5000, worker, [$name_worker]}
    ],
    {ok, {{one_for_one, 5, 10}, ChildSpecs}}.
EOF

    # Generate basic test
    cat > "$project_dir/test/$name_SUITE.erl" << EOF
-module($name_SUITE).
-behaviour(ct_suite).

-export([all/0]).

all() -> [basic_test].

basic_test(_Config) ->
    %% Add your test cases here
    ok.
EOF

    # Generate HotCI files if enabled
    if [ "$hotci_enabled" = true ]; then
        # Generate HotCI supervisor
        cat > "$project_dir/hotci/src/hotci_supervisor.erl" << EOF
-module(hotci_supervisor).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        {hotci_runner, {hotci_runner, start_link, []}, permanent, 5000, worker, [hotci_runner]}
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
EOF

        # Generate HotCI test suite
        cat > "$project_dir/hotci/tests/hotci_upgrade_SUITE.erl" << EOF
-module(hotci_upgrade_SUITE).
-behaviour(ct_suite).

-export([all/0, groups/0]).

all() -> [group, hotci_upgrade].

groups() -> [{hotci_upgrade, [parallel], [upgrade_test]}].

upgrade_test(_Config) ->
    %% Hot code upgrade test
    ok.
EOF
    fi

    # Generate basic config files
    mkdir -p "$project_dir/config"
    cat > "$project_dir/config/sys.config" << EOF
[
    {$name, [
        %% Add your configuration here
        {port, 8080}
    ]}
].
EOF

    cat > "$project_dir/config/vm.args" << EOF
## A2A VM Arguments
## Add your VM arguments here

-name $name@127.0.0.1
-setcookie a2a_hotci
-kernel net_ticktime 60
-heart
EOF

    # Generate Makefile
    cat > "$project_dir/Makefile" << EOF
# A2A HotCI Makefile
.PHONY: build test clean hotci-build hotci-test

build:
\trebar3 compile

test:
\trebar3 eunit

clean:
\trebar3 clean

hotci-build:
\trebar3 as hotci compile

hotci-test:
\trebar3 as hotci ct

hotci-upgrade:
\trebar3 as hotci ct --suite hotci_upgrade_SUITE

shell:
\trebar3 shell
EOF

    # Generate README
    cat > "$project_dir/README.md" << EOF
# $name

A2A HotCI Release Project

## Project Structure

- \`src/\` - Source code
- \`test/\` - Test suites
- \`hotci/\` - HotCI-specific files (if enabled)
- \`config/\` - Configuration files
- \`scripts/\` - Utility scripts
- \`docs/\` - Documentation

## Development

\`\`\`bash
# Build the project
make build

# Run tests
make test

# Run HotCI tests
make hotci-build
make hotci-test

# Run HotCI upgrade tests
make hotci-upgrade

# Start development shell
make shell
\`\`\`

## HotCI Features

This project includes HotCI (Hot Code Improvement) features for:
- Hot code upgrade testing
- Zero-downtime deployment validation
- Multi-node coordination
- Performance monitoring

## Building and Deployment

\`\`\`bash
# Build release
rebar3 release

# Create tarball
rebar3 tar

# Install release
rebar3 install
\`\`\`
EOF

    # Initialize git repository
    cd "$project_dir"
    git init > /dev/null 2>&1
    git add .
    git commit -m "Initial commit: $name release project" > /dev/null 2>&1

    log_success "Generated canonical release project: $project_dir"
    log_info "Run 'cd $project_dir' to start development"
}

# Generate umbrella project
generate_umbrella() {
    local name="$1"
    local version="${2:-0.1.0}"
    local otp_version="${3:-28}"
    local apps="${4:-core}"
    local hotci_enabled=true
    local force=false
    local output_dir="."

    # Parse additional options
    shift 4
    while [ $# -gt 0 ]; do
        case $1 in
            --no-hotci) hotci_enabled=false ;;
            --force) force=true ;;
            --output) output_dir="$2"; shift ;;
        esac
        shift
    done

    local project_dir="$output_dir/$name"

    if [ -d "$project_dir" ] && [ "$force" = false ]; then
        log_error "Directory $project_dir already exists. Use --force to overwrite."
        exit 1
    fi

    log_info "Generating canonical umbrella project: $name"

    # Create umbrella structure
    mkdir -p "$project_dir/apps"
    mkdir -p "$project_dir/config"
    mkdir -p "$project_dir/scripts"
    mkdir -p "$project_dir/docs"

    # HotCI directories
    if [ "$hotci_enabled" = true ]; then
        mkdir -p "$project_dir/hotci/src"
        mkdir -p "$project_dir/hotci/integration"
        mkdir -p "$project_dir/hotci/performance"
    fi

    # Generate rebar.config
    cat > "$project_dir/rebar.config" << EOF
%% -*- mode: erlang; -*-
%% A2A Umbrella Project - rebar3 configuration
%% Generated by A2A HotCI Project Generator
{minimum_otp_vsn, "$otp_version"}.

{erl_opts, [
    debug_info,
    warnings_as_errors,
    warn_export_vars,
    warn_unused_import,
    warn_shadow_vars,
    {i, "include"}
]}.

{deps, []}.

{subdirs, ["apps"]}.

%% Shell configuration for development
{shell, [
    {apps, [$apps]},
    {config, "config/sys.config"}
]}.

EOF

    # Add HotCI profile if enabled
    if [ "$hotci_enabled" = true ]; then
        cat >> "$project_dir/rebar.config" << EOF
{profiles, [
    {hotci, [
        {deps, [
            {meck, "0.9.2"},
            {proper, "1.4.0"},
            {eunit, "2.3.5"},
            {peer, "4.6.0"}
        ]},
        {erl_opts, [nowarn_export_all, debug_info]},
        {cover_enabled, true},
        {steps, [
            {"unit", "ect"},
            {"integration", "test/hotci/integration_SUITE"},
            {"upgrade", "test/hotci/upgrade_downgrade_SUITE"}
        ]}
    ]}
]}.
EOF
    else
        cat >> "$project_dir/rebar.config" << EOF

{profiles, [
    {test, [
        {deps, [
            {meck, "0.9.2"},
            {proper, "1.4.0"}
        ]},
        {erl_opts, [nowarn_export_all, debug_info]},
        {cover_enabled, true}
    ]}
]}.
EOF
    fi

    # Generate apps
    IFS=',' read -ra APP_ARRAY <<< "$apps"
    for app in "${APP_ARRAY[@]}"; do
        generate_app "$app" "$project_dir" "$version" "$otp_version" "$hotci_enabled"
    done

    # Generate umbrella root app
    cat > "$project_dir/src/$name_app.erl" << EOF
-module($name_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    $name_sup:start_link().

stop(_State) ->
    ok.
EOF

    # Generate umbrella supervisor
    cat > "$project_dir/src/$name_sup.erl" << EOF
-module($name_sup).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        %% Add applications here
        % {app_name, {app_name_sup, start_link, []}, permanent, 5000, supervisor, [app_name]}
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
EOF

    # Generate config
    cat > "$project_dir/config/sys.config" << EOF
[
    {$name, [
        %% Global configuration
        {apps, [$apps]}
    ]}
].
EOF

    # Generate Makefile
    cat > "$project_dir/Makefile" << EOF
# A2A HotCI Umbrella Makefile
.PHONY: build test clean hotci-build hotci-test

build:
\trebar3 compile

test:
\trebar3 eunit

clean:
\trebar3 clean

hotci-build:
\trebar3 as hotci compile

hotci-test:
\trebar3 as hotci ct

shell:
\trebar3 shell
EOF

    # Generate README
    cat > "$project_dir/README.md" << EOF
# $name

A2A HotCI Umbrella Project

## Project Structure

- \`apps/\` - Applications
- \`src/\` - Umbrella root source
- \`test/\` - Test suites
- \`hotci/\` - HotCI-specific files
- \`config/\` - Configuration files
- \`docs/\` - Documentation

## Applications

$apps

## Development

\`\`\`bash
# Build the project
make build

# Run tests
make test

# Run HotCI tests
make hotci-build
make hotci-test

# Start development shell
make shell
\`\`\`

## HotCI Features

This umbrella project includes HotCI features for multi-application coordination.
EOF

    # Initialize git
    cd "$project_dir"
    git init > /dev/null 2>&1
    git add .
    git commit -m "Initial commit: $name umbrella project" > /dev/null 2>&1

    log_success "Generated canonical umbrella project: $project_dir"
    log_info "Run 'cd $project_dir' to start development"
}

# Generate application
generate_app() {
    local app="$1"
    local project_dir="$2"
    local version="${3:-0.1.0}"
    local otp_version="$4"
    local hotci_enabled="$5"

    local app_dir="$project_dir/apps/$app"

    mkdir -p "$app_dir/src"
    mkdir -p "$app_dir/test"
    mkdir -p "$app_dir/include"
    mkdir -p "$app_dir/ebin"

    # Generate app.config
    cat > "$app_dir/src/$app.app.src" << EOF
{application, $app, [
    {description, "A2A $app Application"},
    {vsn, "$version"},
    {modules, []},
    {registered, []},
    {applications, [
        kernel,
        stdlib,
        sasl,
        inets
    ]},
    {mod, {$app\_app, []}},
    {env, []}
]}.
EOF

    # Generate app module
    cat > "$app_dir/src/$app_app.erl" << EOF
-module($app_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    case $app_sup:start_link() of
        {ok, Pid} -> {ok, Pid};
        Error -> Error
    end.

stop(_State) ->
    ok.
EOF

    # Generate supervisor
    cat > "$app_dir/src/$app_sup.erl" << EOF
-module($app_sup).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ChildSpecs = [
        %% Add your child specifications here
    ],
    {ok, {{one_for_one, 5, 10}, ChildSpecs}}.
EOF

    # Generate basic test
    cat > "$app_dir/test/$app_SUITE.erl" << EOF
-module($app_SUITE).
-behaviour(ct_suite).

-export([all/0]).

all() -> [basic_test].

basic_test(_Config) ->
    %% Add your test cases here
    ok.
EOF

    log_info "Generated app: $app"
}

# Enhance existing project
enhance_project() {
    local project_dir="$1"
    local hotci_enabled=true

    if [ ! -d "$project_dir" ]; then
        log_error "Project directory not found: $project_dir"
        exit 1
    fi

    log_info "Enhancing project: $project_dir with HotCI features"

    # Check if it's a valid rebar project
    if [ ! -f "$project_dir/rebar.config" ]; then
        log_error "Not a valid rebar project: rebar.config not found"
        exit 1
    fi

    # Create HotCI directories
    if [ "$hotci_enabled" = true ]; then
        mkdir -p "$project_dir/hotci/src"
        mkdir -p "$project_dir/hotci/tests"
        mkdir -p "$project_dir/hotci/config"
        mkdir -p "$project_dir/hotci/integration"
        mkdir -p "$project_dir/hotci/performance"
    fi

    # Add HotCI configuration to rebar.config
    if grep -q "profiles" "$project_dir/rebar.config"; then
        # HotCI profile already exists
        log_warning "HotCI profile already exists in rebar.config"
    else
        # Add HotCI profile
        temp_file=$(mktemp)
        awk '
            /^}$/{print "    {hotci, [\n        {deps, [\n            {meck, \"0.9.2\"},\n            {proper, \"1.4.0\"},\n            {eunit, \"2.3.5\"},\n            {peer, \"4.6.0\"}\n        ]},\n        {erl_opts, [nowarn_export_all, debug_info]},\n        {cover_enabled, true},\n        {steps, [\n            {\"unit\", \"ect\"},\n            {\"integration\", \"test/hotci/integration_SUITE\"},\n            {\"upgrade\", \"test/hotci/upgrade_downgrade_SUITE\"}\n        ]}\n    ]},\n" $0} NR==FNR{print} ' "$project_dir/rebar.config" > "$temp_file"
        mv "$temp_file" "$project_dir/rebar.config"
    fi

    # Generate HotCI files
    if [ "$hotci_enabled" = true ]; then
        generate_hotci_supervisor "$project_dir"
        generate_hotci_test_suite "$project_dir"
        generate_hotci_orchestrator "$project_dir"
        generate_hotci_integration_suite "$project_dir"
    fi

    # Add HotCI to Makefile if it exists
    if [ -f "$project_dir/Makefile" ]; then
        if grep -q "hotci-build" "$project_dir/Makefile"; then
            log_warning "HotCI targets already exist in Makefile"
        else
            cat >> "$project_dir/Makefile" << EOF

# HotCI targets
hotci-build:
\trebar3 as hotci compile

hotci-test:
\trebar3 as hotci ct

hotci-upgrade:
\trebar3 as hotci ct --suite hotci_upgrade_SUITE

hotci-integration:
\trebar3 as hotci ct --suite hotci_integration_SUITE
EOF
        fi
    else
        cat > "$project_dir/Makefile" << EOF
# A2A HotCI Makefile
.PHONY: build test clean hotci-build hotci-test hotci-upgrade hotci-integration

build:
\trebar3 compile

test:
\trebar3 eunit

clean:
\trebar3 clean

hotci-build:
\trebar3 as hotci compile

hotci-test:
\trebar3 as hotci ct

hotci-upgrade:
\trebar3 as hotci ct --suite hotci_upgrade_SUITE

hotci-integration:
\trebar3 as hotci ct --suite hotci_integration_SUITE

shell:
\trebar3 shell
EOF
    fi

    log_success "Enhanced project: $project_dir with HotCI features"
}

# Generate HotCI supervisor
generate_hotci_supervisor() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    cat > "$project_dir/hotci/src/hotci_supervisor.erl" << EOF
-module(${project_name}_hotci_supervisor).
-behaviour(supervisor).

-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        ${project_name}_hotci_runner,
        ${project_name}_hotci_metrics,
        ${project_name}_hotci_monitor
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
EOF
}

# Generate HotCI test suite
generate_hotci_test_suite() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    cat > "$project_dir/hotci/tests/${project_name}_hotci_SUITE.erl" << EOF
-module(${project_name}_hotci_SUITE).
-behaviour(ct_suite).

-export([all/0, groups/0]).

all() -> [{group, hotci_upgrade}].

groups() -> [{hotci_upgrade, [parallel], [upgrade_test]}].

upgrade_test(_Config) ->
    %% Hot code upgrade test
    ok.
EOF
}

# Generate HotCI orchestrator
generate_hotci_orchestrator() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    cat > "$project_dir/hotci/src/${project_name}_hotci_orchestrator.erl" << EOF
-module(${project_name}_hotci_orchestrator).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {test_nodes = [], upgrade_state = idle, metrics = #{}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) -> {ok, #state{}}.

handle_call(get_status, _From, State) -> {reply, {ok, State#state.upgrade_state}, State}.

handle_cast({start_tests, Config}, State) -> {noreply, State}.

handle_info({test_result, TestName, Result}, State) ->
    {noreply, State#state{metrics = maps:put(TestName, Result, State#state.metrics)}}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
EOF
}

# Generate HotCI integration suite
generate_hotci_integration_suite() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    cat > "$project_dir/hotci/integration/${project_name}_hotci_integration_SUITE.erl" << EOF
-module(${project_name}_hotci_integration_SUITE).
-behaviour(ct_suite).

-export([all/0]).

all() -> [multi_node_test].

multi_node_test(_Config) ->
    %% Multi-node integration test
    ok.
EOF
}

# Validate project
validate_project() {
    local project_dir="$1"

    if [ ! -d "$project_dir" ]; then
        log_error "Project directory not found: $project_dir"
        return 1
    fi

    local required_files=("rebar.config" "src" "test")
    local missing_files=()

    for file in "${required_files[@]}"; do
        if [ ! -e "$project_dir/$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "Missing required files: ${missing_files[*]}"
        return 1
    fi

    # Check for HotCI support
    if [ -d "$project_dir/hotci" ]; then
        log_info "Project has HotCI support"
    fi

    # Check for HotCI profile in rebar.config
    if grep -q "hotci" "$project_dir/rebar.config"; then
        log_info "HotCI profile found in rebar.config"
    fi

    log_success "Project validation passed: $project_dir"
    return 0
}

# Main command dispatcher
main() {
    check_dependencies

    case "${1:-help}" in
        generate)
            case "$2" in
                release)
                    generate_release "$3" "$4" "$5" "$6" "$7" "$8" "$9"
                    ;;
                umbrella)
                    generate_umbrella "$3" "$4" "$5" "$6" "$7" "$8" "$9"
                    ;;
                app)
                    shift 2
                    if [ $# -lt 1 ]; then
                        log_error "Usage: $0 generate app <name> [options]"
                        exit 1
                    fi
                    generate_app "$2" "$3" "$4" "$5" "$6"
                    ;;
                hotci)
                    generate_release "$3" "$4" "$5" "$6" "$7" "$8" "$9" --hotci
                    ;;
                *)
                    log_error "Unknown generate type: $2"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        enhance)
            enhance_project "$2"
            ;;
        validate)
            validate_project "$2"
            ;;
        list-templates)
            ls -1 "$TEMPLATES_DIR" | grep -E "\.erl$|\.sh$" | sed 's/\.erl$//' | sed 's/\.sh$//'
            ;;
        --help|help)
            usage
            ;;
        --version)
            echo "A2A HotCI Project Generator v1.0.0"
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"