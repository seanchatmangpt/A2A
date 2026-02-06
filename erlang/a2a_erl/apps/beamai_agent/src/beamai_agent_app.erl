%%%-------------------------------------------------------------------
%%% @doc beamai_agent application callback module.
%%% Manages agent lifecycle, behavior, and coordination.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_agent_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
