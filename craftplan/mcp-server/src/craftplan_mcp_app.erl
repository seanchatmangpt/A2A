%%% @doc Craftplan MCP Server Application
%%% Implements MCP (Model Context Protocol) server for AI tool integration

-module(craftplan_mcp_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% Application Callbacks
%%====================================================================

start(_StartType, _StartArgs) ->
    %% Start security subsystems first
    case start_security_subsystems() of
        ok ->
            craftplan_mcp_sup:start_link();
        {error, Reason} ->
            {error, Reason}
    end.

stop(_State) ->
    %% Stop security subsystems
    stop_security_subsystems(),
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

start_security_subsystems() ->
    %% Start authentication system
    case security_auth_sup:start_link() of
        {ok, _} -> ok;
        {error, _} = Error -> Error
    end,

    %% Start security monitoring
    case security_monitor_sup:start_link() of
        {ok, _} -> ok;
        {error, _} = Error -> Error
    end,

    %% Initialize security components
    initialize_security(),

    ok.

stop_security_subsystems() ->
    %% Stop authentication system
    case whereis(security_auth_sup) of
        undefined -> ok;
        _ -> security_auth_sup:stop()
    end,

    %% Stop security monitoring
    case whereis(security_monitor_sup) of
        undefined -> ok;
        _ -> security_monitor_sup:stop()
    end,

    ok.

initialize_security() ->
    %% Set up initial security configuration
    application:set_env(craftplan_mcp, jwt_secret, crypto:strong_rand_bytes(32)),
    application:set_env(craftplan_mcp, max_sessions_per_user, 10),
    application:set_env(craftplan_mcp, rate_limit_window, 60000), % 1 minute
    application:set_env(craftplan_mcp, rate_limit_requests, 1000), % 1000 requests per minute

    %% Log system startup
    security_monitor:log_security_event(#{
        severity => info,
        action => "system_startup",
        details => #{components => ["auth", "monitoring"]}
    }, "system_event"),

    %% Initialize admin user
    case security_auth:authenticate(<<"admin">>, <<"admin_password">>) of
        {ok, _} ->
            io:format("Security system initialized with admin user~n");
        {error, invalid_credentials} ->
            io:format("Admin user not found - security initialization may have issues~n")
    end.