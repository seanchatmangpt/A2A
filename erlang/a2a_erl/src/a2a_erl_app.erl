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
            _ = start_cowboy(),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    %% Stop Cowboy
    _ = cowboy:stop_listener(a2a_http_listener),
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

start_cowboy() ->
    %% Get configuration with fallback for testing
    Port = get_available_port(application:get_env(a2a_erl, port, 8080)),

    %% Define routes
    Dispatch = cowboy_router:compile([
        {'_', [
            %% Health check endpoints (must be first for performance)
            {"/health", a2a_health_handler, []},
            {"/health/ready", a2a_health_handler, []},
            {"/health/live", a2a_health_handler, []},
            {"/health/degraded", a2a_health_handler, []},
            {"/metrics", a2a_health_handler, []},

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

    %% Start HTTP listener with retry on port conflict
    start_cowboy_listener(Port, Dispatch, 5).

start_cowboy_listener(Port, Dispatch, Retries) when Retries > 0 ->
    case cowboy:start_clear(
        a2a_http_listener,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ) of
        {ok, _} ->
            logger:info("A2A server started on port ~p", [Port]),
            ok;
        {error, {eaddrinuse, _}} ->
            logger:warning("Port ~p in use, trying next port", [Port]),
            NewPort = Port + 1,
            start_cowboy_listener(NewPort, Dispatch, Retries - 1);
        {error, Reason} ->
            {error, Reason}
    end;

start_cowboy_listener(_, _, _) ->
    {error, no_available_ports}.

%% Get an available port, with fallback to testing ports
get_available_port(DefaultPort) ->
    %% Check if DEFAULT_PORT is available
    case gen_udp:open(0, [{ip, {127,0,0,1}}, {port, DefaultPort}]) of
        {ok, Socket} ->
            gen_udp:close(Socket),
            DefaultPort;
        {error, eaddrinuse} ->
            %% Try alternative ports
            AltPorts = [18080, 18081, 18082, 18083, 18084],
            try_next_port(AltPorts);
        _ ->
            DefaultPort
    end.

try_next_port([Port | Rest]) ->
    case gen_udp:open(0, [{ip, {127,0,0,1}}, {port, Port}]) of
        {ok, Socket} ->
            gen_udp:close(Socket),
            logger:info("Using alternative port ~p", [Port]),
            Port;
        {error, eaddrinuse} ->
            try_next_port(Rest);
        _ ->
            try_next_port(Rest)
    end;

try_next_port([]) ->
    0.
