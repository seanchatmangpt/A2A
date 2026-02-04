%%% @doc Craftplan A2A Agent Application
%%% Implements A2A protocol for agent-to-agent collaboration

-module(craftplan_a2a_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% Application Callbacks
%%====================================================================

start(_StartType, _StartArgs) ->
    craftplan_a2a_sup:start_link().

stop(_State) ->
    ok.
