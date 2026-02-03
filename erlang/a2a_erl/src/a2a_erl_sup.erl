%%% @doc A2A Erlang Top-Level Supervisor
%%%
%%% This supervisor manages the core A2A services:
%%% - a2a_task_store: ETS-backed task storage
%%% - a2a_agent_card: Agent card management
%%% - a2a_task_sup: Dynamic supervisor for task state machines
-module(a2a_erl_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%% ============================================================================
%%% Supervisor Callbacks
%%% ============================================================================

init([]) ->
    %% Supervisor flags
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },

    %% Child specifications
    ChildSpecs = [
        %% Task Store - ETS-backed task storage
        #{
            id => a2a_task_store,
            start => {a2a_task_store, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_task_store]
        },

        %% Agent Card Manager
        #{
            id => a2a_agent_card,
            start => {a2a_agent_card, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_agent_card]
        },

        %% Task State Machine Supervisor
        #{
            id => a2a_task_sup,
            start => {a2a_task_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [a2a_task_sup]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.
