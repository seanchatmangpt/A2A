%%% @doc Cowboy dispatch route generator
%%%
%%% Pure function module that generates Cowboy dispatch rules for both
%%% legacy A2A paths (/.well-known/agent-card.json, /a2a, /tasks, etc.)
%%% and beamai paths (/beamai/a2a, /beamai/agent-card, etc.).
%%% Returns routes suitable for cowboy_router:compile/1.
-module(beamai_cowboy_routes).

-include_lib("beamai_core/include/beamai_common.hrl").

-export([routes/0, routes/1, dispatch/0]).

%% @doc Generate default routes for all handlers.
-spec routes() -> list().
routes() ->
    routes(#{}).

%% @doc Generate routes with optional overrides.
%% Supported Opts keys:
%%   host   - Cowboy host match pattern (default '_')
%%   legacy - include legacy routes (default true)
%%   beamai - include beamai routes (default true)
-spec routes(map()) -> list().
routes(Opts) ->
    Host = maps:get(host, Opts, '_'),
    IncludeLegacy = maps:get(legacy, Opts, true),
    IncludeBeamai = maps:get(beamai, Opts, true),
    LegacyRoutes = case IncludeLegacy of
        true -> legacy_routes();
        false -> []
    end,
    BeamaiRoutes = case IncludeBeamai of
        true -> beamai_routes();
        false -> []
    end,
    [{Host, LegacyRoutes ++ BeamaiRoutes}].

%% @doc Generate a compiled Cowboy dispatch table ready for use.
%% Equivalent to cowboy_router:compile(routes()).
-spec dispatch() -> cowboy_router:dispatch_rules().
dispatch() ->
    cowboy_router:compile(routes()).

%%% Internal

%% Legacy A2A protocol routes
legacy_routes() ->
    [{<<"/.well-known/agent-card.json">>, a2a_http_handler, []},
     {<<"/a2a">>, a2a_http_handler, []},
     {<<"/message:send">>, a2a_http_handler, []},
     {<<"/message:stream">>, a2a_sse_handler, []},
     {<<"/tasks/:task_id">>, a2a_http_handler, []},
     {<<"/tasks/:task_id/:action">>, a2a_http_handler, []},
     {<<"/tasks">>, a2a_http_handler, []},
     {<<"/health">>, a2a_health_handler, []}].

%% Beamai A2A routes using beamai_a2a_cowboy_handler
beamai_routes() ->
    [{<<"/beamai/a2a">>, beamai_a2a_cowboy_handler, []},
     {<<"/beamai/agent-card">>, beamai_a2a_cowboy_handler, []},
     {<<"/beamai/tasks">>, beamai_a2a_cowboy_handler, []},
     {<<"/beamai/tasks/:task_id">>, beamai_a2a_cowboy_handler, []},
     {<<"/beamai/tasks/:task_id/:action">>, beamai_a2a_cowboy_handler, []},
     {<<"/beamai/tasks/:task_id/stream">>, beamai_sse_bridge,
      [{format, beamai}]},
     {<<"/beamai/health">>, a2a_health_handler, []}].
