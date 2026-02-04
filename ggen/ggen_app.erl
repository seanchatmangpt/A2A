%%====================================================================
%% Module: ggen_app
%% Description: ggen OTP application for A2A code generation
%%====================================================================

-module(ggen_app).
-behaviour(application).

-export([start/2, stop/1]).

%%====================================================================
%% Application Callbacks
%%====================================================================

-spec start(StartType :: term(), StartArgs :: term()) ->
    {ok, pid()} | {ok, pid(), term()} | {error, term()}.
start(_StartType, _StartArgs) ->
    ggen_sup:start_link().

-spec stop(State :: term()) -> ok.
stop(_State) ->
    ok.