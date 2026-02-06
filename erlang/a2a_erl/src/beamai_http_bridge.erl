%%%-------------------------------------------------------------------
%%% @doc BeamAI HTTP Bridge
%%%
%%% Bridges existing a2a_http_handler routes with BeamAI HTTP handlers.
%%% Supports running both simultaneously for gradual migration using
%%% feature flags.
%%%
%%% Route Management:
%%%   - Legacy routes (/a2a, /tasks, /message:send, etc.) are forwarded
%%%     to a2a_http_handler
%%%   - BeamAI routes (/beamai/*) are forwarded to BeamAI handlers
%%%   - Feature flags control which handler processes shared paths
%%%
%%% Usage:
%%%   {ok, _} = beamai_http_bridge:start_link(),
%%%   ok = beamai_http_bridge:configure_routes(#{enable_beamai => true}),
%%%   Routes = beamai_http_bridge:get_routes().
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_http_bridge).
-behaviour(gen_server).

%% Bridges existing a2a_http_handler routes with BeamAI HTTP handlers
%% Supports running both simultaneously for gradual migration

%% Public API
-export([start_link/0, configure_routes/1, get_routes/0, add_beamai_routes/1]).

%% Route introspection and migration helpers
-export([
    is_beamai_route/1,
    get_handler_for_path/1,
    set_feature_flag/2,
    get_feature_flag/1,
    get_feature_flags/0,
    migration_status/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Cowboy handler callback (used as the front-door router)
-export([cowboy_init/2]).

-include("a2a.hrl").

-record(state, {
    legacy_routes = [] :: list(),
    beamai_routes = [] :: list(),
    feature_flags = #{} :: map(),
    route_cache = #{} :: map(),
    listeners = [] :: [pid()]
}).

-define(SERVER, ?MODULE).
-define(DEFAULT_FLAGS, #{
    enable_beamai => false,
    beamai_jsonrpc => false,
    beamai_sse => false,
    beamai_push => false,
    shadow_mode => false,
    log_routing => true
}).

%%====================================================================
%% Public API
%%====================================================================

%% @doc Start the HTTP bridge gen_server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Configure routes with the given options.
%% Options include feature flags and custom route definitions.
%%
%% Supported options:
%%   enable_beamai => boolean()  - Enable BeamAI route handling
%%   beamai_jsonrpc => boolean() - Enable BeamAI JSON-RPC endpoint
%%   beamai_sse => boolean()     - Enable BeamAI SSE endpoint
%%   beamai_push => boolean()    - Enable BeamAI push notifications
%%   shadow_mode => boolean()    - Mirror requests to BeamAI without
%%                                 using results
%%   log_routing => boolean()    - Log route decisions
%%   custom_routes => list()     - Additional custom Cowboy routes
-spec configure_routes(map()) -> ok | {error, term()}.
configure_routes(Opts) ->
    gen_server:call(?SERVER, {configure_routes, Opts}).

%% @doc Get the current combined route table (legacy + beamai).
%% Returns a list of Cowboy route tuples ready for cowboy_router:compile.
-spec get_routes() -> list().
get_routes() ->
    gen_server:call(?SERVER, get_routes).

%% @doc Add new BeamAI routes dynamically.
%% Routes is a list of {Path, Handler, HandlerOpts} tuples.
-spec add_beamai_routes(list()) -> ok.
add_beamai_routes(Routes) ->
    gen_server:call(?SERVER, {add_beamai_routes, Routes}).

%% @doc Check if a given path should be routed to a BeamAI handler.
-spec is_beamai_route(binary()) -> boolean().
is_beamai_route(Path) ->
    gen_server:call(?SERVER, {is_beamai_route, Path}).

%% @doc Get the handler module for a given path.
%% Returns {legacy, Module} or {beamai, Module}.
-spec get_handler_for_path(binary()) -> {legacy | beamai, module()} | not_found.
get_handler_for_path(Path) ->
    gen_server:call(?SERVER, {get_handler_for_path, Path}).

%% @doc Set a single feature flag.
-spec set_feature_flag(atom(), term()) -> ok.
set_feature_flag(Flag, Value) ->
    gen_server:call(?SERVER, {set_feature_flag, Flag, Value}).

%% @doc Get a single feature flag value.
-spec get_feature_flag(atom()) -> term().
get_feature_flag(Flag) ->
    gen_server:call(?SERVER, {get_feature_flag, Flag}).

%% @doc Get all feature flags.
-spec get_feature_flags() -> map().
get_feature_flags() ->
    gen_server:call(?SERVER, get_feature_flags).

%% @doc Get migration status report.
-spec migration_status() -> map().
migration_status() ->
    gen_server:call(?SERVER, migration_status).

%%====================================================================
%% Cowboy Front-Door Handler
%%====================================================================

%% @doc Cowboy init callback used when this module is the front-door
%% router. Inspects the request path and feature flags, then delegates
%% to the appropriate handler (legacy or BeamAI).
-spec cowboy_init(cowboy_req:req(), list()) -> term().
cowboy_init(Req0, Opts) ->
    Path = cowboy_req:path(Req0),
    Method = cowboy_req:method(Req0),

    %% Determine which handler to use
    {HandlerType, HandlerModule} = resolve_handler(Path, Method),

    %% Log routing decision if enabled
    case get_flag_from_opts(log_routing, Opts) of
        true ->
            logger:debug("BeamAI bridge routing ~s ~s -> ~p (~p)",
                         [Method, Path, HandlerModule, HandlerType]);
        false ->
            ok
    end,

    %% Handle shadow mode: send to both but only use legacy result
    case get_flag_from_opts(shadow_mode, Opts) of
        true when HandlerType =:= legacy ->
            %% In shadow mode, also send to BeamAI asynchronously
            spawn(fun() ->
                try
                    shadow_request(Path, Method, Req0)
                catch
                    _:ShadowErr ->
                        logger:warning("Shadow request failed: ~p", [ShadowErr])
                end
            end);
        _ ->
            ok
    end,

    %% Delegate to the resolved handler
    HandlerModule:init(Req0, handler_opts(HandlerType, Opts)).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    %% Load feature flags from application environment
    EnvFlags = application:get_env(a2a_erl, beamai_feature_flags, #{}),
    Flags = maps:merge(?DEFAULT_FLAGS, EnvFlags),

    %% Build initial route tables
    LegacyRoutes = build_legacy_routes(),
    BeamAIRoutes = build_beamai_routes(Flags),

    State = #state{
        legacy_routes = LegacyRoutes,
        beamai_routes = BeamAIRoutes,
        feature_flags = Flags,
        route_cache = build_route_cache(LegacyRoutes, BeamAIRoutes)
    },

    logger:info("BeamAI HTTP bridge started with flags: ~p", [Flags]),
    {ok, State}.

handle_call({configure_routes, Opts}, _From, State) ->
    NewFlags = maps:merge(State#state.feature_flags, Opts),
    NewBeamAIRoutes = case maps:get(custom_routes, Opts, undefined) of
        undefined -> build_beamai_routes(NewFlags);
        CustomRoutes -> CustomRoutes ++ build_beamai_routes(NewFlags)
    end,
    NewState = State#state{
        feature_flags = NewFlags,
        beamai_routes = NewBeamAIRoutes,
        route_cache = build_route_cache(State#state.legacy_routes, NewBeamAIRoutes)
    },
    %% Notify listeners of route change
    notify_listeners(route_change, NewState),
    {reply, ok, NewState};

handle_call(get_routes, _From, State) ->
    Routes = merge_routes(State),
    {reply, Routes, State};

handle_call({add_beamai_routes, NewRoutes}, _From, State) ->
    UpdatedRoutes = NewRoutes ++ State#state.beamai_routes,
    NewState = State#state{
        beamai_routes = UpdatedRoutes,
        route_cache = build_route_cache(State#state.legacy_routes, UpdatedRoutes)
    },
    notify_listeners(route_change, NewState),
    {reply, ok, NewState};

handle_call({is_beamai_route, Path}, _From, State) ->
    Result = is_beamai_path(Path) andalso
             maps:get(enable_beamai, State#state.feature_flags, false),
    {reply, Result, State};

handle_call({get_handler_for_path, Path}, _From, State) ->
    Result = case maps:get(Path, State#state.route_cache, undefined) of
        undefined -> not_found;
        Handler -> Handler
    end,
    {reply, Result, State};

handle_call({set_feature_flag, Flag, Value}, _From, State) ->
    NewFlags = maps:put(Flag, Value, State#state.feature_flags),
    NewBeamAIRoutes = build_beamai_routes(NewFlags),
    NewState = State#state{
        feature_flags = NewFlags,
        beamai_routes = NewBeamAIRoutes,
        route_cache = build_route_cache(State#state.legacy_routes, NewBeamAIRoutes)
    },
    logger:info("BeamAI feature flag ~p set to ~p", [Flag, Value]),
    {reply, ok, NewState};

handle_call({get_feature_flag, Flag}, _From, State) ->
    Value = maps:get(Flag, State#state.feature_flags, undefined),
    {reply, Value, State};

handle_call(get_feature_flags, _From, State) ->
    {reply, State#state.feature_flags, State};

handle_call(migration_status, _From, State) ->
    Status = #{
        legacy_route_count => length(State#state.legacy_routes),
        beamai_route_count => length(State#state.beamai_routes),
        feature_flags => State#state.feature_flags,
        beamai_enabled => maps:get(enable_beamai, State#state.feature_flags, false),
        shadow_mode => maps:get(shadow_mode, State#state.feature_flags, false),
        cached_routes => maps:size(State#state.route_cache)
    },
    {reply, Status, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({register_listener, Pid}, State) ->
    MonRef = erlang:monitor(process, Pid),
    {noreply, State#state{listeners = [{Pid, MonRef} | State#state.listeners]}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', MonRef, process, Pid, _Reason}, State) ->
    NewListeners = lists:filter(
        fun({P, R}) -> P =/= Pid andalso R =/= MonRef end,
        State#state.listeners
    ),
    {noreply, State#state{listeners = NewListeners}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    logger:info("BeamAI HTTP bridge stopping"),
    ok.

%%====================================================================
%% Route Building
%%====================================================================

%% @private Build the legacy route table from existing A2A handler configuration.
build_legacy_routes() ->
    [
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
        {"/extendedAgentCard", a2a_http_handler, []}
    ].

%% @private Build the BeamAI route table based on feature flags.
build_beamai_routes(Flags) ->
    BaseRoutes = case maps:get(enable_beamai, Flags, false) of
        true ->
            [
                %% BeamAI agent card endpoint
                {"/beamai/agent-card", beamai_a2a_http_handler,
                 #{callback => undefined}},
                %% BeamAI health check
                {"/beamai/health", beamai_a2a_http_handler,
                 #{callback => undefined}}
            ];
        false ->
            []
    end,

    JsonRpcRoutes = case maps:get(beamai_jsonrpc, Flags, false) of
        true ->
            [
                %% BeamAI A2A JSON-RPC endpoint
                {"/beamai/a2a", beamai_a2a_http_handler,
                 #{callback => undefined}}
            ];
        false ->
            []
    end,

    SseRoutes = case maps:get(beamai_sse, Flags, false) of
        true ->
            [
                %% BeamAI SSE streaming endpoint
                {"/beamai/a2a/sse", beamai_sse_bridge, []}
            ];
        false ->
            []
    end,

    PushRoutes = case maps:get(beamai_push, Flags, false) of
        true ->
            [
                %% BeamAI push notification endpoint
                {"/beamai/a2a/push", beamai_push_bridge, []}
            ];
        false ->
            []
    end,

    BaseRoutes ++ JsonRpcRoutes ++ SseRoutes ++ PushRoutes.

%% @private Merge legacy and beamai routes into a single route list
%% suitable for cowboy_router:compile.
merge_routes(#state{legacy_routes = Legacy, beamai_routes = BeamAI,
                    feature_flags = Flags}) ->
    %% Health check that covers both systems
    HealthRoute = {"/health", beamai_cowboy_routes, #{type => health}},

    %% Combine: health first, then BeamAI (more specific), then legacy
    AllRoutes = case maps:get(enable_beamai, Flags, false) of
        true -> [HealthRoute | BeamAI] ++ Legacy;
        false -> [HealthRoute | Legacy]
    end,

    AllRoutes.

%% @private Build a cache mapping paths to their handler type and module.
build_route_cache(LegacyRoutes, BeamAIRoutes) ->
    LegacyCache = lists:foldl(fun({Path, Mod, _Opts}, Acc) ->
        maps:put(list_to_binary(Path), {legacy, Mod}, Acc)
    end, #{}, LegacyRoutes),

    lists:foldl(fun({Path, Mod, _Opts}, Acc) ->
        maps:put(list_to_binary(Path), {beamai, Mod}, Acc)
    end, LegacyCache, BeamAIRoutes).

%%====================================================================
%% Route Resolution
%%====================================================================

%% @private Resolve which handler should process a given request.
resolve_handler(Path, _Method) ->
    case is_beamai_path(Path) of
        true ->
            resolve_beamai_handler(Path);
        false ->
            resolve_legacy_handler(Path)
    end.

%% @private Check if a path belongs to BeamAI namespace.
is_beamai_path(<<"/beamai/", _/binary>>) -> true;
is_beamai_path(_) -> false.

%% @private Resolve to the appropriate BeamAI handler.
resolve_beamai_handler(<<"/beamai/a2a/sse", _/binary>>) ->
    {beamai, beamai_sse_bridge};
resolve_beamai_handler(<<"/beamai/a2a/push", _/binary>>) ->
    {beamai, beamai_push_bridge};
resolve_beamai_handler(<<"/beamai/a2a", _/binary>>) ->
    {beamai, beamai_a2a_http_handler};
resolve_beamai_handler(<<"/beamai/agent-card", _/binary>>) ->
    {beamai, beamai_a2a_http_handler};
resolve_beamai_handler(<<"/beamai/health", _/binary>>) ->
    {beamai, beamai_a2a_http_handler};
resolve_beamai_handler(_) ->
    {beamai, beamai_a2a_http_handler}.

%% @private Resolve to the appropriate legacy handler.
resolve_legacy_handler(<<"/message:stream", _/binary>>) ->
    {legacy, a2a_sse_handler};
resolve_legacy_handler(<<"/tasks/", Rest/binary>>) ->
    case binary:match(Rest, <<":subscribe">>) of
        {_, _} -> {legacy, a2a_sse_handler};
        nomatch -> {legacy, a2a_http_handler}
    end;
resolve_legacy_handler(_) ->
    {legacy, a2a_http_handler}.

%% @private Get handler options based on handler type.
handler_opts(legacy, _Opts) -> [];
handler_opts(beamai, Opts) ->
    #{callback => undefined,
      middleware => proplists:get_value(middleware, Opts, [])}.

%%====================================================================
%% Shadow Mode
%%====================================================================

%% @private Send a shadow request to BeamAI for comparison/testing.
%% The result is logged but not used.
shadow_request(Path, Method, _Req) ->
    logger:debug("Shadow request to BeamAI: ~s ~s", [Method, Path]),
    %% In a full implementation, this would forward the request body
    %% to the BeamAI handler and log/compare the results.
    ok.

%%====================================================================
%% Utility Functions
%%====================================================================

%% @private Get a feature flag value from the init opts (for cowboy_init).
get_flag_from_opts(Flag, Opts) when is_list(Opts) ->
    proplists:get_value(Flag, Opts, maps:get(Flag, ?DEFAULT_FLAGS, false));
get_flag_from_opts(Flag, Opts) when is_map(Opts) ->
    maps:get(Flag, Opts, maps:get(Flag, ?DEFAULT_FLAGS, false));
get_flag_from_opts(_Flag, _Opts) ->
    false.

%% @private Notify all registered listeners of a route change.
notify_listeners(Event, #state{listeners = Listeners}) ->
    lists:foreach(fun({Pid, _MonRef}) ->
        Pid ! {beamai_bridge_event, Event}
    end, Listeners).
