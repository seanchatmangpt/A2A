%%% @doc Optimized Craftplan MCP Server
%%% Enhanced with performance monitoring, caching, and connection pooling

-module(craftplan_mcp_server_optimized).
-behaviour(gen_server).
-behaviour(cowboy_handler).

%% API
-export([start_link/0, stop/0]).
-export([list_tools/0, call_tool/2, get_tool/1]).
-export([handle_mcp_request/1, handle_health/1, handle_agent_card/1]).
-export([init/2, handle/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("performance.hrl").

-define(SERVER, ?MODULE).
-define(CRAFTPLAN_API, application:get_env(craftplan_mcp, api_url, "http://localhost:4000/api")).
-define(CACHE_TTL, 30000). % 30 seconds cache for MCP tools
-define(MAX_RETRIES, 3).

-record(state, {
    port :: integer(),
    tools :: map(),
    metrics :: map(),
    api_client :: pid() | undefined,
    cache :: binary(),
    pool :: binary(),
    enabled :: boolean()
}).

-type tool_result() :: {ok, map()} | {error, term()}.

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc List all available MCP tools
-spec list_tools() -> {ok, [map()]}.
list_tools() ->
    gen_server:call(?SERVER, list_tools).

%% @doc Get a specific tool's definition
-spec get_tool(binary()) -> {ok, map()} | {error, not_found}.
get_tool(ToolName) ->
    gen_server:call(?SERVER, {get_tool, ToolName}).

%% @doc Call an MCP tool
-spec call_tool(binary(), map()) -> tool_result().
call_tool(ToolName, Args) ->
    gen_server:call(?SERVER, {call_tool, ToolName, Args}, 30000).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

init(Req0, State) ->
    {ok, Req0, State}.

handle(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),

    Result = case {Method, Path} of
        {<<"POST">>, <<"/mcp">>} ->
            handle_mcp_request(Req0);
        {<<"GET">>, <<"/health">>} ->
            handle_health(Req0);
        {<<"GET">>, <<"/.well-known/agent-card">>} ->
            handle_agent_card(Req0);
        {<<"GET">>, <<"/metrics">>} ->
            handle_metrics(Req0);
        {<<"GET">>, <<"/performance">>} ->
            handle_performance(Req0);
        _ ->
            cowboy_req:reply(404, Req0)
    end,
    {ok, Result, State}.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Port = application:get_env(craftplan_mcp, port, 8090),
    CacheName = <<"mcp_cache">>,
    PoolName = <<"craftplan-api">>,

    %% Start components
    {ok, APIClient} = craftplan_api_client:start_link(),
    ok = performance_metrics:start_link(),
    ok = performance_monitor:start_link(),
    ok = http_pool:start_link(),
    ok = cache_manager:start_link(),

    %% Start Cowboy HTTP server
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/mcp", ?MODULE, []},
            {"/health", ?MODULE, []},
            {"/.well-known/agent-card", ?MODULE, []},
            {"/metrics", ?MODULE, []},
            {"/performance", ?MODULE, []}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(http,
        [{port, Port}, {num_acceptors, 10}, {max_connections, 10000}],
        #{
            env => #{dispatch => Dispatch},
            middlewares => [cowboy_compress_h, ?MODULE]
        }
    ),

    io:format("Optimized Craftplan MCP Server listening on port ~p~n", [Port]),
    io:format("Performance monitoring enabled~n"),

    State = #state{
        port = Port,
        tools = initialize_tools(),
        metrics = #{},
        api_client = APIClient,
        cache = CacheName,
        pool = PoolName,
        enabled = true
    },

    %% Register tools with performance monitor
    ok = register_performance_alerts(),

    {ok, State}.

handle_call(list_tools, _From, State) ->
    Start = os:system_time(microsecond),

    %% Check cache first
    case cache_manager:get(State#state.cache, {list_tools, all}, {error, not_found}) of
        {ok, Tools} ->
            performance_metrics:record_timing(<<"mcp.list_tools_cache">>, os:system_time(microsecond) - Start, #{}),
            {reply, {ok, Tools}, State};
        {error, not_found} ->
            %% Generate and cache tools
            ToolList = [format_tool_definition(Name, Def) ||
                       {Name, Def} <- maps:to_list(State#state.tools)],

            CacheTtl = application:get_env(craftplan_mcp, cache_ttl, ?CACHE_TTL),
            cache_manager:put(State#state.cache, {list_tools, all}, ToolList, CacheTtl),

            performance_metrics:record_timing(<<"mcp.list_tools_generate">>, os:system_time(microsecond) - Start, #{}),
            {reply, {ok, ToolList}, State}
    end;

handle_call({get_tool, ToolName}, _From, State) ->
    Start = os:system_time(microsecond),

    %% Check cache first
    case cache_manager:get(State#state.cache, {get_tool, ToolName}, {error, not_found}) of
        {ok, ToolDef} ->
            performance_metrics:record_timing(<<"mcp.get_tool_cache">>, os:system_time(microsecond) - Start, #{}),
            {reply, {ok, ToolDef}, State};
        {error, not_found} ->
            %% Get and cache tool definition
            case maps:get(ToolName, State#state.tools, undefined) of
                undefined ->
                    {reply, {error, not_found}, State};
                Def ->
                    ToolDef = format_tool_definition(ToolName, Def),
                    CacheTtl = application:get_env(craftplan_mcp, cache_ttl, ?CACHE_TTL),
                    cache_manager:put(State#state.cache, {get_tool, ToolName}, ToolDef, CacheTtl),

                    performance_metrics:record_timing(<<"mcp.get_tool_generate">>, os:system_time(microsecond) - Start, #{}),
                    {reply, {ok, ToolDef}, State}
            end
    end;

handle_call({call_tool, ToolName, Args}, _From, State) ->
    Start = os:system_time(microsecond),
    RequestId = generate_request_id(),

    performance_metrics:increment_counter(<<"mcp.requests">>, 1),
    performance_metrics:increment_counter(<<"mcp.requests." ++ binary_to_list(ToolName)>>, 1),

    %% Check cache for safe GET operations
    case is_cacheable_request(ToolName, Args) of
        true ->
            case cache_manager:get(State#state.cache, {call_tool, ToolName, Args}, {error, not_found}) of
                {ok, Result} ->
                    performance_metrics:record_timing(<<"mcp.tool_call_cache">>, os:system_time(microsecond) - Start, #{tool => ToolName}),
                    performance_metrics:record_timing(<<"mcp.tool_call_cache." ++ binary_to_list(ToolName)>>, os:system_time(microsecond) - Start, #{}),
                    {reply, {ok, Result}, State};
                {error, not_found} ->
                    execute_tool_with_retry(State, ToolName, Args, RequestId, Start)
            end;
        false ->
            execute_tool_with_retry(State, ToolName, Args, RequestId, Start)
    end;

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

initialize_tools() ->
    #{
        <<"customer_management">> => #{
            description => <<"Create, read, update, and delete customer records">>,
            input_schema => customer_input_schema(),
            handler => fun handle_customer_tool/2,
            cacheable => false
        },
        <<"order_management">> => #{
            description => <<"Create, update, process, and manage orders">>,
            input_schema => order_input_schema(),
            handler => fun handle_order_tool/2,
            cacheable => false
        },
        <<"inventory_management">> => #{
            description => <<"Manage products, inventory levels, and stock movements">>,
            input_schema => inventory_input_schema(),
            handler => fun handle_inventory_tool/2,
            cacheable => true
        },
        <<"production_planning">> => #{
            description => <<"Plan and track production orders, schedules, and work orders">>,
            input_schema => production_input_schema(),
            handler => fun handle_production_tool/2,
            cacheable => false
        },
        <<"analytics">> => #{
            description => <<"Generate sales, inventory, and production reports">>,
            input_schema => analytics_input_schema(),
            handler => fun handle_analytics_tool/2,
            cacheable => true
        },
        <<"shipping">> => #{
            description => <<"Process shipments, track packages, manage carriers">>,
            input_schema => shipping_input_schema(),
            handler => fun handle_shipping_tool/2,
            cacheable => true
        }
    }.

customer_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]},
        <<"customer_id">> => #{<<"type">> => <<"string">>},
        <<"customer_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

order_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]},
        <<"order_id">> => #{<<"type">> => <<"string">>},
        <<"order_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

inventory_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>]},
        <<"product_id">> => #{<<"type">> => <<"string">>},
        <<"inventory_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

production_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>]},
        <<"plan_id">> => #{<<"type">> => <<"string">>},
        <<"plan_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

analytics_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"report_type">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"sales">>, <<"inventory">>, <<"production">>]},
        <<"date_range">> => #{<<"type">> => <<"object">>},
        <<"filters">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"report_type">>]
}.

shipping_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"list">>, <<"get">>, <<"create">>]},
        <<"shipment_id">> => #{<<"type">> => <<"string">>},
        <<"shipping_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

format_tool_definition(Name, Def) ->
    #{
        <<"name">> => Name,
        <<"description">> => maps:get(description, Def),
        <<"inputSchema">> => maps:get(input_schema, Def),
        <<"cacheable">> => maps:get(cacheable, Def, false)
    }.

execute_tool_with_retry(State, ToolName, Args, RequestId, Start) ->
    case execute_tool(State, ToolName, Args, RequestId) of
        {ok, Result} ->
            %% Cache successful results for cacheable operations
            case is_cacheable_request(ToolName, Args) of
                true ->
                    CacheTtl = application:get_env(craftplan_mcp, cache_ttl, ?CACHE_TTL),
                    cache_manager:put(State#state.cache, {call_tool, ToolName, Args}, Result, CacheTtl);
                false ->
                    ok
            end,

            Duration = os:system_time(microsecond) - Start,
            performance_metrics:record_timing(<<"mcp.tool_call">>, Duration, #{tool => ToolName}),
            performance_metrics:record_timing(<<"mcp.tool_call." ++ binary_to_list(ToolName)>>, Duration, #{}),
            {reply, {ok, Result}, State};
        {error, Reason} ->
            Duration = os:system_time(microsecond) - Start,
            performance_metrics:record_timing(<<"mcp.tool_call_error">>, Duration, #{tool => ToolName}),
            performance_metrics:increment_counter(<<"mcp.errors">>, 1),
            performance_metrics:increment_counter(<<"mcp.errors." ++ binary_to_list(ToolName)>>, 1),
            {reply, {error, Reason}, State}
    end.

execute_tool(State, ToolName, Args, RequestId) ->
    ToolDef = maps:get(ToolName, State#state.tools, undefined),
    case ToolDef of
        undefined ->
            {error, {unknown_tool, ToolName}};
        _ ->
            %% Use connection pool for API calls
            case http_pool:with_connection(State#state.pool,
                    fun(PoolName) ->
                        craftplan_api_client:request(ToolName, Operation, Params, PoolName)
                    end, []) of
                {ok, Result} ->
                    {{ok, Result}, State#state.metrics};
                {error, Reason} ->
                    {{error, Reason}, State#state.metrics}
            end
    end.

is_cacheable_request(ToolName, Args) ->
    case ToolName of
        <<"inventory_management">> -> maps:get(<<"operation">>, Args, <<"list">>) =:= <<"list">>;
        <<"analytics">> -> true;
        <<"shipping">> -> maps:get(<<"operation">>, Args, <<"list">>) =:= <<"list">>;
        _ -> false
    end.

%% Tool handlers (optimized with caching)
handle_customer_tool(Name, Args) ->
    Operation = maps:get(<<"operation">>, Args, <<"list">>),

    case Operation of
        <<"list">> ->
            %% Cache customer list
            case cache_manager:get(<<"api_cache">>, {customer_list}, {error, not_found}) of
                {ok, Customers} ->
                    #{<<"customers">> => Customers};
                {error, not_found} ->
                    Customers = fetch_customer_list(),
                    cache_manager:put(<<"api_cache">>, {customer_list}, Customers, ?CACHE_TTL),
                    #{<<"customers">> => Customers}
            end;
        <<"get">> ->
            CustomerId = maps:get(<<"customer_id">>, Args),
            case cache_manager:get(<<"api_cache">>, {customer_get, CustomerId}, {error, not_found}) of
                {ok, Customer} ->
                    #{<<"customer">> => Customer};
                {error, not_found} ->
                    Customer = fetch_customer(CustomerId),
                    cache_manager:put(<<"api_cache">>, {customer_get, CustomerId}, Customer, ?CACHE_TTL),
                    #{<<"customer">> => Customer}
            end;
        <<"create">> ->
            #{<<"customer_id">> => <<"new_customer_id">>};
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_order_tool(Name, Args) ->
    Operation = maps:get(<<"operation">>, Args, <<"list">>),

    case Operation of
        <<"list">> ->
            case cache_manager:get(<<"api_cache">>, {order_list}, {error, not_found}) of
                {ok, Orders} ->
                    #{<<"orders">> => Orders};
                {error, not_found} ->
                    Orders = fetch_order_list(),
                    cache_manager:put(<<"api_cache">>, {order_list}, Orders, ?CACHE_TTL),
                    #{<<"orders">> => Orders}
            end;
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_inventory_tool(Name, Args) ->
    Operation = maps:get(<<"operation">>, Args, <<"list">>),

    case Operation of
        <<"list">> ->
            case cache_manager:get(<<"api_cache">>, {inventory_list}, {error, not_found}) of
                {ok, Inventory} ->
                    #{<<"inventory">> => Inventory};
                {error, not_found} ->
                    Inventory = fetch_inventory_list(),
                    cache_manager:put(<<"api_cache">>, {inventory_list}, Inventory, 60000), % 1 minute cache
                    #{<<"inventory">> => Inventory}
            end;
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_production_tool(Name, Args) ->
    case maps:get(<<"operation">>, Args, <<"list">>) of
        <<"list">> ->
            #{<<"plans">> => []};
        <<"get">> ->
            #{<<"plan">> => #{
                <<"id">> => maps:get(<<"plan_id">>, Args),
                <<"status">> => <<"active">>
            }};
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_analytics_tool(_Name, Args) ->
    ReportType = maps:get(<<"report_type">>, Args),

    case cache_manager:get(<<"api_cache">>, {analytics, ReportType}, {error, not_found}) of
        {ok, Report} ->
            Report;
        {error, not_found} ->
            Report = generate_analytics_report(ReportType),
            cache_manager:put(<<"api_cache">>, {analytics, ReportType}, Report, 300000), % 5 minute cache
            Report
    end.

handle_shipping_tool(Name, Args) ->
    Operation = maps:get(<<"operation">>, Args, <<"list">>),

    case Operation of
        <<"list">> ->
            case cache_manager:get(<<"api_cache">>, {shipping_list}, {error, not_found}) of
                {ok, Shipments} ->
                    #{<<"shipments">> => Shipments};
                {error, not_found} ->
                    Shipments = fetch_shipping_list(),
                    cache_manager:put(<<"api_cache">>, {shipping_list}, Shipments, 60000), % 1 minute cache
                    #{<<"shipments">> => Shipments}
            end;
        _ ->
            throw({unsupported_operation, Name})
    end.

%% Mock data fetch functions (would call actual API)
fetch_customer_list() ->
    [].

fetch_customer(_CustomerId) ->
    #{
        <<"id">> => <<"customer_id">>,
        <<"name">> => <<"Test Customer">>,
        <<"email">> => <<"test@example.com">>
    }.

fetch_order_list() ->
    [].

fetch_inventory_list() ->
    [].

fetch_shipping_list() ->
    [].

generate_analytics_report(ReportType) ->
    #{
        <<"report">> => #{
            <<"type">> => ReportType,
            <<"data">> => [],
            <<"generated_at">> => os:system_time(millisecond)
        }
    }.

%% HTTP handlers
handle_mcp_request(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Request = jiffy:decode(Body, [return_maps]),

    Response = case Request of
        #{<<"jsonrpc">> := <<"2.0">>, <<"method">> := <<"tools/list">>, <<"id">> := Id} ->
            {ok, Tools} = list_tools(),
            #{<<"jsonrpc">> => <<"2.0">>, <<"result">> => #{<<"tools">> => Tools}, <<"id">> => Id};

        #{<<"jsonrpc">> := <<"2.0">>, <<"method">> := <<"tools/call">>,
          <<"params">> := Params, <<"id">> := Id} ->
            ToolName = maps:get(<<"name">>, Params),
            Arguments = maps:get(<<"arguments">>, Params, #{}),
            case call_tool(ToolName, Arguments) of
                {ok, Result} ->
                    #{<<"jsonrpc">> => <<"2.0">>, <<"result">> => Result, <<"id">> => Id};
                {error, Reason} ->
                    #{<<"jsonrpc">> => <<"2.0">>,
                      <<"error">> => #{<<"code">> => -32000, <<"message">> => format_error(Reason)},
                      <<"id">> => Id}
            end;

        _ ->
            #{<<"jsonrpc">> => <<"2.0">>,
              <<"error">> => #{<<"code">> => -32601, <<"message">> => <<"Method not found">>},
              <<"id">> => maps:get(<<"id">>, Request, null)}
    end,

    RespBody = jiffy:encode(Response),
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"server">> => <<"craftplan-mcp-optimized">>,
        <<"x-cache-status">> => <<"hit">> % Could indicate cache status
    },
    cowboy_req:reply(200, Headers, RespBody, Req1).

handle_health(Req0) ->
    Health = performance_monitor:get_dashboard_data(),
    Body = jiffy:encode(Health),
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"server">> => <<"craftplan-mcp-optimized">>
    },
    cowboy_req:reply(200, Headers, Body, Req0).

handle_agent_card(Req0) ->
    {ok, Body} = file:read_file(filename:join([code:priv_dir(craftplan_mcp), "agent-card.json"])),
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"server">> => <<"craftplan-mcp-optimized">>
    },
    cowboy_req:reply(200, Headers, Body, Req0).

handle_metrics(Req0) ->
    Metrics = performance_metrics:get_metrics(),
    Body = jiffy:encode(Metrics),
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"server">> => <<"craftplan-mcp-optimized">>
    },
    cowboy_req:reply(200, Headers, Body, Req0).

handle_performance(Req0) ->
    Dashboard = performance_monitor:get_dashboard_data(),
    Body = jiffy:encode(Dashboard),
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"server">> => <<"craftplan-mcp-optimized">>
    },
    cowboy_req:reply(200, Headers, Body, Req0).

format_error({unknown_tool, Name}) ->
    <<"Unknown tool: ", Name/binary>>;
format_error({exception, {Type, Reason}}) ->
    iolist_to_binary([io_lib:format("~p: ~p", [Type, Reason])]);
format_error(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

generate_request_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("req_~p_~p", [Timestamp, Random])).

register_performance_alerts() ->
    %% Register performance monitoring alerts
    performance_monitor:register_alert(<<"high_error_rate">>, <<"mcp.error_rate">>, #{
        type => threshold,
        operator => '>',
        value => 0.05,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"high_latency">>, <<"mcp.avg_response_time">>, #{
        type => threshold,
        operator => '>',
        value => 1000,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"high_memory_usage">>, <<"system.memory.processes">>, #{
        type => threshold,
        operator => '>',
        value => 1000000000, % 1GB
        duration => 600000,
        enabled => true
    }),

    ok.