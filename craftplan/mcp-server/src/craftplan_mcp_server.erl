%%% @doc Craftplan MCP Server
%%% Implements Model Context Protocol server for Craftplan ERP

-module(craftplan_mcp_server).
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

-define(SERVER, ?MODULE).
-define(CRAFTPLAN_API, application:get_env(craftplan_mcp, api_url, "http://localhost:4000/api")).

-record(state, {
    port :: integer(),
    tools :: map(),
    metrics :: map(),
    api_client :: pid() | undefined
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
        _ ->
            cowboy_req:reply(404, Req0)
    end,
    {ok, Result, State}.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Port = application:get_env(craftplan_mcp, port, 8090),
    {ok, APIClient} = craftplan_api_client:start_link(),

    %% Start Cowboy HTTP server
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/mcp", ?MODULE, []},
            {"/health", ?MODULE, []},
            {"/.well-known/agent-card", ?MODULE, []}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(http,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),

    io:format("Craftplan MCP Server listening on port ~p~n", [Port]),

    State = #state{
        port = Port,
        tools = initialize_tools(),
        metrics = #{},
        api_client = APIClient
    },

    {ok, State}.

handle_call(list_tools, _From, State) ->
    Tools = [format_tool_definition(Name, Def) ||
             {Name, Def} <- maps:to_list(State#state.tools)],
    {reply, {ok, Tools}, State};

handle_call({get_tool, ToolName}, _From, State) ->
    case maps:get(ToolName, State#state.tools, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Def ->
            {reply, {ok, format_tool_definition(ToolName, Def)}, State}
    end;

handle_call({call_tool, ToolName, Args}, _From, State) ->
    case maps:get(ToolName, State#state.tools, undefined) of
        undefined ->
            {reply, {error, {unknown_tool, ToolName}}, State};
        ToolDef ->
            {Result, NewMetrics} = execute_tool(ToolName, Args, ToolDef, State#state.metrics),
            {reply, Result, State#state{metrics = NewMetrics}}
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

%% @doc Initialize all MCP tools
initialize_tools() ->
    #{
        <<"customer_management">> => #{
            description => <<"Create, read, update, and delete customer records">>,
            input_schema => customer_input_schema(),
            handler => fun handle_customer_tool/2
        },
        <<"order_management">> => #{
            description => <<"Create, update, process, and manage orders">>,
            input_schema => order_input_schema(),
            handler => fun handle_order_tool/2
        },
        <<"inventory_management">> => #{
            description => <<"Manage products, inventory levels, and stock movements">>,
            input_schema => inventory_input_schema(),
            handler => fun handle_inventory_tool/2
        },
        <<"production_planning">> => #{
            description => <<"Plan and track production orders, schedules, and work orders">>,
            input_schema => production_input_schema(),
            handler => fun handle_production_tool/2
        },
        <<"analytics">> => #{
            description => <<"Generate sales, inventory, and production reports">>,
            input_schema => analytics_input_schema(),
            handler => fun handle_analytics_tool/2
        },
        <<"shipping">> => #{
            description => <<"Process shipments, track packages, manage carriers">>,
            input_schema => shipping_input_schema(),
            handler => fun handle_shipping_tool/2
        }
    }.

%% Input Schemas
customer_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{
            <<"type">> => <<"string">>,
            <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]
        },
        <<"customer_id">> => #{<<"type">> => <<"string">>},
        <<"customer_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

order_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{
            <<"type">> => <<"string">>,
            <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]
        },
        <<"order_id">> => #{<<"type">> => <<"string">>},
        <<"order_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

inventory_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{
            <<"type">> => <<"string">>,
            <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>]
        },
        <<"product_id">> => #{<<"type">> => <<"string">>},
        <<"inventory_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

production_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{
            <<"type">> => <<"string">>,
            <<"enum">> => [<<"list">>, <<"get">>, <<"create">>, <<"update">>]
        },
        <<"plan_id">> => #{<<"type">> => <<"string">>},
        <<"plan_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

analytics_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"report_type">> => #{
            <<"type">> => <<"string">>,
            <<"enum">> => [<<"sales">>, <<"inventory">>, <<"production">>]
        },
        <<"date_range">> => #{<<"type">> => <<"object">>},
        <<"filters">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"report_type">>]
}.

shipping_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{
            <<"type">> => <<"string">>,
            <<"enum">> => [<<"list">>, <<"get">>, <<"create">>]
        },
        <<"shipment_id">> => #{<<"type">> => <<"string">>},
        <<"shipping_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

%% @doc Format tool definition for MCP
format_tool_definition(Name, Def) ->
    #{
        <<"name">> => Name,
        <<"description">> => maps:get(description, Def),
        <<"inputSchema">> => maps:get(input_schema, Def)
    }.

%% @doc Execute a tool
execute_tool(Name, Args, ToolDef, Metrics) ->
    Handler = maps:get(handler, ToolDef),
    try
        Result = Handler(Name, Args),
        {{ok, Result}, Metrics}
    catch
        Error:Reason ->
            {{error, {exception, {Error, Reason}}}, Metrics}
    end.

%% Tool handlers
handle_customer_tool(Name, Args) ->
    case maps:get(<<"operation">>, Args, <<"list">>) of
        <<"list">> ->
            #{<<"customers">> => []};
        <<"get">> ->
            #{<<"customer">> => #{
                <<"id">> => maps:get(<<"customer_id">>, Args),
                <<"name">> => <<"Test Customer">>,
                <<"email">> => <<"test@example.com">>
            }};
        <<"create">> ->
            #{<<"customer_id">> => <<"new_customer_id">>};
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_order_tool(Name, Args) ->
    case maps:get(<<"operation">>, Args, <<"list">>) of
        <<"list">> ->
            #{<<"orders">> => []};
        <<"get">> ->
            #{<<"order">> => #{
                <<"id">> => maps:get(<<"order_id">>, Args),
                <<"status">> => <<"pending">>,
                <<"total">> => 100.0
            }};
        <<"create">> ->
            #{<<"order_id">> => <<"new_order_id">>};
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_inventory_tool(Name, Args) ->
    case maps:get(<<"operation">>, Args, <<"list">>) of
        <<"list">> ->
            #{<<"inventory">> => []};
        <<"get">> ->
            #{<<"product">> => #{
                <<"id">> => maps:get(<<"product_id">>, Args),
                <<"stock">> => 100
            }};
        <<"create">> ->
            ok;
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
        <<"create">> ->
            ok;
        _ ->
            throw({unsupported_operation, Name})
    end.

handle_analytics_tool(_Name, Args) ->
    ReportType = maps:get(<<"report_type">>, Args),
    #{
        <<"report">> => #{
            <<"type">> => ReportType,
            <<"data">> => [],
            <<"generated_at">> => os:system_time(millisecond)
        }
    }.

handle_shipping_tool(Name, Args) ->
    case maps:get(<<"operation">>, Args, <<"list">>) of
        <<"list">> ->
            #{<<"shipments">> => []};
        <<"get">> ->
            #{<<"shipment">> => #{
                <<"id">> => maps:get(<<"shipment_id">>, Args),
                <<"status">> => <<"in_transit">>
            }};
        <<"create">> ->
            ok;
        _ ->
            throw({unsupported_operation, Name})
    end.

%% HTTP Handlers
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
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, RespBody, Req1).

handle_health(Req0) ->
    Health = #{
        <<"status">> => <<"healthy">>,
        <<"server">> => <<"craftplan-mcp">>,
        <<"version">> => <<"1.0.0">>,
        <<"timestamp">> => os:system_time(millisecond)
    },
    Body = jiffy:encode(Health),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0).

handle_agent_card(Req0) ->
    {ok, Body} = file:read_file(filename:join([code:priv_dir(craftplan_mcp), "agent-card.json"])),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0).

format_error({unknown_tool, Name}) ->
    <<"Unknown tool: ", Name/binary>>;
format_error({exception, {Type, Reason}}) ->
    iolist_to_binary([io_lib:format("~p: ~p", [Type, Reason])]);
format_error(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).