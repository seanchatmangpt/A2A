%%%-------------------------------------------------------------------
%%% @doc beamai_mcp application callback module.
%%% Provides Model Context Protocol (MCP) integration for BeamAI,
%%% enabling standardized communication between AI models and tools.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mcp_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    beamai_mcp_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
