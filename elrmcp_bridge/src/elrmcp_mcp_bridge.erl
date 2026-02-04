%%% @doc elrmcp MCP Bridge
%%% Bridges elrmcp to Craftplan MCP server with dynamic tool registration
%%% and request forwarding capabilities

-module(elrmcp_mcp_bridge).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([initialize_craftplan/0, register_tools/0, forward_request/2]).
-export([list_available_tools/0, get_tool_info/1, call_tool/2]).
-export([configure_bridge/1, get_bridge_status/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_CRAFTPLAN_URL, "http://localhost:8090").
-define(DEFAULT_TIMEOUT, 30000).
-define(DEFAULT_RATE_LIMIT, 100).

%% Bridge configuration
-record(config, {
    craftplan_url :: binary(),
    timeout :: integer(),
    rate_limit :: integer(),
    tool_whitelist :: [binary()],
    tool_blacklist :: [binary()],
    enable_caching :: boolean(),
    cache_ttl :: integer(),
    auth_token :: binary() | undefined
}).

%% Bridge state
-record(state, {
    config :: #config{},
    craftplan_client :: pid() | undefined,
    tool_registry :: map(),
    cache :: map(),
    metrics :: map(),
    rate_limiter :: pid() | undefined
}).

-type tool_info() :: #{
    name := binary(),
    description := binary(),
    input_schema := map(),
    output_schema => map(),
    category => binary(),
    version => binary()
}.

-type request_result() :: {ok, map()} | {error, term()}.

%%====================================================================
%% API
%%====================================================================

%% @doc Start the bridge server
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Stop the bridge server
stop() ->
    gen_server:stop(?SERVER).

%% @doc Initialize Craftplan MCP connection
-spec initialize_craftplan() -> ok | {error, term()}.
initialize_craftplan() ->
    gen_server:call(?SERVER, initialize_craftplan).

%% @doc Register all available tools from Craftplan MCP
-spec register_tools() -> ok | {error, term()}.
register_tools() ->
    gen_server:call(?SERVER, register_tools).

%% @doc Forward a request to Craftplan MCP
-spec forward_request(binary(), map()) -> request_result().
forward_request(ToolName, Args) ->
    gen_server:call(?SERVER, {forward_request, ToolName, Args}, ?DEFAULT_TIMEOUT).

%% @doc List all available tools (both elrmcp and bridged Craftplan tools)
-spec list_available_tools() -> {ok, [tool_info()]}.
list_available_tools() ->
    gen_server:call(?SERVER, list_available_tools).

%% @doc Get detailed information about a specific tool
-spec get_tool_info(binary()) -> {ok, tool_info()} | {error, not_found}.
get_tool_info(ToolName) ->
    gen_server:call(?SERVER, {get_tool_info, ToolName}).

%% @doc Call a tool directly through the bridge
-spec call_tool(binary(), map()) -> request_result().
call_tool(ToolName, Args) ->
    gen_server:call(?SERVER, {call_tool, ToolName, Args}, ?DEFAULT_TIMEOUT).

%% @doc Configure bridge settings
-spec configure_bridge(map()) -> ok | {error, term()}.
configure_bridge(Config) ->
    gen_server:call(?SERVER, {configure_bridge, Config}).

%% @doc Get bridge status and metrics
-spec get_bridge_status() -> {ok, map()}.
get_bridge_status() ->
    gen_server:call(?SERVER, get_bridge_status).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    %% Initialize default configuration
    DefaultConfig = #config{
        craftplan_url = ?DEFAULT_CRAFTPLAN_URL,
        timeout = ?DEFAULT_TIMEOUT,
        rate_limit = ?DEFAULT_RATE_LIMIT,
        tool_whitelist = [],
        tool_blacklist = [],
        enable_caching = true,
        cache_ttl = 300000,  % 5 minutes
        auth_token = undefined
    },

    State = #state{
        config = DefaultConfig,
        craftplan_client = undefined,
        tool_registry = #{},
        cache = #{},
        metrics = #{total_requests => 0, successful_requests => 0, failed_requests => 0},
        rate_limiter = undefined
    },

    %% Auto-initialize on startup
    {ok, State1} = handle_call(initialize_craftplan, undefined, State),
    {ok, State2} = handle_call(register_tools, undefined, State1),

    %% Start rate limiter if enabled
    case DefaultConfig#config.rate_limit > 0 of
        true ->
            ok = start_rate_limiter();
        false ->
            ok
    end,

    io:format("elrmcp MCP Bridge initialized~n"),
    {ok, State2}.

handle_call(initialize_craftplan, _From, State) ->
    try
        Config = State#state.config,

        %% Start Craftplan MCP HTTP client
        {ok, ClientPid} = start_craftplan_client(Config#config.craftplan_url),

        %% Initialize tools registry
        ToolRegistry = initialize_tool_registry(),

        io:format("Craftplan MCP client initialized at ~s~n", [Config#config.craftplan_url]),

        {reply, ok, State#state{
            craftplan_client = ClientPid,
            tool_registry = ToolRegistry
        }}
    catch
        Error:Reason ->
            io:format("Failed to initialize Craftplan MCP: ~p:~p~n", [Error, Reason]),
            {reply, {error, {initialization_failed, {Error, Reason}}}, State}
    end;

handle_call(register_tools, _From, State) ->
    try
        Config = State#state.config,
        ClientPid = State#state.craftplan_client,

        %% Get tools list from Craftplan MCP
        case fetch_craftplan_tools(ClientPid) of
            {ok, CraftplanTools} ->
                %% Filter tools based on whitelist/blacklist
                FilteredTools = filter_tools(CraftplanTools, Config),

                %% Register tools in local registry
                ToolRegistry = register_tools_in_registry(FilteredTools, State#state.tool_registry),

                io:format("Registered ~p Craftplan tools~n", [maps:size(ToolRegistry)]),

                {reply, ok, State#state{tool_registry = ToolRegistry}};
            {error, Reason} ->
                io:format("Failed to register Craftplan tools: ~p~n", [Reason]),
                {reply, {error, {tool_registration_failed, Reason}}, State}
        end
    catch
        Error:Reason ->
            io:format("Error registering tools: ~p:~p~n", [Error, Reason]),
            {reply, {error, {tool_registration_error, {Error, Reason}}}, State}
    end;

handle_call({forward_request, ToolName, Args}, _From, State) ->
    Metrics = State#state.metrics,
    NewMetrics = Metrics#{total_requests => Metrics#{total_requests} + 1},

    try
        %% Check rate limiting
        case check_rate_limit(State) of
            allowed ->
                Result = forward_to_craftplan(ToolName, Args, State),
                case Result of
                    {ok, _} ->
                        NewMetrics1 = NewMetrics#{successful_requests => NewMetrics#{successful_requests} + 1},
                        {reply, Result, State#state{metrics = NewMetrics1}};
                    {error, _} ->
                        NewMetrics1 = NewMetrics#{failed_requests => NewMetrics#{failed_requests} + 1},
                        {reply, Result, State#state{metrics = NewMetrics1}}
                end;
            denied ->
                Error = {error, {rate_limited, "Too many requests"}},
                NewMetrics1 = NewMetrics#{failed_requests => NewMetrics#{failed_requests} + 1},
                {reply, Error, State#state{metrics = NewMetrics1}}
        end
    catch
        Error:Reason ->
            NewMetrics1 = NewMetrics#{failed_requests => NewMetrics#{failed_requests} + 1},
            io:format("Error forwarding request: ~p:~p~n", [Error, Reason]),
            {reply, {error, {forward_error, {Error, Reason}}}, State#state{metrics = NewMetrics1}}
    end;

handle_call(list_available_tools, _From, State) ->
    Tools = maps:values(State#state.tool_registry),
    {reply, {ok, Tools}, State};

handle_call({get_tool_info, ToolName}, _From, State) ->
    case maps:get(ToolName, State#state.tool_registry, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        ToolInfo ->
            {reply, {ok, ToolInfo}, State}
    end;

handle_call({call_tool, ToolName, Args}, _From, State) ->
    Result = forward_request(ToolName, Args),
    {reply, Result, State};

handle_call({configure_bridge, ConfigMap}, _From, State) ->
    Config = State#state.config,
    NewConfig = update_config(Config, ConfigMap),
    io:format("Bridge configuration updated~n"),
    {reply, ok, State#state{config = NewConfig}};

handle_call(get_bridge_status, _From, State) ->
    Status = #{
        status => case State#state.craftplan_client of
                     undefined -> disconnected;
                     _ -> connected
                 end,
        tools_count => maps:size(State#state.tool_registry),
        metrics => State#state.metrics,
        config => format_config(State#state.config),
        cache_size => maps:size(State#state.cache),
        uptime => os:system_time(millisecond)
    },
    {reply, {ok, Status}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    %% Clean up resources
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @doc Start Craftplan HTTP client
start_craftplan_client(URL) ->
    elrmcp_mcp_client:start_link(URL).

%% @doc Initialize tools registry
initialize_tool_registry() ->
    %% Add elrmcp core tools
    #{
        <<"system_info">> => #{
            name => <<"system_info">>,
            description => <<"Get elrmcp system information">>,
            input_schema => #{
                type => object,
                properties => #{},
                required => []
            },
            category => <<"system">>,
            version => <<"1.0.0">>
        },
        <<"bridge_status">> => #{
            name => <<"bridge_status">>,
            description => <<"Get bridge status and metrics">>,
            input_schema => #{
                type => object,
                properties => #{},
                required => []
            },
            category => <<"bridge">>,
            version => <<"1.0.0">>
        }
    }.

%% @doc Fetch tools from Craftplan MCP
fetch_craftplan_tools(ClientPid) ->
    elrmcp_mcp_client:list_tools(ClientPid).

%% @doc Filter tools based on configuration
filter_tools(CraftplanTools, Config) ->
    Whitelist = Config#config.tool_whitelist,
    Blacklist = Config#config.tool_blacklist,

    lists:filter(fun(Tool) ->
        ToolName = maps:get(<<"name">>, Tool),

        %% Check blacklist first
        case lists:member(ToolName, Blacklist) of
            true ->
                false;
            false ->
                %% Check whitelist
                case Whitelist of
                    [] ->
                        true;
                    _ ->
                        lists:member(ToolName, Whitelist)
                end
        end
    end, CraftplanTools).

%% @doc Register tools in registry
register_tools_in_registry(CraftplanTools, ExistingRegistry) ->
    Tools = lists:map(fun(Tool) ->
        ToolName = maps:get(<<"name">>, Tool),
        #{
            name => ToolName,
            description => maps:get(<<"description">>, Tool),
            input_schema => maps:get(<<"inputSchema">>, Tool),
            output_schema => maps:get(<<"outputSchema">>, Tool, #{}),
            category => <<"craftplan">>,
            version => <<"1.0.0">>
        }
    end, CraftplanTools),

    maps:merge(ExistingRegistry, maps:from_list([{maps:get(<<"name">>, T), T} || T <- Tools])).

%% @doc Forward request to Craftplan MCP
forward_to_craftplan(ToolName, Args, State) ->
    Config = State#state.config,
    ClientPid = State#state.craftplan_client,

    %% Check cache
    case Config#config.enable_caching of
        true ->
            case get_from_cache(ToolName, Args) of
                {ok, CachedResult} ->
                    io:format("Cache hit for tool ~s~n", [ToolName]),
                    {ok, CachedResult};
                miss ->
                    Result = elrmcp_mcp_client:call_tool(ClientPid, ToolName, Args),
                    case Result of
                        {ok, _} ->
                            cache_result(ToolName, Args, Result);
                        Error ->
                            Error
                    end
            end;
        false ->
            elrmcp_mcp_client:call_tool(ClientPid, ToolName, Args)
    end.

%% @doc Cache management
get_from_cache(ToolName, Args) ->
    %% Implement caching logic
    miss.

cache_result(ToolName, Args, Result) ->
    %% Implement caching logic
    ok.

%% @doc Rate limiting
check_rate_limit(State) ->
    case State#state.rate_limiter of
        undefined ->
            allowed;
        LimiterPid ->
            elrmcp_rate_limiter:check(LimiterPid)
    end.

start_rate_limiter() ->
    elrmcp_rate_limiter:start_link(?DEFAULT_RATE_LIMIT).

%% @doc Configuration management
update_config(Config, ConfigMap) ->
    %% Update configuration fields from map
    %% Handle validation and defaults
    Config.

%% @doc Format configuration for display
format_config(Config) ->
    #{
        craftplan_url => Config#config.craftplan_url,
        timeout => Config#config.timeout,
        rate_limit => Config#config.rate_limit,
        enable_caching => Config#config.enable_caching,
        cache_ttl => Config#config.cache_ttl
    }.