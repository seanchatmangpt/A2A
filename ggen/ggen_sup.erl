%%====================================================================
%% Module: ggen_sup
%% Description: ggen supervisor
%%====================================================================

-module(ggen_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%====================================================================
%% Supervisor Callbacks
%%====================================================================

-spec init(Args :: term()) ->
    {ok, {supervisor:supervisor_opts(), [supervisor:child_spec()]}} | ignore.
init(_Args) ->
    Children = [
        ggen_file_watcher,
        ggen_metrics_collector
    ],

    Strategy = one_for_all,
    MaxRestarts = 3,
    MaxSeconds = 10,

    {ok, {{Strategy, MaxRestarts, MaxSeconds}, Children}}.