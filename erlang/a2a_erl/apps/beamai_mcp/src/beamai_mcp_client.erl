%%%-------------------------------------------------------------------
%%% @doc BeamAI MCP Client
%%%
%%% Client for connecting to external MCP servers. Discovers server
%%% capabilities, calls remote tools, and fetches remote resources.
%%% Supports both stdio and HTTP/SSE transports through the
%%% beamai_mcp_transport abstraction.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mcp_client).

-behaviour(gen_server).

%% API
-export([
    connect/1,
    disconnect/1,
    list_tools/1,
    call_tool/3,
    list_resources/1,
    get_resource/2,
    list_prompts/1,
    get_prompt/3,
    get_capabilities/1,
    ping/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(DEFAULT_TIMEOUT, 30000).
-define(MCP_VERSION, <<"2024-11-05">>).

-record(state, {
    server_url      :: binary(),
    transport       :: pid() | undefined,
    transport_type  :: stdio | http,
    capabilities    :: map(),
    server_info     :: map(),
    connected       :: boolean(),
    request_id      :: non_neg_integer(),
    pending         :: #{integer() => {pid(), reference()}},
    config          :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Connect to a remote MCP server.
%% Options:
%%   url - Server URL (required for HTTP transport)
%%   transport - stdio | http (default: http)
%%   command - Command for stdio transport
-spec connect(map()) -> {ok, pid()} | {error, term()}.
connect(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

%% @doc Disconnect from the MCP server.
-spec disconnect(pid()) -> ok.
disconnect(Client) ->
    gen_server:stop(Client, normal, 5000).

%% @doc List tools available on the remote MCP server.
-spec list_tools(pid()) -> {ok, [map()]} | {error, term()}.
list_tools(Client) ->
    gen_server:call(Client, list_tools, ?DEFAULT_TIMEOUT).

%% @doc Call a tool on the remote MCP server.
-spec call_tool(pid(), binary(), map()) -> {ok, map()} | {error, term()}.
call_tool(Client, ToolName, Args) ->
    gen_server:call(Client, {call_tool, ToolName, Args}, ?DEFAULT_TIMEOUT).

%% @doc List resources available on the remote MCP server.
-spec list_resources(pid()) -> {ok, [map()]} | {error, term()}.
list_resources(Client) ->
    gen_server:call(Client, list_resources, ?DEFAULT_TIMEOUT).

%% @doc Read a resource from the remote MCP server.
-spec get_resource(pid(), binary()) -> {ok, [map()]} | {error, term()}.
get_resource(Client, Uri) ->
    gen_server:call(Client, {get_resource, Uri}, ?DEFAULT_TIMEOUT).

%% @doc List prompts available on the remote MCP server.
-spec list_prompts(pid()) -> {ok, [map()]} | {error, term()}.
list_prompts(Client) ->
    gen_server:call(Client, list_prompts, ?DEFAULT_TIMEOUT).

%% @doc Get a prompt from the remote MCP server.
-spec get_prompt(pid(), binary(), map()) -> {ok, map()} | {error, term()}.
get_prompt(Client, Name, Args) ->
    gen_server:call(Client, {get_prompt, Name, Args}, ?DEFAULT_TIMEOUT).

%% @doc Get the server capabilities discovered during initialization.
-spec get_capabilities(pid()) -> {ok, map()} | {error, term()}.
get_capabilities(Client) ->
    gen_server:call(Client, get_capabilities).

%% @doc Ping the remote MCP server.
-spec ping(pid()) -> ok | {error, term()}.
ping(Client) ->
    gen_server:call(Client, ping, 5000).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Opts) ->
    ServerUrl = maps:get(url, Opts, <<"http://localhost:3001">>),
    TransportType = maps:get(transport, Opts, http),
    State = #state{
        server_url = ServerUrl,
        transport = undefined,
        transport_type = TransportType,
        capabilities = #{},
        server_info = #{},
        connected = false,
        request_id = 1,
        pending = #{},
        config = Opts
    },
    %% Attempt to connect and initialize
    case do_connect(State) of
        {ok, ConnectedState} ->
            case do_initialize(ConnectedState) of
                {ok, InitState} ->
                    logger:info("MCP client connected to ~s", [ServerUrl]),
                    {ok, InitState};
                {error, Reason} ->
                    logger:error("MCP client initialization failed: ~p", [Reason]),
                    {ok, State#state{connected = false}}
            end;
        {error, Reason} ->
            logger:warning("MCP client connection failed: ~p (will retry)", [Reason]),
            {ok, State#state{connected = false}}
    end.

%% @private
handle_call(list_tools, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            case send_request(<<"tools/list">>, #{}, ConnState) of
                {ok, #{<<"tools">> := Tools}, NewState} ->
                    {reply, {ok, Tools}, NewState};
                {ok, Result, NewState} ->
                    {reply, {ok, maps:get(<<"tools">>, Result, [])}, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({call_tool, ToolName, Args}, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            Params = #{<<"name">> => ToolName, <<"arguments">> => Args},
            case send_request(<<"tools/call">>, Params, ConnState) of
                {ok, Result, NewState} ->
                    {reply, {ok, Result}, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(list_resources, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            case send_request(<<"resources/list">>, #{}, ConnState) of
                {ok, #{<<"resources">> := Resources}, NewState} ->
                    {reply, {ok, Resources}, NewState};
                {ok, Result, NewState} ->
                    {reply, {ok, maps:get(<<"resources">>, Result, [])}, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_resource, Uri}, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            Params = #{<<"uri">> => Uri},
            case send_request(<<"resources/read">>, Params, ConnState) of
                {ok, #{<<"contents">> := Contents}, NewState} ->
                    {reply, {ok, Contents}, NewState};
                {ok, Result, NewState} ->
                    {reply, {ok, Result}, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(list_prompts, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            case send_request(<<"prompts/list">>, #{}, ConnState) of
                {ok, #{<<"prompts">> := Prompts}, NewState} ->
                    {reply, {ok, Prompts}, NewState};
                {ok, Result, NewState} ->
                    {reply, {ok, maps:get(<<"prompts">>, Result, [])}, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_prompt, Name, Args}, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            Params = #{<<"name">> => Name, <<"arguments">> => Args},
            case send_request(<<"prompts/get">>, Params, ConnState) of
                {ok, Result, NewState} ->
                    {reply, {ok, Result}, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_capabilities, _From, #state{capabilities = Caps} = State) ->
    {reply, {ok, Caps}, State};

handle_call(ping, _From, State) ->
    case ensure_connected(State) of
        {ok, ConnState} ->
            case send_request(<<"ping">>, #{}, ConnState) of
                {ok, _Result, NewState} ->
                    {reply, ok, NewState};
                {error, Reason, NewState} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({transport_data, Data}, State) ->
    %% Handle incoming data from the transport
    handle_transport_data(Data, State);

handle_info({transport_closed, _Reason}, State) ->
    logger:warning("MCP transport closed"),
    {noreply, State#state{connected = false, transport = undefined}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{transport = Transport}) ->
    case Transport of
        undefined -> ok;
        Pid when is_pid(Pid) ->
            try beamai_mcp_transport:close(Pid)
            catch _:_ -> ok
            end
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Establish transport connection.
-spec do_connect(#state{}) -> {ok, #state{}} | {error, term()}.
do_connect(#state{transport_type = http, server_url = Url, config = Config} = State) ->
    TransportOpts = #{type => http, url => Url, config => Config},
    case beamai_mcp_transport:start(http, TransportOpts) of
        {ok, TransportPid} ->
            {ok, State#state{transport = TransportPid, connected = true}};
        {error, Reason} ->
            {error, Reason}
    end;
do_connect(#state{transport_type = stdio, config = Config} = State) ->
    Command = maps:get(command, Config, undefined),
    case Command of
        undefined ->
            {error, missing_command_for_stdio};
        Cmd ->
            TransportOpts = #{type => stdio, command => Cmd, config => Config},
            case beamai_mcp_transport:start(stdio, TransportOpts) of
                {ok, TransportPid} ->
                    {ok, State#state{transport = TransportPid, connected = true}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% @private Send the MCP initialize request.
-spec do_initialize(#state{}) -> {ok, #state{}} | {error, term()}.
do_initialize(State) ->
    Params = #{
        <<"protocolVersion">> => ?MCP_VERSION,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{
            <<"name">> => <<"beamai-mcp-client">>,
            <<"version">> => <<"0.1.0">>
        }
    },
    case send_request(<<"initialize">>, Params, State) of
        {ok, Result, NewState} ->
            Capabilities = maps:get(<<"capabilities">>, Result, #{}),
            ServerInfo = maps:get(<<"serverInfo">>, Result, #{}),
            %% Send initialized notification
            _ = send_notification(<<"notifications/initialized">>, #{}, NewState),
            {ok, NewState#state{
                capabilities = Capabilities,
                server_info = ServerInfo
            }};
        {error, Reason, _NewState} ->
            {error, Reason}
    end.

%% @private Ensure the client is connected, reconnecting if necessary.
-spec ensure_connected(#state{}) -> {ok, #state{}} | {error, term()}.
ensure_connected(#state{connected = true} = State) ->
    {ok, State};
ensure_connected(State) ->
    case do_connect(State) of
        {ok, ConnState} ->
            case do_initialize(ConnState) of
                {ok, InitState} -> {ok, InitState};
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @private Send a JSON-RPC request via the transport.
-spec send_request(binary(), map(), #state{}) ->
    {ok, map(), #state{}} | {error, term(), #state{}}.
send_request(Method, Params, #state{transport = Transport, request_id = ReqId} = State)
  when Transport =/= undefined ->
    Request = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"id">> => ReqId,
        <<"method">> => Method,
        <<"params">> => Params
    },
    NewState = State#state{request_id = ReqId + 1},
    case beamai_mcp_transport:send(Transport, Request) of
        {ok, Response} ->
            case Response of
                #{<<"result">> := Result} ->
                    {ok, Result, NewState};
                #{<<"error">> := Error} ->
                    {error, Error, NewState};
                _ ->
                    {ok, Response, NewState}
            end;
        {error, Reason} ->
            {error, Reason, NewState#state{connected = false}}
    end;
send_request(_Method, _Params, State) ->
    {error, not_connected, State}.

%% @private Send a JSON-RPC notification (no response expected).
-spec send_notification(binary(), map(), #state{}) -> ok | {error, term()}.
send_notification(Method, Params, #state{transport = Transport})
  when Transport =/= undefined ->
    Notification = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => Method,
        <<"params">> => Params
    },
    case beamai_mcp_transport:send(Transport, Notification) of
        {ok, _} -> ok;
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end;
send_notification(_Method, _Params, _State) ->
    {error, not_connected}.

%% @private Handle incoming transport data.
-spec handle_transport_data(term(), #state{}) -> {noreply, #state{}}.
handle_transport_data(Data, State) when is_map(Data) ->
    case maps:find(<<"id">>, Data) of
        {ok, Id} ->
            %% Response to a pending request
            case maps:find(Id, State#state.pending) of
                {ok, {From, _Ref}} ->
                    gen_server:reply(From, {ok, Data}),
                    NewPending = maps:remove(Id, State#state.pending),
                    {noreply, State#state{pending = NewPending}};
                error ->
                    %% No pending request for this ID
                    {noreply, State}
            end;
        error ->
            %% Notification from server
            handle_server_notification(Data, State)
    end;
handle_transport_data(_Data, State) ->
    {noreply, State}.

%% @private Handle a server notification.
-spec handle_server_notification(map(), #state{}) -> {noreply, #state{}}.
handle_server_notification(#{<<"method">> := Method} = Notification, State) ->
    logger:debug("MCP server notification: ~s", [Method]),
    case Method of
        <<"notifications/tools/list_changed">> ->
            %% Tools list changed, clients should re-fetch
            logger:info("MCP server tools list changed"),
            {noreply, State};
        <<"notifications/resources/list_changed">> ->
            logger:info("MCP server resources list changed"),
            {noreply, State};
        _ ->
            logger:debug("Unhandled MCP notification: ~s", [Method]),
            {noreply, State}
    end;
handle_server_notification(_Notification, State) ->
    {noreply, State}.
