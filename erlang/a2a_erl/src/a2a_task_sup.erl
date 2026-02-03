%%% @doc A2A Task State Machine Supervisor
%%%
%%% A dynamic supervisor that manages task gen_statem processes.
%%% Uses OTP 28's supervisor module with simple_one_for_one strategy
%%% for efficient dynamic child management.
-module(a2a_task_sup).
-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_task/1,
    start_task/2,
    stop_task/1
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a new task with the given message
-spec start_task(term()) -> {ok, pid()} | {error, term()}.
start_task(Message) ->
    start_task(Message, #{}).

%% @doc Start a new task with message and options
-spec start_task(term(), map()) -> {ok, pid()} | {error, term()}.
start_task(Message, Opts) ->
    supervisor:start_child(?SERVER, [Message, Opts]).

%% @doc Stop a task by pid
-spec stop_task(pid()) -> ok | {error, term()}.
stop_task(Pid) ->
    supervisor:terminate_child(?SERVER, Pid).

%%% ============================================================================
%%% Supervisor Callbacks
%%% ============================================================================

init([]) ->
    %% Supervisor flags for dynamic children
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 100,
        period => 60
    },

    %% Child specification template
    ChildSpec = #{
        id => a2a_task_statem,
        start => {a2a_task_statem, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [a2a_task_statem]
    },

    {ok, {SupFlags, [ChildSpec]}}.
