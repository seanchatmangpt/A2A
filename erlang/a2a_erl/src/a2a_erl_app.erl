%%% @doc A2A Erlang Application
%%%
%%% This is the main OTP application module for the A2A protocol implementation.
%%% It starts the supervisor which manages all the A2A services and YAWL workflow engine.
%%%
%%% ## Supervision Hierarchy
%%%
%%% ```
%%% a2a_erl_sup (one_for_one)
%%% ├── yawl_persistence          - Mnesia-based workflow storage
%%% ├── a2a_task_store            - ETS-backed task storage
%%% ├── yawl_events               - Observer pattern for workflow events
%%% ├── yawl_service_registry     - Service discovery and registration
%%% ├── yawl_resource_manager     - Dynamic resource allocation
%%% ├── yawl_orchestrator         - Workflow lifecycle management
%%% ├── yawl_metrics              - Metrics collection
%%% ├── yawl_error_recovery       - Error recovery strategies
%%% ├── yawl_human_task           - Human-in-the-loop tasks
%%% ├── yawl_workitem_processor   - Work item processing
%%% ├── a2a_agent_card            - Agent card management
%%% ├── yawl_a2a_bridge           - YAWL-A2A protocol bridge
%%% ├── yawl_a2a_events           - A2A event notifications
%%% ├── yawl_a2a_resource_integration - Resource integration
%%% ├── y_combinator_logger       - Demo logging and telemetry
%%% ├── yawl_workflow_instance_sup (simple_one_for_one)
%%% │   └── [workflow_instance_1, workflow_instance_2, ...]
%%% └── a2a_task_sup (simple_one_for_one)
%%%     └── [task_state_1, task_state_2, ...]
%%% '''
%%%
%%% ## Application Startup Sequence
%%%
%%% 1. Mnesia schema is created (if needed)
%%% 2. Mnesia is started and tables are initialized
%%% 3. Core services start (persistence, task store)
%%% 4. YAWL services start (events, orchestrator, resource manager)
%%% 5. HTTP server starts
%%%
%%% @end
-module(a2a_erl_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%% ============================================================================
%%% Application Callbacks
%%% ============================================================================

%% @doc Start the A2A application.
%%
%% Initializes Mnesia, starts the supervision tree, and starts the HTTP server.
start(_StartType, _StartArgs) ->
    %% Initialize Mnesia first - required for YAWL persistence
    case initialize_mnesia() of
        ok ->
            %% Start inets for httpc (push notifications)
            case inets:start() of
                ok -> ok;
                {error, {already_started, inets}} -> ok
            end,

            %% Start the supervisor
            case a2a_erl_sup:start_link() of
                {ok, Pid} ->
                    %% Wait for Mnesia tables to be ready
                    case yawl_persistence:wait_for_tables() of
                        ok ->
                            logger:info("Mnesia tables ready for YAWL persistence"),
                            ok;
                        {timeout, Tables} ->
                            logger:warning("Mnesia table wait timeout, tables may not be ready: ~p", [Tables]),
                            ok
                    end,

                    %% Start Cowboy HTTP server
                    _ = start_cowboy(),
                    logger:info("A2A application started successfully"),
                    {ok, Pid};
                Error ->
                    logger:error("Failed to start A2A supervisor: ~p", [Error]),
                    Error
            end;
        {error, Reason} ->
            logger:error("Failed to initialize Mnesia: ~p", [Reason]),
            {error, {mnesia_init_failed, Reason}}
    end.

%% @doc Stop the A2A application.
%%
%% Performs graceful shutdown of all services.
stop(_State) ->
    logger:info("Stopping A2A application"),

    %% Stop Cowboy HTTP listener
    _ = cowboy:stop_listener(a2a_http_listener),

    %% Mnesia will be stopped by the persistence supervisor
    logger:info("A2A application stopped"),
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @private
%% @doc Initialize Mnesia for YAWL persistence.
%%
%% Creates the Mnesia schema on this node if it doesn't exist.
%% Note: Tables are created by the yawl_persistence gen_server during init.
initialize_mnesia() ->
    case mnesia:system_info(is_running) of
        yes ->
            logger:info("Mnesia is already running"),
            ok;
        no ->
            logger:info("Initializing Mnesia for YAWL persistence"),
            case yawl_persistence:create_schema() of
                ok ->
                    logger:info("Mnesia schema created successfully"),
                    ok;
                {error, {already_exists, _}} ->
                    logger:info("Mnesia schema already exists"),
                    ok;
                {error, Reason} ->
                    logger:error("Failed to create Mnesia schema: ~p", [Reason]),
                    {error, Reason}
            end
    end.

%% @private
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
