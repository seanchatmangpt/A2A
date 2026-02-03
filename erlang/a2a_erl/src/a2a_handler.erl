%%% @doc A2A Task Handler Behaviour
%%%
%%% This module defines the behaviour for implementing custom task handlers.
%%% Task handlers process incoming messages and produce artifacts.
%%%
%%% Example implementation:
%%% ```
%%% -module(my_handler).
%%% -behaviour(a2a_handler).
%%%
%%% -export([init/2, process/2, handle_message/2, terminate/2]).
%%%
%%% init(Task, Message) ->
%%%     {ok, #{}}.
%%%
%%% process(Task, State) ->
%%%     %% Do work and return result
%%%     {ok, #{artifacts => [create_artifact()]}}.
%%%
%%% handle_message(Message, State) ->
%%%     {continue, State}.
%%%
%%% terminate(Reason, State) ->
%%%     ok.
%%% ```
-module(a2a_handler).

-include("a2a.hrl").

%% Behaviour callbacks
-callback init(Task :: task(), Message :: message()) ->
    {ok, State :: term()} | {error, Reason :: term()}.

-callback process(Task :: task(), State :: term()) ->
    {ok, Result :: map()} |
    {error, Reason :: term()} |
    {input_required, Prompt :: binary()} |
    {auth_required, Details :: map()}.

-callback handle_message(Message :: message(), State :: term()) ->
    {ok, Result :: map()} |
    {continue, NewState :: term()} |
    {error, Reason :: term()}.

-callback terminate(Reason :: term(), State :: term()) ->
    ok.

%% Optional callbacks
-optional_callbacks([terminate/2]).
