%%%-------------------------------------------------------------------
%%% @doc beamai_core top-level supervisor.
%%% Supervises the BeamAI kernel gen_server and any other core
%%% processes required by the framework.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_core_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

%%--------------------------------------------------------------------
%% @doc Start the supervisor.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc Supervisor init callback.
%% Starts the beamai_kernel gen_server as a child.
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },
    Kernel = #{
        id => beamai_kernel,
        start => {beamai_kernel, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_kernel]
    },
    {ok, {SupFlags, [Kernel]}}.
