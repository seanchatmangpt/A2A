%%% @doc elrmcp MCP Client
%%% HTTP client for communicating with Craftplan MCP server

-module(elrmcp_mcp_client).
-behaviour(gen_server).

%% API
-export([start_link/1, stop/0]).
-export([list_tools/0, call_tool/2, get_tool/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 30000).
-define(JSONRPC_VERSION, <<"2.0">>).

-record(state, {
    base_url :: binary(),
    http_client :: pid(),
    timeout :: integer(),
    auth_header :: binary() | undefined
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the MCP client
-spec start_link(binary()) -> {ok, pid()} | {error, term()}.
start_link(BaseUrl) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [BaseUrl], []).

%% @doc Stop the MCP client
stop() ->
    gen_server:stop(?SERVER).

%% @doc List all available tools from Craftplan MCP
-spec list_tools() -> {ok, [map()]} | {error, term()}.
list_tools() ->
    gen_server:call(?SERVER, list_tools, ?DEFAULT_TIMEOUT).

%% @doc Call a tool on Craftplan MCP
-spec call_tool(binary(), map()) -> {ok, map()} | {error, term()}.
call_tool(ToolName, Arguments) ->
    gen_server:call(?SERVER, {call_tool, ToolName, Arguments}, ?DEFAULT_TIMEOUT).

%% @doc Get a specific tool's definition
-spec get_tool(binary()) -> {ok, map()} | {error, term()}.
get_tool(ToolName) ->
    gen_server:call(?SERVER, {get_tool, ToolName}, ?DEFAULT_TIMEOUT).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([BaseUrl]) ->
    State = #state{
        base_url = BaseUrl,
        http_client = undefined,
        timeout = ?DEFAULT_TIMEOUT,
        auth_header = undefined
    },

    %% Start HTTP client
    {ok, HttpClient} = start_http_client(),

    {ok, State#state{http_client = HttpClient}}.

handle_call(list_tools, _From, State) ->
    Request = #{
        jsonrpc => ?JSONRPC_VERSION,
        method => <<"tools/list">>,
        id => generate_request_id()
    },

    case send_request(Request, State) of
        {ok, Response} ->
            case Response of
                #{<<"result">> := #{<<"tools">> := Tools}} ->
                    {ok, Tools};
                #{<<"error">> := Error} ->
                    {error, {mcp_error, Error}}
            end;
        {error, Reason} ->
            {error, Reason}
    end;

handle_call({call_tool, ToolName, Arguments}, _From, State) ->
    Request = #{
        jsonrpc => ?JSONRPC_VERSION,
        method => <<"tools/call">>,
        params => #{
            name => ToolName,
            arguments => Arguments
        },
        id => generate_request_id()
    },

    case send_request(Request, State) of
        {ok, Response} ->
            case Response of
                #{<<"result">> := Result} ->
                    {ok, Result};
                #{<<"error">> := Error} ->
                    {error, {mcp_error, Error}}
            end;
        {error, Reason} ->
            {error, Reason}
    end;

handle_call({get_tool, ToolName}, _From, State) ->
    Request = #{
        jsonrpc => ?JSONRPC_VERSION,
        method => <<"tools/get">>,
        params => #{
            name => ToolName
        },
        id => generate_request_id()
    },

    case send_request(Request, State) of
        {ok, Response} ->
            case Response of
                #{<<"result">> := Tool} ->
                    {ok, Tool};
                #{<<"error">> := Error} ->
                    {error, {mcp_error, Error}}
            end;
        {error, Reason} ->
            {error, Reason}
    end;

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

%% @doc Start HTTP client
start_http_client() ->
    %% In a real implementation, this would start an HTTP client process
    %% For now, use a simple implementation
    {ok, self()}.

%% @doc Send JSON-RPC request to Craftplan MCP
send_request(Request, State) ->
    Url = <<State#state.base_url/binary, "/mcp">>,
    Headers = get_request_headers(State),
    Body = jiffy:encode(Request),

    try
        %% This would be replaced with actual HTTP client call
        %% For now, simulate response
        simulate_mcp_response(Request)
    catch
        Error:Reason ->
            {error, {request_failed, {Error, Reason}}}
    end.

%% @doc Get request headers
get_request_headers(State) ->
    Headers = [
        {<<"content-type">>, <<"application/json">>},
        {<<"user-agent">>, <<"elrmcp-bridge/1.0.0">>}
    ],

    %% Add authentication header if configured
    case State#state.auth_header of
        undefined ->
            Headers;
        AuthHeader ->
            [{<<"authorization">>, AuthHeader} | Headers]
    end.

%% @doc Generate unique request ID
generate_request_id() ->
    integer_to_binary(erlang:system_time(millisecond)).

%% @doc Simulate MCP response (for testing)
simulate_mcp_response(Request) ->
    Method = maps:get(<<"method">>, Request),

    case Method of
        <<"tools/list">> ->
            Response = #{
                jsonrpc => ?JSONRPC_VERSION,
                result => #{
                    tools => [
                        #{
                            name => <<"customer_management">>,
                            description => <<"Create, read, update, and delete customer records">>,
                            inputSchema => #{
                                type => object,
                                properties => #{
                                    operation => #{type => string, enum => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]},
                                    customer_id => #{type => string},
                                    customer_data => #{type => object}
                                },
                                required => [<<"operation">>]
                            }
                        },
                        #{
                            name => <<"order_management">>,
                            description => <<"Create, update, process, and manage orders">>,
                            inputSchema => #{
                                type => object,
                                properties => #{
                                    operation => #{type => string, enum => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]},
                                    order_id => #{type => string},
                                    order_data => #{type => object}
                                },
                                required => [<<"operation">>]
                            }
                        }
                    ]
                },
                id => maps:get(<<"id">>, Request)
            },
            {ok, Response};

        <<"tools/call">> ->
            Params = maps:get(<<"params">>, Request),
            ToolName = maps:get(<<"name">>, Params),
            Arguments = maps:get(<<"arguments">>, Params, #{}),

            Result = simulate_tool_call(ToolName, Arguments),

            Response = #{
                jsonrpc => ?JSONRPC_VERSION,
                result => Result,
                id => maps:get(<<"id">>, Request)
            },
            {ok, Response};

        <<"tools/get">> ->
            Params = maps:get(<<"params">>, Request),
            ToolName = maps:get(<<"name">>, Params),

            Tool = case ToolName of
                <<"customer_management">> ->
                    #{
                        name => <<"customer_management">>,
                        description => <<"Create, read, update, and delete customer records">>,
                        inputSchema => #{
                            type => object,
                            properties => #{
                                operation => #{type => string, enum => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]},
                                customer_id => #{type => string},
                                customer_data => #{type => object}
                            },
                            required => [<<"operation">>]
                        }
                    };
                <<"order_management">> ->
                    #{
                        name => <<"order_management">>,
                        description => <<"Create, update, process, and manage orders">>,
                        inputSchema => #{
                            type => object,
                            properties => #{
                                operation => #{type => string, enum => [<<"list">>, <<"get">>, <<"create">>, <<"update">>, <<"delete">>]},
                                order_id => #{type => string},
                                order_data => #{type => object}
                            },
                            required => [<<"operation">>]
                        }
                    };
                _ ->
                    undefined
            end,

            case Tool of
                undefined ->
                    Response = #{
                        jsonrpc => ?JSONRPC_VERSION,
                        error => #{
                            code => -32601,
                            message => <<"Tool not found">>
                        },
                        id => maps:get(<<"id">>, Request)
                    },
                    {ok, Response};
                _ ->
                    Response = #{
                        jsonrpc => ?JSONRPC_VERSION,
                        result => Tool,
                        id => maps:get(<<"id">>, Request)
                    },
                    {ok, Response}
            end;

        _ ->
            Response = #{
                jsonrpc => ?JSONRPC_VERSION,
                error => #{
                    code => -32601,
                    message => <<"Method not found">>
                },
                id => maps:get(<<"id">>, Request)
            },
            {ok, Response}
    end.

%% @doc Simulate tool call response
simulate_tool_call(ToolName, Args) ->
    case ToolName of
        <<"customer_management">> ->
            Operation = maps:get(<<"operation">>, Args, <<"list">>),
            case Operation of
                <<"list">> ->
                    #{<<"customers">> => []};
                <<"get">> ->
                    #{<<"customer">> => #{
                        id => maps:get(<<"customer_id">>, Args),
                        name => <<"Test Customer">>,
                        email => <<"test@example.com">>
                    }};
                <<"create">> ->
                    #{<<"customer_id">> => <<"new_customer_id">>};
                <<"update">> ->
                    #{<<"success">> => true};
                <<"delete">> ->
                    #{<<"success">> => true}
            end;
        <<"order_management">> ->
            Operation = maps:get(<<"operation">>, Args, <<"list">>),
            case Operation of
                <<"list">> ->
                    #{<<"orders">> => []};
                <<"get">> ->
                    #{<<"order">> => #{
                        id => maps:get(<<"order_id">>, Args),
                        status => <<"pending">>,
                        total => 100.0
                    }};
                <<"create">> ->
                    #{<<"order_id">> => <<"new_order_id">>};
                <<"update">> ->
                    #{<<"success">> => true};
                <<"delete">> ->
                    #{<<"success">> => true}
            end;
        _ ->
            #{<<"error">> => <<"Unknown tool">>}
    end.