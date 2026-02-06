%%%-------------------------------------------------------------------
%%% @doc beamai_tools application callback module.
%%% Provides built-in tool implementations and middleware for
%%% extending BeamAI agent capabilities.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tools_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_tools_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
