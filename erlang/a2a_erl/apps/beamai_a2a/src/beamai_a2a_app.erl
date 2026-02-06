%%%-------------------------------------------------------------------
%%% @doc beamai_a2a application callback module.
%%% Provides Agent-to-Agent protocol integration for BeamAI,
%%% bridging the A2A protocol with BeamAI kernel capabilities.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_a2a_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
