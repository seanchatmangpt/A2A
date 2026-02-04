%%% @doc Craftplan MCP Tools Supervisor
%%% Supervises individual tool handlers

-module(craftplan_tools_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },

    Tools = [
        customer_management,
        order_management,
        inventory_management,
        production_planning,
        analytics,
        shipping
    ],

    ChildSpecs = [tool_spec(Tool) || Tool <- Tools],

    {ok, {SupFlags, ChildSpecs}}.

%%====================================================================
%% Internal functions
%%====================================================================

tool_spec(ToolName) ->
    Module = list_to_atom("craftplan_" ++ atom_to_list(ToolName) ++ "_tool"),
    #{
        id => Module,
        start => {Module, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [Module]
    }.
