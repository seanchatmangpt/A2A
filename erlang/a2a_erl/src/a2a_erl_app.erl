%%% @doc A2A Erlang Application
%%%
%%% This is the main OTP application module for the A2A protocol implementation.
%%% It starts the supervisor which manages all the A2A services.
-module(a2a_erl_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%% ============================================================================
%%% Application Callbacks
%%% ============================================================================

start(_StartType, _StartArgs) ->
    %% Start inets for httpc (push notifications)
    case inets:start() of
        ok -> ok;
        {error, {already_started, inets}} -> ok
    end,

    %% Start the supervisor
    case a2a_erl_sup:start_link() of
        {ok, Pid} ->
            %% Start Cowboy HTTP server
            start_cowboy(),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    %% Stop Cowboy
    cowboy:stop_listener(a2a_http_listener),
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

start_cowboy() ->
    %% Get configuration
    Port = application:get_env(a2a_erl, port, 8080),

    %% Define routes
    Dispatch = cowboy_router:compile([
        {'_', [
            %% Agent card discovery
            {"/.well-known/agent-card.json", a2a_http_handler, []},

            %% Core A2A endpoints
            {"/message:send", a2a_http_handler, []},
            {"/message:stream", a2a_sse_handler, []},
            {"/tasks", a2a_http_handler, []},
            {"/tasks/:task_id", a2a_http_handler, []},
            {"/tasks/:task_id:cancel", a2a_http_handler, []},
            {"/tasks/:task_id:subscribe", a2a_sse_handler, []},

            %% Push notification config endpoints
            {"/tasks/:task_id/pushNotificationConfigs", a2a_http_handler, []},
            {"/tasks/:task_id/pushNotificationConfigs/:config_id", a2a_http_handler, []},

            %% Extended agent card
            {"/extendedAgentCard", a2a_http_handler, []},

            %% Tenant-prefixed routes
            {"/:tenant/message:send", a2a_http_handler, []},
            {"/:tenant/message:stream", a2a_sse_handler, []},
            {"/:tenant/tasks", a2a_http_handler, []},
            {"/:tenant/tasks/:task_id", a2a_http_handler, []},
            {"/:tenant/tasks/:task_id:cancel", a2a_http_handler, []},
            {"/:tenant/tasks/:task_id:subscribe", a2a_sse_handler, []}
        ]}
    ]),

    %% Start HTTP listener
    {ok, _} = cowboy:start_clear(
        a2a_http_listener,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),

    logger:info("A2A server started on port ~p", [Port]),
    ok.
