%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A HTTP Handler Abstraction Layer
%%%
%%% This module provides a behavior for HTTP request handling that bridges
%%% the existing a2a_http_handler with BeamAI's Cowboy handler patterns.
%%% It supports content-type negotiation, request body parsing, response
%%% formatting, and integration with middleware for auth/rate-limiting.
%%%
%%% Implements Cowboy handler callbacks and delegates to callback modules
%%% that implement the beamai_a2a_http_handler behaviour.
%%%
%%% Content Types Supported:
%%%   - application/json (JSON-RPC requests/responses)
%%%   - text/event-stream (SSE streaming upgrade)
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_http_handler).

-include("a2a.hrl").

%% Behaviour definition
-callback handle_request(Method :: binary(), Path :: binary(),
                         Body :: map(), Req :: cowboy_req:req()) ->
    {ok, StatusCode :: integer(), ResponseBody :: map()} |
    {error, StatusCode :: integer(), ErrorMsg :: binary()} |
    {stream, Req :: cowboy_req:req()} |
    {forward, Module :: module(), Req :: cowboy_req:req()}.

-callback handle_jsonrpc(Method :: binary(), Params :: map(),
                         Id :: binary() | integer() | null,
                         Req :: cowboy_req:req()) ->
    {ok, Result :: map()} |
    {error, Code :: integer(), Message :: binary()} |
    {error, Code :: integer(), Message :: binary(), Data :: term()}.

-optional_callbacks([handle_jsonrpc/4]).

%% Cowboy handler callbacks
-export([init/2, handle/2, terminate/3]).

%% Public API
-export([send_json/3, send_sse/3, send_error/3]).

%% Internal utilities
-export([parse_body/1, negotiate_content_type/1]).

-record(handler_state, {
    callback_module :: module() | undefined,
    parsed_body :: map() | undefined,
    content_type :: json | sse | unknown,
    middleware_chain = [] :: [module()],
    request_id :: binary() | undefined,
    opts :: map()
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @doc Initialize the Cowboy handler.
%% Parses the request, negotiates content type, runs middleware,
%% and delegates to the appropriate handler.
-spec init(cowboy_req:req(), list() | map()) ->
    {ok, cowboy_req:req(), term()} | {cowboy_loop, cowboy_req:req(), term()}.
init(Req0, Opts) when is_list(Opts) ->
    init(Req0, opts_to_map(Opts));
init(Req0, Opts) when is_map(Opts) ->
    CallbackModule = maps:get(callback, Opts, undefined),
    MiddlewareChain = maps:get(middleware, Opts, default_middleware()),

    %% Determine content type from Accept header
    ContentType = negotiate_content_type(Req0),

    State = #handler_state{
        callback_module = CallbackModule,
        content_type = ContentType,
        middleware_chain = MiddlewareChain,
        opts = Opts
    },

    %% Run pre-request middleware (auth, rate limiting, etc.)
    case run_middleware(pre_request, Req0, State) of
        {ok, Req1, State1} ->
            handle(Req1, State1);
        {error, StatusCode, ErrorMsg, Req1} ->
            Req2 = send_error(StatusCode, ErrorMsg, Req1),
            {ok, Req2, State}
    end.

%% @doc Handle the HTTP request after middleware processing.
%% Routes based on content type and method.
-spec handle(cowboy_req:req(), #handler_state{}) ->
    {ok, cowboy_req:req(), #handler_state{}} |
    {cowboy_loop, cowboy_req:req(), #handler_state{}}.
handle(Req0, #handler_state{content_type = sse} = State) ->
    %% SSE requests get upgraded to loop handler
    handle_sse_upgrade(Req0, State);
handle(Req0, #handler_state{callback_module = undefined} = State) ->
    %% No callback module - use built-in JSON-RPC routing
    handle_builtin(Req0, State);
handle(Req0, #handler_state{callback_module = Mod} = State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),

    %% Parse request body for POST/PUT/PATCH
    {Body, Req1} = case Method of
        <<"GET">> -> {#{}, Req0};
        <<"DELETE">> -> {#{}, Req0};
        <<"OPTIONS">> -> {#{}, Req0};
        _ -> parse_body(Req0)
    end,

    State1 = State#handler_state{parsed_body = Body},

    %% Handle OPTIONS for CORS
    case Method of
        <<"OPTIONS">> ->
            Req2 = cowboy_req:reply(204, cors_headers(), <<>>, Req1),
            {ok, Req2, State1};
        _ ->
            %% Delegate to callback module
            case Mod:handle_request(Method, Path, Body, Req1) of
                {ok, StatusCode, ResponseBody} ->
                    Req2 = send_json(StatusCode, ResponseBody, Req1),
                    {ok, Req2, State1};
                {error, StatusCode, ErrorMsg} ->
                    Req2 = send_error(StatusCode, ErrorMsg, Req1),
                    {ok, Req2, State1};
                {stream, Req2} ->
                    %% Handler initiated SSE stream
                    {cowboy_loop, Req2, State1};
                {forward, ForwardMod, Req2} ->
                    %% Forward to another handler module
                    ForwardMod:init(Req2, maps:get(forward_opts, State1#handler_state.opts, []))
            end
    end.

%% @doc Terminate the handler, running post-request middleware.
-spec terminate(term(), cowboy_req:req(), #handler_state{}) -> ok.
terminate(Reason, Req, #handler_state{} = State) ->
    %% Run post-request middleware (logging, metrics, cleanup)
    _ = run_middleware(post_request, Req, State),
    case State#handler_state.callback_module of
        undefined -> ok;
        _Mod ->
            %% Log request completion for observability
            log_request_completion(Reason, Req, State)
    end,
    ok;
terminate(_Reason, _Req, _State) ->
    ok.

%%====================================================================
%% Public API
%%====================================================================

%% @doc Send a JSON response with the given status code and body map.
-spec send_json(integer(), map() | binary(), cowboy_req:req()) -> cowboy_req:req().
send_json(StatusCode, Body, Req) when is_map(Body) ->
    EncodedBody = json:encode(Body),
    Headers = maps:merge(json_headers(), cors_headers()),
    cowboy_req:reply(StatusCode, Headers, EncodedBody, Req);
send_json(StatusCode, Body, Req) when is_binary(Body) ->
    Headers = maps:merge(json_headers(), cors_headers()),
    cowboy_req:reply(StatusCode, Headers, Body, Req).

%% @doc Initiate an SSE stream and send an initial event.
%% Returns the request object configured for streaming.
-spec send_sse(binary(), map() | binary(), cowboy_req:req()) -> cowboy_req:req().
send_sse(EventType, Data, Req) ->
    Headers = #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"access-control-allow-origin">> => <<"*">>,
        <<"x-accel-buffering">> => <<"no">>
    },
    Req1 = cowboy_req:stream_reply(200, Headers, Req),
    %% Send the initial event
    send_sse_event(EventType, Data, Req1),
    Req1.

%% @doc Send a JSON-RPC error response.
-spec send_error(integer(), binary(), cowboy_req:req()) -> cowboy_req:req().
send_error(StatusCode, Message, Req) ->
    ErrorBody = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => #{
            <<"code">> => status_to_jsonrpc_code(StatusCode),
            <<"message">> => Message
        },
        <<"id">> => null
    },
    send_json(StatusCode, ErrorBody, Req).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Handle requests when no callback module is configured.
%% Provides built-in JSON-RPC routing compatible with the A2A protocol.
handle_builtin(Req0, State) ->
    Method = cowboy_req:method(Req0),

    case Method of
        <<"OPTIONS">> ->
            Req1 = cowboy_req:reply(204, cors_headers(), <<>>, Req0),
            {ok, Req1, State};
        <<"POST">> ->
            {Body, Req1} = parse_body(Req0),
            State1 = State#handler_state{parsed_body = Body},
            handle_jsonrpc_request(Body, Req1, State1);
        <<"GET">> ->
            Path = cowboy_req:path(Req0),
            handle_get_request(Path, Req0, State);
        _ ->
            Req1 = send_error(405, <<"Method not allowed">>, Req0),
            {ok, Req1, State}
    end.

%% @private Handle JSON-RPC POST requests.
handle_jsonrpc_request(Body, Req, State) ->
    case parse_jsonrpc(Body) of
        {ok, JsonRpcMethod, Params, Id} ->
            State1 = State#handler_state{request_id = Id},
            case dispatch_jsonrpc(JsonRpcMethod, Params, Id, Req) of
                {ok, Result} ->
                    Response = make_jsonrpc_response(Id, Result),
                    Req1 = send_json(200, Response, Req),
                    {ok, Req1, State1};
                {error, Code, Msg} ->
                    Response = make_jsonrpc_error(Id, Code, Msg),
                    Req1 = send_json(200, Response, Req),
                    {ok, Req1, State1};
                {error, Code, Msg, Data} ->
                    Response = make_jsonrpc_error(Id, Code, Msg, Data),
                    Req1 = send_json(200, Response, Req),
                    {ok, Req1, State1}
            end;
        {error, parse_error} ->
            Response = make_jsonrpc_error(null, ?JSONRPC_PARSE_ERROR, <<"Parse error">>),
            Req1 = send_json(400, Response, Req),
            {ok, Req1, State};
        {error, invalid_request} ->
            Response = make_jsonrpc_error(null, ?JSONRPC_INVALID_REQUEST, <<"Invalid request">>),
            Req1 = send_json(400, Response, Req),
            {ok, Req1, State}
    end.

%% @private Parse a JSON-RPC request from a decoded map.
parse_jsonrpc(#{<<"jsonrpc">> := <<"2.0">>, <<"method">> := Method} = Body) ->
    Params = maps:get(<<"params">>, Body, #{}),
    Id = maps:get(<<"id">>, Body, null),
    {ok, Method, Params, Id};
parse_jsonrpc(#{<<"method">> := _Method}) ->
    {error, invalid_request};
parse_jsonrpc(_) ->
    {error, parse_error}.

%% @private Dispatch a JSON-RPC method to the appropriate handler.
%% These are the standard A2A protocol methods dispatched to the BeamAI
%% handler layer.
dispatch_jsonrpc(<<"message/send">>, Params, _Id, _Req) ->
    case beamai_dispatch_message_send(Params) of
        {ok, Result} -> {ok, Result};
        {error, Reason} -> {error, ?JSONRPC_INTERNAL_ERROR, Reason}
    end;
dispatch_jsonrpc(<<"message/stream">>, _Params, _Id, _Req) ->
    %% Streaming should go through SSE, not standard JSON-RPC
    {error, ?A2A_UNSUPPORTED_OPERATION,
     <<"Use SSE endpoint for streaming">>};
dispatch_jsonrpc(<<"tasks/get">>, Params, _Id, _Req) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case TaskId of
        undefined ->
            {error, ?JSONRPC_INVALID_PARAMS, <<"Missing task id">>};
        _ ->
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    {ok, #{<<"task">> => a2a_json:encode_task(Task)}};
                {error, not_found} ->
                    {error, ?A2A_TASK_NOT_FOUND, <<"Task not found">>}
            end
    end;
dispatch_jsonrpc(<<"tasks/cancel">>, Params, _Id, _Req) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case TaskId of
        undefined ->
            {error, ?JSONRPC_INVALID_PARAMS, <<"Missing task id">>};
        _ ->
            case a2a_task_store:get_task_pid(TaskId) of
                {ok, Pid} ->
                    case a2a_task_statem:cancel_task(Pid) of
                        {ok, Task} ->
                            {ok, #{<<"task">> => a2a_json:encode_task(Task)}};
                        {error, task_terminal} ->
                            {error, ?A2A_TASK_ALREADY_TERMINAL,
                             <<"Task already in terminal state">>}
                    end;
                {error, not_found} ->
                    {error, ?A2A_TASK_NOT_FOUND, <<"Task not found">>}
            end
    end;
dispatch_jsonrpc(<<"tasks/pushNotificationConfig/set">>, Params, _Id, _Req) ->
    %% Forward to push notification configuration
    TaskId = maps:get(<<"id">>, Params, undefined),
    PushConfig = maps:get(<<"pushNotificationConfig">>, Params, #{}),
    case TaskId of
        undefined ->
            {error, ?JSONRPC_INVALID_PARAMS, <<"Missing task id">>};
        _ ->
            {ok, #{<<"taskId">> => TaskId, <<"pushNotificationConfig">> => PushConfig}}
    end;
dispatch_jsonrpc(Method, _Params, _Id, _Req) ->
    {error, ?JSONRPC_METHOD_NOT_FOUND,
     <<"Unknown method: ", Method/binary>>}.

%% @private Dispatch message/send via the BeamAI layer.
%% Attempts to use beamai_a2a_cowboy_handler if available, falls back
%% to the legacy a2a_http_handler logic.
beamai_dispatch_message_send(Params) ->
    try
        case a2a_json:decode_send_message_request(Params) of
            {ok, SendReq} ->
                Message = SendReq#send_message_request.message,
                Config = SendReq#send_message_request.configuration,
                TaskId = Message#message.task_id,

                Result = case TaskId of
                    undefined ->
                        %% New task
                        Opts = case Config of
                            undefined -> #{};
                            #send_message_configuration{} ->
                                #{blocking => Config#send_message_configuration.blocking}
                        end,
                        case a2a_task_statem:start_link(Message, Opts) of
                            {ok, Pid} -> a2a_task_statem:get_task(Pid);
                            Error -> Error
                        end;
                    _ ->
                        %% Continue existing task
                        case a2a_task_store:get_task_pid(TaskId) of
                            {ok, Pid} ->
                                a2a_task_statem:send_message(Pid, Message);
                            {error, not_found} ->
                                {error, task_not_found}
                        end
                end,

                case Result of
                    {ok, Task} ->
                        {ok, #{<<"task">> => a2a_json:encode_task(Task)}};
                    {error, Reason} ->
                        {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
                end;
            {error, _} ->
                {error, <<"Invalid message parameters">>}
        end
    catch
        _:Err ->
            {error, iolist_to_binary(io_lib:format("~p", [Err]))}
    end.

%% @private Handle GET requests (agent card, health, etc.)
handle_get_request(<<"/.well-known/agent-card.json">>, Req, State) ->
    AgentCard = a2a_agent_card:get_card(),
    Body = a2a_json:encode_agent_card(AgentCard),
    Req1 = send_json(200, Body, Req),
    {ok, Req1, State};
handle_get_request(<<"/beamai/agent-card">>, Req, State) ->
    %% BeamAI-specific agent card endpoint
    AgentCard = a2a_agent_card:get_card(),
    CardMap = a2a_json:encode_agent_card(AgentCard),
    %% Augment with BeamAI metadata
    BeamAICard = CardMap#{
        <<"beamai">> => #{
            <<"framework">> => <<"BeamAI">>,
            <<"version">> => <<"0.1.0">>,
            <<"capabilities">> => [<<"kernel">>, <<"tools">>, <<"filters">>]
        }
    },
    Req1 = send_json(200, BeamAICard, Req),
    {ok, Req1, State};
handle_get_request(_Path, Req, State) ->
    Req1 = send_error(404, <<"Not found">>, Req),
    {ok, Req1, State}.

%% @private Handle SSE upgrade request.
handle_sse_upgrade(Req0, State) ->
    Headers = #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"access-control-allow-origin">> => <<"*">>,
        <<"x-accel-buffering">> => <<"no">>
    },
    Req = cowboy_req:stream_reply(200, Headers, Req0),
    %% Send initial connection event
    send_sse_event(<<"connected">>, #{<<"status">> => <<"ok">>}, Req),
    %% Schedule keepalive
    erlang:send_after(30000, self(), beamai_keepalive),
    {cowboy_loop, Req, State}.

%% @private Send a single SSE event.
send_sse_event(EventType, Data, Req) when is_map(Data) ->
    EncodedData = json:encode(Data),
    send_sse_event(EventType, EncodedData, Req);
send_sse_event(EventType, Data, Req) when is_binary(Data) ->
    Chunk = iolist_to_binary([
        <<"event: ">>, EventType, <<"\n">>,
        <<"data: ">>, Data, <<"\n\n">>
    ]),
    cowboy_req:stream_body(Chunk, nofin, Req).

%% @doc Parse the request body, handling JSON content type.
-spec parse_body(cowboy_req:req()) -> {map(), cowboy_req:req()}.
parse_body(Req0) ->
    case cowboy_req:read_body(Req0) of
        {ok, <<>>, Req1} ->
            {#{}, Req1};
        {ok, RawBody, Req1} ->
            case cowboy_req:header(<<"content-type">>, Req1) of
                <<"application/json", _/binary>> ->
                    try
                        Decoded = json:decode(RawBody),
                        {ensure_map(Decoded), Req1}
                    catch
                        _:_ -> {#{<<"_raw">> => RawBody}, Req1}
                    end;
                _ ->
                    {#{<<"_raw">> => RawBody}, Req1}
            end;
        {more, _Partial, Req1} ->
            %% Body too large or chunked - read in full
            read_full_body(Req1, [])
    end.

%% @private Read the full body for chunked/large requests.
read_full_body(Req0, Acc) ->
    case cowboy_req:read_body(Req0) of
        {ok, Data, Req1} ->
            Full = iolist_to_binary(lists:reverse([Data | Acc])),
            try
                Decoded = json:decode(Full),
                {ensure_map(Decoded), Req1}
            catch
                _:_ -> {#{<<"_raw">> => Full}, Req1}
            end;
        {more, Data, Req1} ->
            read_full_body(Req1, [Data | Acc])
    end.

%% @doc Negotiate the content type from the Accept header.
-spec negotiate_content_type(cowboy_req:req()) -> json | sse | unknown.
negotiate_content_type(Req) ->
    Accept = cowboy_req:header(<<"accept">>, Req, <<"application/json">>),
    case Accept of
        <<"text/event-stream", _/binary>> -> sse;
        <<"application/json", _/binary>> -> json;
        <<"*/*", _/binary>> -> json;
        _ ->
            %% Check if text/event-stream is anywhere in the accept header
            case binary:match(Accept, <<"text/event-stream">>) of
                nomatch ->
                    case binary:match(Accept, <<"application/json">>) of
                        nomatch -> unknown;
                        _ -> json
                    end;
                _ -> sse
            end
    end.

%%====================================================================
%% Middleware Pipeline
%%====================================================================

%% @private Default middleware chain for request processing.
default_middleware() ->
    [].

%% @private Run middleware chain for a given phase.
-spec run_middleware(pre_request | post_request, cowboy_req:req(), #handler_state{}) ->
    {ok, cowboy_req:req(), #handler_state{}} |
    {error, integer(), binary(), cowboy_req:req()}.
run_middleware(Phase, Req, #handler_state{middleware_chain = Chain} = State) ->
    run_middleware_chain(Phase, Chain, Req, State).

run_middleware_chain(_Phase, [], Req, State) ->
    {ok, Req, State};
run_middleware_chain(Phase, [Middleware | Rest], Req, State) ->
    try
        case apply_middleware(Phase, Middleware, Req, State) of
            {ok, Req1, State1} ->
                run_middleware_chain(Phase, Rest, Req1, State1);
            {error, StatusCode, Msg, Req1} ->
                {error, StatusCode, Msg, Req1};
            skip ->
                run_middleware_chain(Phase, Rest, Req, State)
        end
    catch
        _:MiddlewareError ->
            logger:error("Middleware ~p failed in phase ~p: ~p",
                         [Middleware, Phase, MiddlewareError]),
            run_middleware_chain(Phase, Rest, Req, State)
    end.

%% @private Apply a single middleware. Middleware can be:
%%   - A module implementing execute/3
%%   - A tuple {Module, Function}
%%   - A fun/3
apply_middleware(Phase, Middleware, Req, State) when is_atom(Middleware) ->
    case erlang:function_exported(Middleware, execute, 3) of
        true ->
            Middleware:execute(Phase, Req, State#handler_state.opts);
        false ->
            skip
    end;
apply_middleware(Phase, {Mod, Fun}, Req, State) ->
    case erlang:function_exported(Mod, Fun, 3) of
        true ->
            Mod:Fun(Phase, Req, State#handler_state.opts);
        false ->
            skip
    end;
apply_middleware(Phase, Fun, Req, State) when is_function(Fun, 3) ->
    Fun(Phase, Req, State#handler_state.opts);
apply_middleware(_Phase, _Middleware, _Req, _State) ->
    skip.

%%====================================================================
%% JSON-RPC Helpers
%%====================================================================

%% @private Construct a JSON-RPC 2.0 success response.
make_jsonrpc_response(Id, Result) ->
    #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"result">> => Result,
        <<"id">> => Id
    }.

%% @private Construct a JSON-RPC 2.0 error response.
make_jsonrpc_error(Id, Code, Message) ->
    #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => #{
            <<"code">> => Code,
            <<"message">> => Message
        },
        <<"id">> => Id
    }.

%% @private Construct a JSON-RPC 2.0 error response with data.
make_jsonrpc_error(Id, Code, Message, Data) ->
    #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => #{
            <<"code">> => Code,
            <<"message">> => Message,
            <<"data">> => Data
        },
        <<"id">> => Id
    }.

%%====================================================================
%% Utility Helpers
%%====================================================================

%% @private JSON response headers.
json_headers() ->
    #{<<"content-type">> => <<"application/json">>}.

%% @private CORS headers for cross-origin requests.
cors_headers() ->
    #{
        <<"access-control-allow-origin">> => <<"*">>,
        <<"access-control-allow-methods">> => <<"GET, POST, PUT, DELETE, OPTIONS">>,
        <<"access-control-allow-headers">> => <<"content-type, authorization, x-request-id">>,
        <<"access-control-max-age">> => <<"86400">>
    }.

%% @private Convert HTTP status code to JSON-RPC error code.
status_to_jsonrpc_code(400) -> ?JSONRPC_INVALID_REQUEST;
status_to_jsonrpc_code(401) -> ?A2A_AUTHENTICATION_REQUIRED;
status_to_jsonrpc_code(404) -> ?A2A_TASK_NOT_FOUND;
status_to_jsonrpc_code(405) -> ?JSONRPC_METHOD_NOT_FOUND;
status_to_jsonrpc_code(429) -> -32005;  %% Rate limited
status_to_jsonrpc_code(500) -> ?JSONRPC_INTERNAL_ERROR;
status_to_jsonrpc_code(_) -> ?JSONRPC_INTERNAL_ERROR.

%% @private Ensure a decoded JSON value is a map.
ensure_map(Value) when is_map(Value) -> Value;
ensure_map(Value) -> #{<<"_value">> => Value}.

%% @private Convert proplist-style opts to map.
opts_to_map([]) -> #{};
opts_to_map(Opts) when is_list(Opts) ->
    maps:from_list([{K, V} || {K, V} <- Opts]);
opts_to_map(Opts) when is_map(Opts) -> Opts.

%% @private Log request completion for observability.
log_request_completion(Reason, Req, _State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    case Reason of
        normal ->
            logger:debug("BeamAI HTTP request completed: ~s ~s", [Method, Path]);
        {normal, _} ->
            logger:debug("BeamAI HTTP request completed: ~s ~s", [Method, Path]);
        Other ->
            logger:warning("BeamAI HTTP request terminated: ~s ~s reason=~p",
                           [Method, Path, Other])
    end.
