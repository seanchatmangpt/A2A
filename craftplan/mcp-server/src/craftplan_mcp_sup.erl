%%% @doc Craftplan MCP Server Supervisor
%%% Supervises all MCP tool handlers and connections

-module(craftplan_mcp_sup).
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
        intensity => 10,
        period => 60
    },

    ChildSpecs = [
        #{
            id => craftplan_mcp_server,
            start => {craftplan_mcp_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [craftplan_mcp_server]
        },
        #{
            id => craftplan_api_client,
            start => {craftplan_api_client, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [craftplan_api_client]
        },
        #{
            id => craftplan_tools_sup,
            start => {craftplan_tools_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [craftplan_tools_sup]
        },
        #{
            id => craftplan_a2a_bridge,
            start => {craftplan_a2a_bridge, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [craftplan_a2a_bridge]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.
