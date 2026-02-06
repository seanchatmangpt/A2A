%%%-------------------------------------------------------------------
%%% @doc Supervisor for beamai bridge components
%%%
%%% one_for_one strategy supervisor that starts:
%%% - beamai_bridge (main kernel bridge)
%%% - beamai_process_bridge (task process bridge)
%%% - beamai_event_adapter (event forwarding)
%%% - beamai_enterprise_sup (enterprise adapters)
%%%
%%% Children are configurable via application env
%%% `{a2a_erl, [{beamai_bridge_opts, #{...}}]}`.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_supervisor_bridge).

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
    Opts = application:get_env(a2a_erl, beamai_bridge_opts, #{}),
    start_link(Opts).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Opts).

%%====================================================================
%% supervisor callback
%%====================================================================

init(Opts) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },

    BridgeOpts = maps:get(bridge, Opts, #{}),
    EnableProcess = maps:get(enable_process_bridge, Opts, true),
    EnableEvents = maps:get(enable_event_adapter, Opts, true),
    EnableEnterprise = maps:get(enable_enterprise, Opts, true),

    Bridge = #{
        id => beamai_bridge,
        start => {beamai_bridge, start_link, [BridgeOpts]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_bridge]
    },

    ProcessBridge = #{
        id => beamai_process_bridge,
        start => {beamai_process_bridge, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_process_bridge]
    },

    EventAdapter = #{
        id => beamai_event_adapter,
        start => {beamai_event_adapter, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_event_adapter]
    },

    EnterpriseSup = #{
        id => beamai_enterprise_sup,
        start => {beamai_enterprise_sup, start_link, []},
        restart => permanent,
        shutdown => infinity,
        type => supervisor,
        modules => [beamai_enterprise_sup]
    },

    Children = [Bridge]
        ++ [ProcessBridge || EnableProcess]
        ++ [EventAdapter || EnableEvents]
        ++ [EnterpriseSup || EnableEnterprise],

    {ok, {SupFlags, Children}}.
