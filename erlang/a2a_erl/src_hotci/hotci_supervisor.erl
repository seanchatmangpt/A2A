%%% @doc HotCI Framework Supervisor
%%%
%%% This module supervises all HotCI components for distributed Erlang/OTP
%%% systems, including node orchestrators, upgrade validators, and monitoring
%%% processes.
-module(hotci_supervisor).
-behaviour(supervisor).

%% API
-export([start_link/0, start_child/1, stop_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% Child specification exports
-export([node_orchestrator_spec/0, upgrade_validator_spec/0,
         consistency_checker_spec/0, metrics_collector_spec/0,
         failure_injector_spec/0, rollback_coordinator_spec/0]).

-define(SERVER, ?MODULE).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the HotCI supervisor
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a HotCI child process
-spec start_child(ChildSpec :: term()) -> {ok, pid()} | {error, term()}.
start_child(ChildSpec) ->
    supervisor:start_child(?SERVER, ChildSpec).

%% @doc Stop a HotCI child process
-spec stop_child(ChildId :: term()) -> ok | {error, term()}.
stop_child(ChildId) ->
    supervisor:terminate_child(?SERVER, ChildId),
    supervisor:delete_child(?SERVER, ChildId).

%%% ============================================================================
%%% Supervisor Callbacks
%%% ============================================================================

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    %% Define the HotCI component tree
    Children = [
        %% Orchestrators (start first)
        node_orchestrator_spec(),
        upgrade_validator_spec(),

        %% Monitors (start after orchestrators)
        consistency_checker_spec(),
        metrics_collector_spec(),

        %% Test components (start after monitors)
        failure_injector_spec(),
        rollback_coordinator_spec()
    ],

    %% Restart strategy: one-for-one, with temporary children
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60,
        max_restart => 10,
        max_shutdown => infinity
    },

    {ok, {SupFlags, Children}}.

%%% ============================================================================
%%% Child Specifications
%%% ============================================================================

%% @doc Create node orchestrator child specification
-spec node_orchestrator_spec() -> supervisor:child_spec().
node_orchestrator_spec() ->
    #{
        id => hotci_node_orchestrator,
        start => {hotci_node_orchestrator, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [hotci_node_orchestrator],
        significant => true
    }.

%% @doc Create upgrade validator child specification
-spec upgrade_validator_spec() -> supervisor:child_spec().
upgrade_validator_spec() ->
    #{
        id => hotci_upgrade_validator,
        start => {hotci_upgrade_validator, start_link, []},
        restart => permanent,
        shutdown => 10000,
        type => worker,
        modules => [hotci_upgrade_validator],
        significant => true
    }.

%% @doc Create consistency checker child specification
-spec consistency_checker_spec() -> supervisor:child_spec().
consistency_checker_spec() ->
    #{
        id => hotci_consistency_checker,
        start => {hotci_consistency_checker, start_link, []},
        restart => permanent,
        shutdown => 8000,
        type => worker,
        modules => [hotci_consistency_checker],
        significant => true
    }.

%% @doc Create metrics collector child specification
-spec metrics_collector_spec() -> supervisor:child_spec().
metrics_collector_spec() ->
    #{
        id => hotci_metrics_collector,
        start => {hotci_metrics_collector, start_link, []},
        restart => permanent,
        shutdown => 3000,
        type => worker,
        modules => [hotci_metrics_collector],
        significant => true
    }.

%% @doc Create failure injector child specification
-spec failure_injector_spec() -> supervisor:child_spec().
failure_injector_spec() ->
    #{
        id => hotci_failure_injector,
        start => {hotci_failure_injector, start_link, []},
        restart => transient,
        shutdown => 5000,
        type => worker,
        modules => [hotci_failure_injector],
        significant => true
    }.

%% @doc Create rollback coordinator child specification
-spec rollback_coordinator_spec() -> supervisor:child_spec().
rollback_coordinator_spec() ->
    #{
        id => hotci_rollback_coordinator,
        start => {hotci_rollback_coordinator, start_link, []},
        restart => permanent,
        shutdown => 10000,
        type => worker,
        modules => [hotci_rollback_coordinator],
        significant => true
    }.