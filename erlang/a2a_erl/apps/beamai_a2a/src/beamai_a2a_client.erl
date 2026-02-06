%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Protocol Client
%%%
%%% Client for making A2A protocol requests to remote agents.
%%% Supports agent discovery via /.well-known/agent-card.json,
%%% task management (send, get, cancel), and streaming subscriptions
%%% via SSE.
%%%
%%% Uses OTP's httpc client for HTTP requests and json module
%%% for JSON processing.
%%%
%%% Example:
%%%   {ok, Card} = beamai_a2a_client:discover("https://agent.example.com"),
%%%   {ok, Task} = beamai_a2a_client:send_task(
%%%       "https://agent.example.com",
%%%       #{<<"message">> => #{
%%%           <<"messageId">> => beamai_a2a_utils:generate_id(),
%%%           <<"role">> => <<"user">>,
%%%           <<"parts">> => [#{<<"text">> => <<"Hello">>}]
%%%       }},
%%%       #{}),
%%%   {ok, TaskState} = beamai_a2a_client:get_task(
%%%       "https://agent.example.com",
%%%       maps:get(<<"id">>, Task)).
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_client).

-include("a2a.hrl").

%% API
-export([
    discover/1,
    discover/2,
    send_task/3,
    send_task/4,
    get_task/2,
    get_task/3,
    cancel_task/2,
    cancel_task/3,
    subscribe/3,
    subscribe/4,
    set_push_notification/3,
    get_push_notification/2
]).

%% Low-level API
-export([
    jsonrpc_request/4,
    jsonrpc_request/5
]).

%% Default timeout for HTTP requests (30 seconds)
-define(DEFAULT_TIMEOUT, 30000).
-define(AGENT_CARD_PATH, "/.well-known/agent-card.json").

%%====================================================================
%% Discovery
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Discover a remote agent by fetching its agent card.
%%
%% `BaseUrl' is the agent's base URL (e.g., "https://agent.example.com").
%% Returns `{ok, AgentCardMap}' or `{error, Reason}'.
%% @end
%%--------------------------------------------------------------------
-spec discover(binary() | string()) -> {ok, map()} | {error, term()}.
discover(BaseUrl) ->
    discover(BaseUrl, #{}).

-spec discover(binary() | string(), map()) -> {ok, map()} | {error, term()}.
discover(BaseUrl, Opts) ->
    Url = to_list(BaseUrl) ++ ?AGENT_CARD_PATH,
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
    Headers = base_headers(Opts),

    case httpc:request(get, {Url, Headers},
                       [{timeout, Timeout}], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RespHeaders, Body}} ->
            try
                Decoded = json:decode(Body),
                {ok, Decoded}
            catch
                _:_ -> {error, {invalid_json, Body}}
            end;
        {ok, {{_, StatusCode, _}, _, Body}} ->
            {error, {http_error, StatusCode, Body}};
        {error, Reason} ->
            {error, {request_failed, Reason}}
    end.

%%====================================================================
%% Task operations
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Send a task (tasks/send) to a remote agent.
%%
%% `BaseUrl' is the agent's base URL.
%% `Params' is the JSON-RPC params map, expected to contain a
%%   `message' key with the A2A message.
%% `Opts' is a map of options:
%%   `timeout'       - request timeout in ms (default 30000)
%%   `auth_token'    - bearer token for authentication
%%   `api_key'       - API key for authentication
%%   `blocking'      - if true, wait for task completion
%%
%% Returns `{ok, TaskMap}' or `{error, Reason}'.
%% @end
%%--------------------------------------------------------------------
-spec send_task(binary() | string(), map(), map()) ->
    {ok, map()} | {error, term()}.
send_task(BaseUrl, Params, Opts) ->
    send_task(BaseUrl, <<"tasks/send">>, Params, Opts).

-spec send_task(binary() | string(), binary(), map(), map()) ->
    {ok, map()} | {error, term()}.
send_task(BaseUrl, Method, Params, Opts) ->
    jsonrpc_request(BaseUrl, Method, Params, Opts).

%%--------------------------------------------------------------------
%% @doc Get the state of a task (tasks/get) from a remote agent.
%%
%% `BaseUrl' is the agent's base URL.
%% `TaskId' is the task identifier.
%% @end
%%--------------------------------------------------------------------
-spec get_task(binary() | string(), binary()) ->
    {ok, map()} | {error, term()}.
get_task(BaseUrl, TaskId) ->
    get_task(BaseUrl, TaskId, #{}).

-spec get_task(binary() | string(), binary(), map()) ->
    {ok, map()} | {error, term()}.
get_task(BaseUrl, TaskId, Opts) ->
    Params = #{<<"id">> => TaskId},
    ParamsWithHistory = case maps:get(history_length, Opts, undefined) of
        undefined -> Params;
        HL -> Params#{<<"historyLength">> => HL}
    end,
    jsonrpc_request(BaseUrl, <<"tasks/get">>, ParamsWithHistory, Opts).

%%--------------------------------------------------------------------
%% @doc Cancel a task (tasks/cancel) on a remote agent.
%%
%% `BaseUrl' is the agent's base URL.
%% `TaskId' is the task identifier.
%% @end
%%--------------------------------------------------------------------
-spec cancel_task(binary() | string(), binary()) ->
    {ok, map()} | {error, term()}.
cancel_task(BaseUrl, TaskId) ->
    cancel_task(BaseUrl, TaskId, #{}).

-spec cancel_task(binary() | string(), binary(), map()) ->
    {ok, map()} | {error, term()}.
cancel_task(BaseUrl, TaskId, Opts) ->
    Params = #{<<"id">> => TaskId},
    jsonrpc_request(BaseUrl, <<"tasks/cancel">>, Params, Opts).

%%--------------------------------------------------------------------
%% @doc Subscribe to task updates (tasks/sendSubscribe) and receive
%% events via a callback function.
%%
%% `BaseUrl' is the agent's base URL.
%% `Params' is the JSON-RPC params map (same as send_task).
%% `Callback' is a function that receives SSE events:
%%   fun(Event :: map()) -> ok | stop
%%
%% This function spawns a process that connects to the SSE endpoint
%% and forwards events to the callback. Returns `{ok, Pid}' where
%% Pid is the SSE listener process.
%% @end
%%--------------------------------------------------------------------
-spec subscribe(binary() | string(), map(),
                fun((map()) -> ok | stop)) ->
    {ok, pid()} | {error, term()}.
subscribe(BaseUrl, Params, Callback) ->
    subscribe(BaseUrl, Params, Callback, #{}).

-spec subscribe(binary() | string(), map(),
                fun((map()) -> ok | stop), map()) ->
    {ok, pid()} | {error, term()}.
subscribe(BaseUrl, Params, Callback, Opts) ->
    %% First send the task
    case send_task(BaseUrl, <<"tasks/sendSubscribe">>, Params, Opts) of
        {ok, Result} ->
            TaskId = maps:get(<<"id">>, Result,
                              maps:get(<<"taskId">>, Result, undefined)),
            case TaskId of
                undefined ->
                    {error, no_task_id_in_response};
                _ ->
                    %% Start SSE listener process
                    Pid = spawn_link(fun() ->
                        sse_listener(BaseUrl, TaskId, Callback, Opts)
                    end),
                    {ok, Pid}
            end;
        {error, _} = Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @doc Set push notification config for a task.
%% @end
%%--------------------------------------------------------------------
-spec set_push_notification(binary() | string(), map(), map()) ->
    {ok, map()} | {error, term()}.
set_push_notification(BaseUrl, Params, Opts) ->
    jsonrpc_request(BaseUrl, <<"tasks/pushNotification/set">>, Params, Opts).

%%--------------------------------------------------------------------
%% @doc Get push notification config for a task.
%% @end
%%--------------------------------------------------------------------
-spec get_push_notification(binary() | string(), map()) ->
    {ok, map()} | {error, term()}.
get_push_notification(BaseUrl, Params) ->
    jsonrpc_request(BaseUrl, <<"tasks/pushNotification/get">>, Params, #{}).

%%====================================================================
%% Low-level JSON-RPC request
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Send a JSON-RPC request to a remote agent.
%%
%% Constructs a JSON-RPC 2.0 request, sends it via HTTP POST, and
%% decodes the response.
%% @end
%%--------------------------------------------------------------------
-spec jsonrpc_request(binary() | string(), binary(), map(), map()) ->
    {ok, term()} | {error, term()}.
jsonrpc_request(BaseUrl, Method, Params, Opts) ->
    RequestId = beamai_a2a_utils:generate_id(),
    jsonrpc_request(BaseUrl, Method, Params, RequestId, Opts).

-spec jsonrpc_request(binary() | string(), binary(), map(),
                      binary(), map()) ->
    {ok, term()} | {error, term()}.
jsonrpc_request(BaseUrl, Method, Params, RequestId, Opts) ->
    Url = to_list(BaseUrl),
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),

    RequestBody = iolist_to_binary(json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">>  => Method,
        <<"params">>  => Params,
        <<"id">>      => RequestId
    })),

    Headers = request_headers(Opts),
    Request = {Url, Headers, "application/json", RequestBody},

    case httpc:request(post, Request,
                       [{timeout, Timeout}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RespHeaders, RespBody}} ->
            decode_jsonrpc_response(RespBody);
        {ok, {{_, StatusCode, _}, _RespHeaders, RespBody}} ->
            %% Try to decode as JSON-RPC error
            case decode_jsonrpc_response(RespBody) of
                {error, _} = JsonRpcError ->
                    JsonRpcError;
                _ ->
                    {error, {http_error, StatusCode, RespBody}}
            end;
        {error, Reason} ->
            {error, {request_failed, Reason}}
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Decode a JSON-RPC response body.
-spec decode_jsonrpc_response(binary()) -> {ok, term()} | {error, term()}.
decode_jsonrpc_response(Body) ->
    try
        Decoded = json:decode(Body),
        case maps:get(<<"error">>, Decoded, undefined) of
            undefined ->
                {ok, maps:get(<<"result">>, Decoded, #{})};
            ErrorObj ->
                Code = maps:get(<<"code">>, ErrorObj, -32603),
                Message = maps:get(<<"message">>, ErrorObj,
                                   <<"Unknown error">>),
                Data = maps:get(<<"data">>, ErrorObj, undefined),
                {error, {jsonrpc_error, Code, Message, Data}}
        end
    catch
        _:_ ->
            {error, {invalid_response, Body}}
    end.

%% @doc Build request headers with authentication.
-spec request_headers(map()) -> [{string(), string()}].
request_headers(Opts) ->
    Base = base_headers(Opts),
    WithContentType = [{"Content-Type", "application/json"} | Base],
    WithContentType.

%% @doc Build base headers with optional authentication.
-spec base_headers(map()) -> [{string(), string()}].
base_headers(Opts) ->
    Base = [{"Accept", "application/json"}],
    WithAuth = case maps:get(auth_token, Opts, undefined) of
        undefined ->
            case maps:get(api_key, Opts, undefined) of
                undefined -> Base;
                Key ->
                    [{"Authorization",
                      "ApiKey " ++ binary_to_list(Key)} | Base]
            end;
        Token ->
            [{"Authorization",
              "Bearer " ++ binary_to_list(Token)} | Base]
    end,
    WithAuth.

%% @doc SSE listener process that reads events from a streaming
%% connection and forwards them to a callback function.
-spec sse_listener(binary() | string(), binary(),
                   fun((map()) -> ok | stop), map()) -> ok.
sse_listener(BaseUrl, TaskId, Callback, Opts) ->
    Url = to_list(BaseUrl) ++ "/tasks/" ++
          binary_to_list(TaskId) ++ ":subscribe",
    Timeout = maps:get(timeout, Opts, 300000),  %% 5 min for SSE
    Headers = base_headers(Opts),

    %% Use httpc with streaming
    case httpc:request(get, {Url, Headers},
                       [{timeout, Timeout},
                        {sync, false},
                        {stream, self}],
                       []) of
        {ok, RequestId} ->
            sse_receive_loop(RequestId, Callback, <<>>);
        {error, Reason} ->
            logger:error("SSE connection failed: ~p", [Reason]),
            ok
    end.

%% @doc Receive loop for SSE events from httpc streaming.
-spec sse_receive_loop(term(), fun((map()) -> ok | stop), binary()) -> ok.
sse_receive_loop(RequestId, Callback, Buffer) ->
    receive
        {http, {RequestId, stream_start, _Headers}} ->
            sse_receive_loop(RequestId, Callback, Buffer);
        {http, {RequestId, stream, BinBodyPart}} ->
            NewBuffer = <<Buffer/binary, BinBodyPart/binary>>,
            {Events, Remaining} = parse_sse_events(NewBuffer),
            Continue = lists:foldl(fun
                (_Event, stop) -> stop;
                (Event, ok) ->
                    try Callback(Event) of
                        stop -> stop;
                        _ -> ok
                    catch _:_ -> ok
                    end
            end, ok, Events),
            case Continue of
                stop ->
                    httpc:cancel_request(RequestId),
                    ok;
                ok ->
                    sse_receive_loop(RequestId, Callback, Remaining)
            end;
        {http, {RequestId, stream_end, _Headers}} ->
            %% Connection closed by server
            ok;
        {http, {RequestId, {error, Reason}}} ->
            logger:warning("SSE stream error: ~p", [Reason]),
            ok
    after 300000 ->
        %% 5 minute timeout
        httpc:cancel_request(RequestId),
        ok
    end.

%% @doc Parse SSE events from a buffer.
%%
%% SSE events are separated by double newlines. Each event may have
%% `event:' and `data:' fields.
-spec parse_sse_events(binary()) -> {[map()], binary()}.
parse_sse_events(Buffer) ->
    parse_sse_events(Buffer, []).

parse_sse_events(Buffer, Acc) ->
    case binary:split(Buffer, <<"\n\n">>) of
        [EventBlock, Rest] ->
            Event = parse_sse_event_block(EventBlock),
            case Event of
                #{} when map_size(Event) > 0 ->
                    parse_sse_events(Rest, [Event | Acc]);
                _ ->
                    parse_sse_events(Rest, Acc)
            end;
        [Incomplete] ->
            {lists:reverse(Acc), Incomplete}
    end.

%% @doc Parse a single SSE event block into a map.
-spec parse_sse_event_block(binary()) -> map().
parse_sse_event_block(Block) ->
    Lines = binary:split(Block, <<"\n">>, [global]),
    lists:foldl(fun parse_sse_line/2, #{}, Lines).

%% @doc Parse a single SSE line.
-spec parse_sse_line(binary(), map()) -> map().
parse_sse_line(<<"event: ", EventType/binary>>, Acc) ->
    Acc#{<<"event">> => string:trim(EventType)};
parse_sse_line(<<"data: ", Data/binary>>, Acc) ->
    Trimmed = string:trim(Data),
    try
        Decoded = json:decode(Trimmed),
        Acc#{<<"data">> => Decoded}
    catch
        _:_ -> Acc#{<<"data">> => Trimmed}
    end;
parse_sse_line(<<"id: ", Id/binary>>, Acc) ->
    Acc#{<<"id">> => string:trim(Id)};
parse_sse_line(<<": ", _Comment/binary>>, Acc) ->
    %% SSE comment (e.g., keepalive) - ignore
    Acc;
parse_sse_line(_, Acc) ->
    Acc.

%% @doc Convert a value to a list (string) for httpc.
-spec to_list(binary() | string()) -> string().
to_list(V) when is_binary(V) -> binary_to_list(V);
to_list(V) when is_list(V) -> V.
