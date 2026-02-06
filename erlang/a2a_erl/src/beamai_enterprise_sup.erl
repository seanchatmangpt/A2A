%%%-------------------------------------------------------------------
%%% @doc Supervisor for enterprise adapter workers
%%%
%%% Manages one_for_one child processes for enterprise integrations:
%%% - beamai_hotci_adapter   (hot code injection / CI integration)
%%% - beamai_health_adapter  (health check bridge)
%%% - beamai_metrics_adapter (metrics collection bridge)
%%% - beamai_integrity_adapter (data integrity checks)
%%% - beamai_security_adapter (security policy enforcement)
%%%
%%% Each adapter is a gen_server that bridges between the A2A
%%% infrastructure (a2a_health_handler, a2a_metrics, etc.) and the
%%% beamai kernel's tool/filter system.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_enterprise_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_link/1]).

%% supervisor callback
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Opts).

%%====================================================================
%% supervisor callback
%%====================================================================

init(Opts) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },

    Adapters = maps:get(adapters, Opts, default_adapters()),

    Children = [adapter_child_spec(Id, Mod, AdapterOpts)
                || {Id, Mod, AdapterOpts} <- Adapters,
                   is_module_available(Mod)],

    {ok, {SupFlags, Children}}.

%%====================================================================
%% Internal
%%====================================================================

default_adapters() ->
    [
        {beamai_health_adapter, beamai_health_adapter, #{}},
        {beamai_metrics_adapter, beamai_metrics_adapter, #{}},
        {beamai_integrity_adapter, beamai_integrity_adapter, #{}},
        {beamai_security_adapter, beamai_security_adapter, #{}},
        {beamai_hotci_adapter, beamai_hotci_adapter, #{}}
    ].

adapter_child_spec(Id, Module, Opts) ->
    #{
        id => Id,
        start => {Module, start_link, [Opts]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [Module]
    }.

%% @doc Check if a module is loadable. If the adapter module does not
%% exist yet, we silently skip it so the supervisor can still start.
is_module_available(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} -> true;
        {error, _} -> false
    end.
