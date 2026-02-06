%%% @doc BeamAI Enterprise Supervisor
%%%
%%% This supervisor manages all BeamAI enterprise adapter modules. It
%%% starts each adapter under supervision using a rest_for_one strategy,
%%% which means that if an adapter crashes, all adapters started after it
%%% are also restarted. This reflects the dependency chain between
%%% adapters.
%%%
%%% The startup order is:
%%% 1. beamai_hotci_adapter - core HotCI integration (no dependencies)
%%% 2. beamai_security_adapter - security (depends on hotci adapter)
%%% 3. beamai_health_adapter - health checks (depends on security)
%%% 4. beamai_metrics_adapter - metrics collection (depends on health)
%%% 5. beamai_integrity_adapter - integrity validation (depends on metrics)
%%% 6. beamai_disaster_recovery_adapter - disaster recovery (depends on integrity)
%%% 7. beamai_monitoring_adapter - monitoring hub (depends on all above)
%%% 8. beamai_benchmark_adapter - benchmarking (optional, depends on monitoring)
%%%
%%% The supervisor can be started with a configuration map that specifies
%%% which adapters are active. By default, all adapters are started.
%%%
%%% @end
-module(beamai_enterprise_sup).
-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_link/1,
    init/1
]).

-define(SERVER, ?MODULE).

%% Default configuration: all adapters enabled
-define(DEFAULT_CONFIG, #{
    hotci_adapter => true,
    security_adapter => true,
    health_adapter => true,
    metrics_adapter => true,
    integrity_adapter => true,
    disaster_recovery_adapter => true,
    monitoring_adapter => true,
    benchmark_adapter => true
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the enterprise supervisor with default configuration.
%% All adapters are enabled by default.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(?DEFAULT_CONFIG).

%% @doc Start the enterprise supervisor with custom configuration.
%% The Config map can specify which adapters are active:
%%   #{hotci_adapter => true, benchmark_adapter => false, ...}
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Config).

%%%===================================================================
%%% Supervisor Callback
%%%===================================================================

%% @private
-spec init(map()) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init(Config) ->
    MergedConfig = maps:merge(?DEFAULT_CONFIG, Config),

    logger:info("BeamAI enterprise supervisor initializing with config: ~p", [MergedConfig]),

    %% Build child specs based on configuration
    AllSpecs = [
        {hotci_adapter, hotci_adapter_spec()},
        {security_adapter, security_adapter_spec()},
        {health_adapter, health_adapter_spec()},
        {metrics_adapter, metrics_adapter_spec()},
        {integrity_adapter, integrity_adapter_spec()},
        {disaster_recovery_adapter, disaster_recovery_adapter_spec()},
        {monitoring_adapter, monitoring_adapter_spec()},
        {benchmark_adapter, benchmark_adapter_spec()}
    ],

    %% Filter out disabled adapters
    ActiveSpecs = lists:filtermap(fun({Key, Spec}) ->
        case maps:get(Key, MergedConfig, true) of
            true -> {true, Spec};
            false ->
                logger:info("BeamAI enterprise supervisor: ~p disabled by config", [Key]),
                false
        end
    end, AllSpecs),

    %% rest_for_one: if one child terminates, all children started after
    %% it are terminated and restarted in order.
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 10,
        period => 60
    },

    {ok, {SupFlags, ActiveSpecs}}.

%%%===================================================================
%%% Child Specifications
%%%===================================================================

%% @private HotCI adapter - core integration with hot code upgrade system.
-spec hotci_adapter_spec() -> supervisor:child_spec().
hotci_adapter_spec() ->
    #{
        id => beamai_hotci_adapter,
        start => {beamai_hotci_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_hotci_adapter]
    }.

%% @private Security adapter - module integrity and audit.
-spec security_adapter_spec() -> supervisor:child_spec().
security_adapter_spec() ->
    #{
        id => beamai_security_adapter,
        start => {beamai_security_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_security_adapter]
    }.

%% @private Health adapter - component health checks.
-spec health_adapter_spec() -> supervisor:child_spec().
health_adapter_spec() ->
    #{
        id => beamai_health_adapter,
        start => {beamai_health_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_health_adapter]
    }.

%% @private Metrics adapter - metrics collection and Prometheus export.
-spec metrics_adapter_spec() -> supervisor:child_spec().
metrics_adapter_spec() ->
    #{
        id => beamai_metrics_adapter,
        start => {beamai_metrics_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_metrics_adapter]
    }.

%% @private Integrity adapter - state integrity validation.
-spec integrity_adapter_spec() -> supervisor:child_spec().
integrity_adapter_spec() ->
    #{
        id => beamai_integrity_adapter,
        start => {beamai_integrity_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_integrity_adapter]
    }.

%% @private Disaster recovery adapter - snapshots and restore.
-spec disaster_recovery_adapter_spec() -> supervisor:child_spec().
disaster_recovery_adapter_spec() ->
    #{
        id => beamai_disaster_recovery_adapter,
        start => {beamai_disaster_recovery_adapter, start_link, []},
        restart => permanent,
        shutdown => 10000,
        type => worker,
        modules => [beamai_disaster_recovery_adapter]
    }.

%% @private Monitoring adapter - dashboard and alerts.
-spec monitoring_adapter_spec() -> supervisor:child_spec().
monitoring_adapter_spec() ->
    #{
        id => beamai_monitoring_adapter,
        start => {beamai_monitoring_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_monitoring_adapter]
    }.

%% @private Benchmark adapter - performance benchmarking.
%% This adapter is transient since benchmarks are on-demand and
%% the adapter is less critical than others.
-spec benchmark_adapter_spec() -> supervisor:child_spec().
benchmark_adapter_spec() ->
    #{
        id => beamai_benchmark_adapter,
        start => {beamai_benchmark_adapter, start_link, []},
        restart => transient,
        shutdown => 5000,
        type => worker,
        modules => [beamai_benchmark_adapter]
    }.
