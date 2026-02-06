%%%-------------------------------------------------------------------
%%% @doc BeamAI Cowboy Route Dispatch Generator
%%%
%%% Generates Cowboy route dispatch rules that include both legacy A2A
%%% paths and new BeamAI paths. Provides a single entry point to get
%%% a complete, compiled dispatch table for Cowboy.
%%%
%%% Route Map:
%%%   /.well-known/agent-card.json -> a2a_agent_card (legacy)
%%%   /a2a                         -> a2a_http_handler (legacy)
%%%   /a2a/sse                     -> a2a_sse_handler (legacy)
%%%   /message:send                -> a2a_http_handler (legacy)
%%%   /message:stream              -> a2a_sse_handler (legacy)
%%%   /tasks/*                     -> a2a_http_handler (legacy)
%%%   /beamai/a2a                  -> beamai_a2a_http_handler (new)
%%%   /beamai/a2a/sse              -> beamai_sse_bridge (new)
%%%   /beamai/agent-card           -> beamai_a2a_http_handler (new)
%%%   /beamai/a2a/push             -> beamai_push_bridge (new)
%%%   /health                      -> combined health check
%%%
%%% Usage:
%%%   Dispatch = beamai_cowboy_routes:dispatch(),
%%%   cowboy:start_clear(Name, [{port, Port}],
%%%                      #{env => #{dispatch => Dispatch}}).
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_cowboy_routes).

%% Public API
-export([routes/0, routes/1, dispatch/0, dispatch/1]).

%% Cowboy handler callback (for health check)
-export([init/2]).

-include("a2a.hrl").

-define(DEFAULT_OPTS, #{
    enable_beamai => true,
    enable_legacy => true,
    health_check => true,
    host_match => '_',
    beamai_middleware => [],
    beamai_handler_opts => #{}
}).

%%====================================================================
%% Public API
%%====================================================================

%% @doc Get the full route list with default options.
%% Returns a list of Cowboy route tuples (not compiled).
-spec routes() -> list().
routes() ->
    routes(#{}).

%% @doc Get the full route list with custom options.
%%
%% Opts can include:
%%   enable_beamai => boolean()      - Include BeamAI routes (default: true)
%%   enable_legacy => boolean()      - Include legacy routes (default: true)
%%   health_check => boolean()       - Include health route (default: true)
%%   host_match => term()            - Cowboy host match (default: '_')
%%   beamai_middleware => [module()]  - Middleware chain for BeamAI handlers
%%   beamai_handler_opts => map()    - Extra opts for BeamAI handlers
-spec routes(map()) -> list().
routes(Opts) ->
    MergedOpts = maps:merge(?DEFAULT_OPTS, Opts),

    HealthRoutes = case maps:get(health_check, MergedOpts) of
        true -> health_routes();
        false -> []
    end,

    LegacyRoutes = case maps:get(enable_legacy, MergedOpts) of
        true -> legacy_routes();
        false -> []
    end,

    BeamAIRoutes = case maps:get(enable_beamai, MergedOpts) of
        true -> beamai_routes(MergedOpts);
        false -> []
    end,

    %% Order matters: health first, then BeamAI (more specific paths),
    %% then legacy routes
    HealthRoutes ++ BeamAIRoutes ++ LegacyRoutes.

%% @doc Get a compiled Cowboy dispatch table with default options.
%% Ready to pass directly to cowboy:start_clear/3 or cowboy:start_tls/3.
-spec dispatch() -> cowboy_router:dispatch_rules().
dispatch() ->
    dispatch(#{}).

%% @doc Get a compiled Cowboy dispatch table with custom options.
-spec dispatch(map()) -> cowboy_router:dispatch_rules().
dispatch(Opts) ->
    MergedOpts = maps:merge(?DEFAULT_OPTS, Opts),
    HostMatch = maps:get(host_match, MergedOpts),
    AllRoutes = routes(MergedOpts),
    cowboy_router:compile([{HostMatch, AllRoutes}]).

%%====================================================================
%% Cowboy Handler for Health Check
%%====================================================================

%% @doc Combined health check handler.
%% Reports health of both legacy and BeamAI systems.
-spec init(cowboy_req:req(), map() | list()) ->
    {ok, cowboy_req:req(), term()}.
init(Req0, Opts) when is_list(Opts) ->
    init(Req0, maps:from_list([{K, V} || {K, V} <- Opts]));
init(Req0, Opts) when is_map(Opts) ->
    Path = cowboy_req:path(Req0),
    Type = maps:get(type, Opts, resolve_health_type(Path)),

    Response = case Type of
        health -> combined_health_check();
        ready -> readiness_check();
        live -> liveness_check();
        degraded -> degraded_check();
        _ -> combined_health_check()
    end,

    Body = json:encode(Response),
    StatusCode = case maps:get(<<"status">>, Response, <<"unknown">>) of
        <<"healthy">> -> 200;
        <<"ready">> -> 200;
        <<"alive">> -> 200;
        <<"degraded">> -> 200;
        _ -> 503
    end,

    Req = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"access-control-allow-origin">> => <<"*">>
    }, Body, Req0),
    {ok, Req, Opts}.

%%====================================================================
%% Route Definitions
%%====================================================================

%% @private Health check routes.
health_routes() ->
    [
        {"/health", ?MODULE, #{type => health}},
        {"/health/ready", ?MODULE, #{type => ready}},
        {"/health/live", ?MODULE, #{type => live}},
        {"/health/degraded", ?MODULE, #{type => degraded}}
    ].

%% @private Legacy A2A protocol routes.
%% These mirror the routes defined in a2a_erl_app:start_cowboy/0.
legacy_routes() ->
    [
        %% Agent card discovery (RFC 8615)
        {"/.well-known/agent-card.json", a2a_http_handler, []},

        %% Core A2A JSON-RPC endpoints
        {"/a2a", a2a_http_handler, []},
        {"/message:send", a2a_http_handler, []},
        {"/message:stream", a2a_sse_handler, []},

        %% Task management
        {"/tasks", a2a_http_handler, []},
        {"/tasks/:task_id", a2a_http_handler, []},
        {"/tasks/:task_id:cancel", a2a_http_handler, []},
        {"/tasks/:task_id:subscribe", a2a_sse_handler, []},

        %% SSE streaming
        {"/a2a/sse", a2a_sse_handler, []},

        %% Push notification configuration
        {"/tasks/:task_id/pushNotificationConfigs", a2a_http_handler, []},
        {"/tasks/:task_id/pushNotificationConfigs/:config_id", a2a_http_handler, []},

        %% Extended agent card (authenticated)
        {"/extendedAgentCard", a2a_http_handler, []},

        %% Tenant-prefixed routes
        {"/:tenant/message:send", a2a_http_handler, []},
        {"/:tenant/message:stream", a2a_sse_handler, []},
        {"/:tenant/tasks", a2a_http_handler, []},
        {"/:tenant/tasks/:task_id", a2a_http_handler, []},
        {"/:tenant/tasks/:task_id:cancel", a2a_http_handler, []},
        {"/:tenant/tasks/:task_id:subscribe", a2a_sse_handler, []}
    ].

%% @private BeamAI handler routes.
beamai_routes(Opts) ->
    HandlerOpts = maps:get(beamai_handler_opts, Opts, #{}),
    Middleware = maps:get(beamai_middleware, Opts, []),

    HttpOpts = HandlerOpts#{
        callback => undefined,
        middleware => Middleware
    },

    [
        %% BeamAI agent card endpoint
        {"/beamai/agent-card", beamai_a2a_http_handler, HttpOpts},

        %% BeamAI A2A JSON-RPC endpoint (primary)
        {"/beamai/a2a", beamai_a2a_http_handler, HttpOpts},

        %% BeamAI SSE streaming endpoint
        {"/beamai/a2a/sse", beamai_sse_bridge, #{format => beamai}},

        %% BeamAI push notification management
        {"/beamai/a2a/push", beamai_push_bridge, []},
        {"/beamai/a2a/push/:endpoint_id", beamai_push_bridge, []},

        %% BeamAI task management (JSON-RPC via HTTP handler)
        {"/beamai/a2a/tasks", beamai_a2a_http_handler, HttpOpts},
        {"/beamai/a2a/tasks/:task_id", beamai_a2a_http_handler, HttpOpts},

        %% BeamAI health (BeamAI-specific health info)
        {"/beamai/health", ?MODULE, #{type => health}},

        %% BeamAI kernel info endpoint
        {"/beamai/info", beamai_a2a_http_handler, HttpOpts}
    ].

%%====================================================================
%% Health Checks
%%====================================================================

%% @private Resolve health check type from path.
resolve_health_type(<<"/health/ready">>) -> ready;
resolve_health_type(<<"/health/live">>) -> live;
resolve_health_type(<<"/health/degraded">>) -> degraded;
resolve_health_type(<<"/beamai/health">>) -> health;
resolve_health_type(_) -> health.

%% @private Combined health check covering both legacy and BeamAI systems.
combined_health_check() ->
    LegacyHealth = check_legacy_health(),
    BeamAIHealth = check_beamai_health(),

    OverallStatus = case {maps:get(<<"status">>, LegacyHealth),
                          maps:get(<<"status">>, BeamAIHealth)} of
        {<<"healthy">>, <<"healthy">>} -> <<"healthy">>;
        {<<"healthy">>, _} -> <<"degraded">>;
        {_, <<"healthy">>} -> <<"degraded">>;
        _ -> <<"unhealthy">>
    end,

    #{
        <<"status">> => OverallStatus,
        <<"timestamp">> => erlang:system_time(millisecond),
        <<"uptime">> => get_uptime_seconds(),
        <<"systems">> => #{
            <<"legacy">> => LegacyHealth,
            <<"beamai">> => BeamAIHealth
        },
        <<"erlang">> => #{
            <<"node">> => atom_to_binary(node(), utf8),
            <<"process_count">> => erlang:system_info(process_count),
            <<"otp_release">> => list_to_binary(erlang:system_info(otp_release))
        }
    }.

%% @private Readiness check.
readiness_check() ->
    LegacyReady = check_legacy_ready(),
    BeamAIReady = check_beamai_ready(),

    Status = case LegacyReady andalso BeamAIReady of
        true -> <<"ready">>;
        false -> <<"not_ready">>
    end,

    #{
        <<"status">> => Status,
        <<"timestamp">> => erlang:system_time(millisecond),
        <<"checks">> => #{
            <<"legacy">> => LegacyReady,
            <<"beamai">> => BeamAIReady
        }
    }.

%% @private Liveness check.
liveness_check() ->
    #{
        <<"status">> => <<"alive">>,
        <<"timestamp">> => erlang:system_time(millisecond),
        <<"pid">> => list_to_binary(pid_to_list(self()))
    }.

%% @private Degraded check - report degraded components.
degraded_check() ->
    LegacyHealth = check_legacy_health(),
    BeamAIHealth = check_beamai_health(),

    DegradedComponents = lists:filter(
        fun({_Name, Health}) ->
            maps:get(<<"status">>, Health) =/= <<"healthy">>
        end,
        [{<<"legacy">>, LegacyHealth}, {<<"beamai">>, BeamAIHealth}]
    ),

    Status = case DegradedComponents of
        [] -> <<"healthy">>;
        _ -> <<"degraded">>
    end,

    #{
        <<"status">> => Status,
        <<"timestamp">> => erlang:system_time(millisecond),
        <<"degraded_components">> => maps:from_list(DegradedComponents)
    }.

%%====================================================================
%% Component Health Checks
%%====================================================================

%% @private Check health of the legacy A2A system.
check_legacy_health() ->
    Checks = [
        {<<"a2a_agent_card">>, is_process_alive(whereis(a2a_agent_card))},
        {<<"a2a_task_store">>, is_process_alive(whereis(a2a_task_store))}
    ],

    AllHealthy = lists:all(fun({_, V}) -> V end, Checks),

    #{
        <<"status">> => case AllHealthy of true -> <<"healthy">>; false -> <<"unhealthy">> end,
        <<"components">> => maps:from_list(Checks)
    }.

%% @private Check health of the BeamAI system.
check_beamai_health() ->
    Checks = [
        {<<"beamai_kernel">>, is_process_alive(whereis(beamai_kernel))},
        {<<"beamai_http_bridge">>, is_process_alive(whereis(beamai_http_bridge))},
        {<<"beamai_push_bridge">>, is_process_alive(whereis(beamai_push_bridge))}
    ],

    AllHealthy = lists:all(fun({_, V}) -> V end, Checks),

    #{
        <<"status">> => case AllHealthy of true -> <<"healthy">>; false -> <<"unhealthy">> end,
        <<"components">> => maps:from_list(Checks)
    }.

%% @private Check if the legacy system is ready to accept traffic.
check_legacy_ready() ->
    is_process_alive(whereis(a2a_agent_card)).

%% @private Check if the BeamAI system is ready to accept traffic.
check_beamai_ready() ->
    is_process_alive(whereis(beamai_kernel)).

%%====================================================================
%% Utility Functions
%%====================================================================

%% @private Get uptime in seconds.
get_uptime_seconds() ->
    case erlang:statistics(wall_clock) of
        {UpTimeMs, _} -> UpTimeMs div 1000;
        _ -> 0
    end.

%% @private Check if a pid is alive, handling undefined.
is_process_alive(undefined) -> false;
is_process_alive(Pid) when is_pid(Pid) ->
    erlang:is_process_alive(Pid);
is_process_alive(_) -> false.
