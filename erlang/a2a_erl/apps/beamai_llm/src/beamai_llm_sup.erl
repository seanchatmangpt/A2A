%%%-------------------------------------------------------------------
%%% @doc beamai_llm top-level supervisor.
%%% Supervises the chat completion gen_server and any other LLM
%%% processes required by the framework.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_llm_sup).

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
%% Starts the beamai_chat_completion gen_server as a child.
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },
    ChatCompletion = #{
        id => beamai_chat_completion,
        start => {beamai_chat_completion, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_chat_completion]
    },
    {ok, {SupFlags, [ChatCompletion]}}.
