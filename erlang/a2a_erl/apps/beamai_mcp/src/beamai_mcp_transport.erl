%%%-------------------------------------------------------------------
%%% @doc BeamAI MCP Transport Abstraction
%%%
%%% Provides a unified transport interface for MCP communication.
%%% Supports stdio transport for local processes and HTTP/SSE
%%% transport for remote servers.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mcp_transport).

-behaviour(gen_server).

%% API
-export([
    start/2,
    send/2,
    receive_msg/1,
    close/1,
    get_type/1,
    is_connected/1
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

-define(HTTP_TIMEOUT, 30000).
-define(RECV_TIMEOUT, 60000).

-record(state, {
    type        :: stdio | http,
    owner       :: pid(),
    connected   :: boolean(),
    %% stdio-specific
    port        :: port() | undefined,
    buffer      :: binary(),
    %% HTTP-specific
    url         :: binary() | undefined,
    session_url :: binary() | undefined,
    config      :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start a transport process.
%% Type is `stdio' or `http'.
%% Opts contains transport-specific configuration.
-spec start(stdio | http, map()) -> {ok, pid()} | {error, term()}.
start(Type, Opts) ->
    gen_server:start_link(?MODULE, {Type, Opts, self()}, []).

%% @doc Send a JSON-RPC message through the transport.
%% Returns {ok, Response} for request/response, or ok for notifications.
-spec send(pid(), map()) -> {ok, map()} | ok | {error, term()}.
send(Transport, Message) ->
    gen_server:call(Transport, {send, Message}, ?HTTP_TIMEOUT).

%% @doc Receive a message from the transport (blocking with timeout).
-spec receive_msg(pid()) -> {ok, map()} | {error, timeout | term()}.
receive_msg(Transport) ->
    gen_server:call(Transport, receive_msg, ?RECV_TIMEOUT).

%% @doc Close the transport connection.
-spec close(pid()) -> ok.
close(Transport) ->
    gen_server:stop(Transport, normal, 5000).

%% @doc Get the transport type.
-spec get_type(pid()) -> stdio | http.
get_type(Transport) ->
    gen_server:call(Transport, get_type).

%% @doc Check if the transport is connected.
-spec is_connected(pid()) -> boolean().
is_connected(Transport) ->
    gen_server:call(Transport, is_connected).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init({stdio, Opts, Owner}) ->
    Command = maps:get(command, Opts, undefined),
    case Command of
        undefined ->
            {stop, missing_command};
        Cmd ->
            CmdStr = case is_binary(Cmd) of
                true -> binary_to_list(Cmd);
                false when is_list(Cmd) -> Cmd;
                false when is_atom(Cmd) -> atom_to_list(Cmd)
            end,
            try
                Port = open_port({spawn, CmdStr}, [
                    binary, {line, 65536}, use_stdio, exit_status, stderr_to_stdout
                ]),
                State = #state{
                    type = stdio,
                    owner = Owner,
                    connected = true,
                    port = Port,
                    buffer = <<>>,
                    config = Opts
                },
                {ok, State}
            catch
                error:Reason ->
                    {stop, {port_open_failed, Reason}}
            end
    end;

init({http, Opts, Owner}) ->
    Url = maps:get(url, Opts, <<"http://localhost:3001">>),
    State = #state{
        type = http,
        owner = Owner,
        connected = true,
        url = Url,
        buffer = <<>>,
        config = Opts
    },
    {ok, State}.

%% @private
handle_call({send, Message}, _From, #state{type = stdio} = State) ->
    case do_stdio_send(Message, State) of
        {ok, Response, NewState} ->
            {reply, {ok, Response}, NewState};
        {error, Reason, NewState} ->
            {reply, {error, Reason}, NewState}
    end;

handle_call({send, Message}, _From, #state{type = http} = State) ->
    case do_http_send(Message, State) of
        {ok, Response, NewState} ->
            IsNotification = not maps:is_key(<<"id">>, Message),
            case IsNotification of
                true -> {reply, ok, NewState};
                false -> {reply, {ok, Response}, NewState}
            end;
        {error, Reason, NewState} ->
            {reply, {error, Reason}, NewState}
    end;

handle_call(receive_msg, _From, State) ->
    %% For synchronous receive, check the buffer
    case parse_buffered_message(State) of
        {ok, Msg, NewState} ->
            {reply, {ok, Msg}, NewState};
        {error, empty} ->
            {reply, {error, no_message}, State}
    end;

handle_call(get_type, _From, #state{type = Type} = State) ->
    {reply, Type, State};

handle_call(is_connected, _From, #state{connected = Connected} = State) ->
    {reply, Connected, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({Port, {data, {eol, Line}}}, #state{port = Port, owner = Owner} = State) ->
    %% Data from stdio port (line-buffered)
    case try_decode_json(Line) of
        {ok, Message} ->
            Owner ! {transport_data, Message},
            {noreply, State};
        {error, _} ->
            %% Accumulate in buffer
            NewBuffer = <<(State#state.buffer)/binary, Line/binary>>,
            {noreply, State#state{buffer = NewBuffer}}
    end;

handle_info({Port, {data, {noeol, Data}}}, #state{port = Port} = State) ->
    %% Partial line, accumulate
    NewBuffer = <<(State#state.buffer)/binary, Data/binary>>,
    {noreply, State#state{buffer = NewBuffer}};

handle_info({Port, {exit_status, Status}}, #state{port = Port, owner = Owner} = State) ->
    logger:warning("MCP stdio transport process exited with status ~p", [Status]),
    Owner ! {transport_closed, {exit_status, Status}},
    {noreply, State#state{connected = false, port = undefined}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{type = stdio, port = Port}) when Port =/= undefined ->
    try port_close(Port)
    catch _:_ -> ok
    end,
    ok;
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Send a message via stdio transport.
-spec do_stdio_send(map(), #state{}) -> {ok, map(), #state{}} | {error, term(), #state{}}.
do_stdio_send(Message, #state{port = Port} = State) when Port =/= undefined ->
    JsonBin = jsx:encode(Message),
    try
        port_command(Port, [JsonBin, $\n]),
        %% For requests (with id), wait for response
        case maps:is_key(<<"id">>, Message) of
            true ->
                case wait_for_response(State, ?HTTP_TIMEOUT) of
                    {ok, Response, NewState} ->
                        {ok, Response, NewState};
                    {error, Reason} ->
                        {error, Reason, State}
                end;
            false ->
                {ok, #{}, State}
        end
    catch
        error:Reason ->
            {error, {send_failed, Reason}, State#state{connected = false}}
    end;
do_stdio_send(_Message, State) ->
    {error, port_not_open, State}.

%% @private Send a message via HTTP transport.
-spec do_http_send(map(), #state{}) -> {ok, map(), #state{}} | {error, term(), #state{}}.
do_http_send(Message, #state{url = BaseUrl} = State) ->
    Url = build_mcp_url(BaseUrl),
    JsonBin = jsx:encode(Message),
    Headers = [
        {<<"Content-Type">>, <<"application/json">>},
        {<<"Accept">>, <<"application/json">>}
    ],
    try
        case beamai_http_client:post(Url, Headers, JsonBin) of
            {ok, StatusCode, RespHeaders, RespBody} when StatusCode >= 200, StatusCode < 300 ->
                %% Check for session URL in response headers
                NewState = maybe_update_session(RespHeaders, State),
                Response = case RespBody of
                    Body when is_map(Body) -> Body;
                    Body when is_binary(Body), byte_size(Body) > 0 ->
                        try jsx:decode(Body, [return_maps])
                        catch _:_ -> #{}
                        end;
                    _ -> #{}
                end,
                {ok, Response, NewState};
            {ok, StatusCode, _Headers, Body} ->
                {error, {http_error, StatusCode, Body}, State};
            {error, Reason} ->
                {error, {http_request_failed, Reason}, State#state{connected = false}}
        end
    catch
        Class:Reason2:_Stack ->
            {error, {Class, Reason2}, State#state{connected = false}}
    end.

%% @private Wait for a response on the stdio port.
-spec wait_for_response(#state{}, non_neg_integer()) ->
    {ok, map(), #state{}} | {error, term()}.
wait_for_response(#state{port = Port} = State, Timeout) ->
    receive
        {Port, {data, {eol, Line}}} ->
            case try_decode_json(Line) of
                {ok, Response} ->
                    {ok, Response, State};
                {error, _} ->
                    %% Not a complete JSON response, keep waiting
                    NewBuf = <<(State#state.buffer)/binary, Line/binary>>,
                    wait_for_response(State#state{buffer = NewBuf}, Timeout)
            end;
        {Port, {data, {noeol, Data}}} ->
            NewBuf = <<(State#state.buffer)/binary, Data/binary>>,
            wait_for_response(State#state{buffer = NewBuf}, Timeout)
    after Timeout ->
        {error, timeout}
    end.

%% @private Parse a buffered message.
-spec parse_buffered_message(#state{}) -> {ok, map(), #state{}} | {error, empty}.
parse_buffered_message(#state{buffer = Buffer} = State)
  when byte_size(Buffer) > 0 ->
    case try_decode_json(Buffer) of
        {ok, Msg} ->
            {ok, Msg, State#state{buffer = <<>>}};
        {error, _} ->
            {error, empty}
    end;
parse_buffered_message(_State) ->
    {error, empty}.

%% @private Build the MCP endpoint URL.
-spec build_mcp_url(binary()) -> binary().
build_mcp_url(BaseUrl) ->
    %% If the URL already ends with a path, use it as-is
    case binary:match(BaseUrl, <<"/mcp">>) of
        nomatch ->
            %% Strip trailing slash and append /mcp
            CleanUrl = case binary:last(BaseUrl) of
                $/ -> binary:part(BaseUrl, 0, byte_size(BaseUrl) - 1);
                _ -> BaseUrl
            end,
            <<CleanUrl/binary, "/mcp">>;
        _ ->
            BaseUrl
    end.

%% @private Update session URL from response headers.
-spec maybe_update_session([{binary(), binary()}], #state{}) -> #state{}.
maybe_update_session(Headers, State) ->
    case lists:keyfind(<<"mcp-session-id">>, 1, Headers) of
        {_, SessionId} ->
            State#state{session_url = SessionId};
        false ->
            case lists:keyfind(<<"Mcp-Session-Id">>, 1, Headers) of
                {_, SessionId} ->
                    State#state{session_url = SessionId};
                false ->
                    State
            end
    end.

%% @private Try to decode a binary as JSON.
-spec try_decode_json(binary()) -> {ok, map()} | {error, term()}.
try_decode_json(Bin) when is_binary(Bin), byte_size(Bin) > 0 ->
    try
        Decoded = jsx:decode(Bin, [return_maps]),
        {ok, Decoded}
    catch
        _:Reason -> {error, Reason}
    end;
try_decode_json(_) ->
    {error, empty}.
