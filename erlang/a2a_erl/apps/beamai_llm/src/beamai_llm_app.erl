%%%-------------------------------------------------------------------
%%% @doc beamai_llm application callback module.
%%% Starts the BeamAI LLM application which provides chat completion,
%%% output parsing, and multi-provider LLM support.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_llm_app).

-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @doc Start the beamai_llm application.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_llm_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the beamai_llm application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
