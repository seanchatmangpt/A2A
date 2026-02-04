%%% @doc Craftplan A2A Agent Supervisor
%%% Supervises A2A protocol handlers and task processors

-module(craftplan_a2a_sup).
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
            id => craftplan_a2a_server,
            start => {craftplan_a2a_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [craftplan_a2a_server]
        },
        #{
            id => craftplan_task_sup,
            start => {craftplan_task_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [craftplan_task_sup]
        },
        #{
            id => craftplan_agent_card,
            start => {craftplan_agent_card, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [craftplan_agent_card]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.
