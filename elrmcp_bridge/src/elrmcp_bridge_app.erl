%%% @doc elrmcp Bridge Application
%%% Top-level application for elrmcp MCP bridge

-module(elrmcp_bridge_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% Application Callbacks
%%====================================================================

start(_StartType, _StartArgs) ->
    io:format("Starting elrmcp Bridge Application~n"),
    elrmcp_bridge_sup:start_link().

stop(_State) ->
    io:format("Stopping elrmcp Bridge Application~n"),
    ok.