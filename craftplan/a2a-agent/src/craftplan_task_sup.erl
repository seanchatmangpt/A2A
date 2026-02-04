%%% @doc Craftplan Task Supervisor
%%% Simple_one_for_one supervisor for task handlers

-module(craftplan_task_sup).
-behaviour(supervisor).

%% API
-export([start_link/0, start_child/3]).
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_child(Module, Args) ->
    supervisor:start_child(?SERVER, [Module, Args]).

start_child(Module, Arg1, Arg2) ->
    supervisor:start_child(?SERVER, [Module, [Arg1, Arg2]]).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 10,
        period => 60
    },

    ChildSpec = #{
        id => task_handler,
        start => {craftplan_task_handler, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [craftplan_task_handler]
    },

    {ok, {SupFlags, [ChildSpec]}}.
