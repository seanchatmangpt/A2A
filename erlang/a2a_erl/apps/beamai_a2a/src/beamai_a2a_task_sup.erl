%%% @doc BeamAI A2A Task Supervisor
%%%
%%% A simple_one_for_one supervisor that dynamically manages beamai_a2a_task
%%% gen_server processes. Each child is a beamai_a2a_task process started
%%% with an options map.
%%%
%%% Usage:
%%%   {ok, _} = beamai_a2a_task_sup:start_link().
%%%   {ok, Pid} = beamai_a2a_task_sup:start_task(#{id => <<"task-1">>}).
%%% @end
-module(beamai_a2a_task_sup).
-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_task/1
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the task supervisor.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a new beamai_a2a_task child process under this supervisor.
%% Opts is a map passed to beamai_a2a_task:start_link/1. It may contain:
%%   id        - binary task ID
%%   status    - initial status atom
%%   messages  - initial messages
%%   artifacts - initial artifacts
%%   metadata  - metadata map
-spec start_task(map()) -> {ok, pid()} | {error, term()}.
start_task(Opts) when is_map(Opts) ->
    supervisor:start_child(?SERVER, [Opts]).

%%% ============================================================================
%%% Supervisor Callbacks
%%% ============================================================================

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 100,
        period => 60
    },

    ChildSpec = #{
        id => beamai_a2a_task,
        start => {beamai_a2a_task, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [beamai_a2a_task]
    },

    {ok, {SupFlags, [ChildSpec]}}.
