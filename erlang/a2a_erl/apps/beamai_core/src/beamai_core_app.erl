%%%-------------------------------------------------------------------
%%% @doc beamai_core application callback module.
%%% Starts the BeamAI Core application which provides the kernel,
%%% tool registry, LLM providers, and filter pipeline.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_core_app).

-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @doc Start the beamai_core application.
%% Initializes the ETS tables and starts the supervision tree.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_core_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the beamai_core application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
