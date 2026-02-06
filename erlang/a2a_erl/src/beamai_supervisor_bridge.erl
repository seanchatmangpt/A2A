%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Supervisor Bridge
%%%
%%% A supervisor that manages all BeamAI bridge components. This
%%% supervisor is designed to sit under a2a_erl_sup and starts the
%%% following children:
%%%
%%% 1. beamai_bridge        - Core kernel bridge (gen_server)
%%% 2. beamai_process_bridge - Process/task state mapping (gen_server)
%%% 3. beamai_graph_bridge   - YAWL/Petri net graph bridge (gen_server)
%%% 4. beamai_event_adapter  - A2A/BeamAI event translation (gen_server)
%%%
%%% The supervisor supports configuration-driven activation: individual
%%% bridge components can be enabled or disabled via the config map
%%% passed to start_link/1 or via application environment variables.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_supervisor_bridge).
-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_link/1,
    which_children_info/0
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

-define(DEFAULT_CONFIG, #{
    enable_bridge => true,
    enable_process_bridge => true,
    enable_graph_bridge => true,
    enable_event_adapter => true,
    bridge_config => #{},
    process_bridge_config => #{},
    graph_bridge_config => #{},
    event_adapter_config => #{}
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the supervisor with default configuration.
%% Reads configuration from the application environment key
%% `beamai_config` if available, otherwise uses defaults.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    EnvConfig = application:get_env(a2a_erl, beamai_config, #{}),
    start_link(EnvConfig).

%% @doc Start the supervisor with a custom configuration map.
%% The config map supports the following keys:
%%   - enable_bridge :: boolean()         - Enable the core bridge
%%   - enable_process_bridge :: boolean() - Enable the process bridge
%%   - enable_graph_bridge :: boolean()   - Enable the graph bridge
%%   - enable_event_adapter :: boolean()  - Enable the event adapter
%%   - bridge_config :: map()             - Config passed to beamai_bridge
%%   - process_bridge_config :: map()     - Config passed to beamai_process_bridge
%%   - graph_bridge_config :: map()       - Config passed to beamai_graph_bridge
%%   - event_adapter_config :: map()      - Config passed to beamai_event_adapter
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) when is_map(Config) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Config);
start_link(_) ->
    start_link(#{}).

%% @doc Return a summary of all active children and their status.
-spec which_children_info() -> [map()].
which_children_info() ->
    Children = supervisor:which_children(?SERVER),
    lists:map(fun({Id, Pid, Type, Modules}) ->
        #{
            id => Id,
            pid => Pid,
            type => Type,
            modules => Modules,
            status => case Pid of
                undefined -> not_started;
                restarting -> restarting;
                P when is_pid(P) ->
                    case is_process_alive(P) of
                        true -> running;
                        false -> dead
                    end
            end
        }
    end, Children).

%%%===================================================================
%%% Supervisor Callbacks
%%%===================================================================

%% @private
init(UserConfig) ->
    Config = maps:merge(?DEFAULT_CONFIG, UserConfig),

    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },

    %% Build child specs based on enabled components
    ChildSpecs = build_child_specs(Config),

    logger:info("BeamAI supervisor bridge initializing with ~p component(s)",
                [length(ChildSpecs)]),

    {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Build the list of child specs based on configuration.
-spec build_child_specs(map()) -> [supervisor:child_spec()].
build_child_specs(Config) ->
    Components = [
        {enable_bridge, beamai_bridge, bridge_config},
        {enable_process_bridge, beamai_process_bridge, process_bridge_config},
        {enable_graph_bridge, beamai_graph_bridge, graph_bridge_config},
        {enable_event_adapter, beamai_event_adapter, event_adapter_config}
    ],

    lists:filtermap(fun({EnableKey, Module, ConfigKey}) ->
        case maps:get(EnableKey, Config, true) of
            true ->
                ChildConfig = maps:get(ConfigKey, Config, #{}),
                Spec = #{
                    id => Module,
                    start => {Module, start_link, [ChildConfig]},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [Module]
                },
                {true, Spec};
            false ->
                false
        end
    end, Components).
