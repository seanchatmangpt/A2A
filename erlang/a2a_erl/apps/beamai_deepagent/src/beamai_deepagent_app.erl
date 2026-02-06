%%%-------------------------------------------------------------------
%%% @doc beamai_deepagent application callback module.
%%% Advanced multi-step agent orchestration with planning,
%%% reasoning, and autonomous task decomposition.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_deepagent_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_deepagent_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
