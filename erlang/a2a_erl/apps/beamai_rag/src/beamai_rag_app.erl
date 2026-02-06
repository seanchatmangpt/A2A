%%%-------------------------------------------------------------------
%%% @doc beamai_rag application callback module.
%%% Provides Retrieval-Augmented Generation capabilities, combining
%%% memory/knowledge retrieval with LLM generation.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_rag_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_rag_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
