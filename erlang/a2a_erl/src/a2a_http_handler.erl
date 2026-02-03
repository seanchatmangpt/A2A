%%% @doc A2A HTTP Handler for JSON-RPC endpoints
%%%
%%% This module implements the HTTP/JSON-RPC interface for the A2A protocol.
%%% Uses Cowboy web server (OTP 28 compatible).
%%%
%%% Endpoints:
%%% - POST /message:send       - SendMessage
%%% - POST /message:stream     - SendStreamingMessage (SSE)
%%% - GET  /tasks/{id}         - GetTask
%%% - GET  /tasks              - ListTasks
%%% - POST /tasks/{id}:cancel  - CancelTask
%%% - GET  /tasks/{id}:subscribe - SubscribeToTask (SSE)
%%% - GET  /.well-known/agent-card.json - Agent discovery
-module(a2a_http_handler).
-behaviour(cowboy_handler).

-include("a2a.hrl").

%% Cowboy callbacks
-export([init/2]).

%% Internal API for routing
-export([
    handle_send_message/2,
    handle_get_task/2,
    handle_list_tasks/2,
    handle_cancel_task/2
]).

%%% ============================================================================
%%% Cowboy Handler
%%% ============================================================================

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),

    %% Route to appropriate handler
    {Status, Headers, Body, Req1} = route_request(Method, Path, Req0),

    Req = cowboy_req:reply(Status, Headers, Body, Req1),
    {ok, Req, State}.

%%% ============================================================================
%%% Request Routing
%%% ============================================================================

route_request(<<"POST">>, <<"/message:send">>, Req) ->
    handle_send_message(Req, false);

route_request(<<"POST">>, <<"/message:stream">>, Req) ->
    %% Streaming handled by a2a_sse_handler
    handle_streaming_message(Req);

route_request(<<"GET">>, <<"/tasks/", TaskId/binary>>, Req) ->
    %% Check if it's a subscribe request
    case binary:match(TaskId, <<":subscribe">>) of
        {Pos, _} ->
            ActualId = binary:part(TaskId, 0, Pos),
            handle_subscribe(Req, ActualId);
        nomatch ->
            %% Check for :cancel
            case binary:match(TaskId, <<":cancel">>) of
                nomatch ->
                    handle_get_task(Req, TaskId);
                _ ->
                    {405, json_headers(), error_response(<<"Method not allowed">>), Req}
            end
    end;

route_request(<<"POST">>, <<"/tasks/", TaskId/binary>>, Req) ->
    case binary:match(TaskId, <<":cancel">>) of
        {Pos, _} ->
            ActualId = binary:part(TaskId, 0, Pos),
            handle_cancel_task(Req, ActualId);
        nomatch ->
            {404, json_headers(), error_response(<<"Not found">>), Req}
    end;

route_request(<<"GET">>, <<"/tasks">>, Req) ->
    handle_list_tasks(Req, undefined);

route_request(<<"GET">>, <<"/.well-known/agent-card.json">>, Req) ->
    handle_agent_card(Req);

route_request(<<"GET">>, <<"/extendedAgentCard">>, Req) ->
    handle_extended_agent_card(Req);

route_request(<<"OPTIONS">>, _Path, Req) ->
    %% CORS preflight
    {204, cors_headers(), <<>>, Req};

route_request(_Method, _Path, Req) ->
    {404, json_headers(), error_response(<<"Not found">>), Req}.

%%% ============================================================================
%%% Handler Implementations
%%% ============================================================================

%% POST /message:send
handle_send_message(Req0, _Blocking) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),

    case a2a_json:decode_jsonrpc_request(Body) of
        {ok, #jsonrpc_request{method = <<"message/send">>, params = Params, id = ReqId}} ->
            case a2a_json:decode_send_message_request(Params) of
                {ok, SendReq} ->
                    %% Create or continue task
                    Message = SendReq#send_message_request.message,
                    Config = SendReq#send_message_request.configuration,

                    Result = case Message#message.task_id of
                        undefined ->
                            %% New task
                            create_new_task(Message, Config);
                        TaskId ->
                            %% Continue existing task
                            continue_task(TaskId, Message)
                    end,

                    case Result of
                        {ok, Task} ->
                            Response = make_jsonrpc_response(ReqId,
                                #{<<"task">> => a2a_json:encode_task(Task)}),
                            {200, json_headers(), Response, Req};
                        {error, _Reason} ->
                            %% This case handles actual errors from get_task
                            %% The {ok, message, Msg} pattern is handled below
                            {400, json_headers(),
                             make_jsonrpc_error(ReqId, ?JSONRPC_INTERNAL_ERROR, <<"Task not found">>), Req}
                    end;
                {error, _} ->
                    {400, json_headers(),
                     make_jsonrpc_error(ReqId, ?JSONRPC_INVALID_PARAMS, <<"Invalid params">>), Req}
            end;
        {ok, #jsonrpc_request{id = ReqId}} ->
            {400, json_headers(),
             make_jsonrpc_error(ReqId, ?JSONRPC_METHOD_NOT_FOUND, <<"Method not found">>), Req};
        {error, _} ->
            {400, json_headers(),
             make_jsonrpc_error(null, ?JSONRPC_PARSE_ERROR, <<"Parse error">>), Req}
    end.

%% POST /message:stream - Upgrade to SSE
handle_streaming_message(Req) ->
    %% This will be handled by a2a_sse_handler
    %% Return error if called directly
    {400, json_headers(), error_response(<<"Use SSE endpoint">>), Req}.

%% GET /tasks/{id}
handle_get_task(Req, TaskId) ->
    HistoryLength = case cowboy_req:match_qs([{historyLength, int, undefined}], Req) of
        #{historyLength := HL} -> HL;
        _ -> undefined
    end,

    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            %% Apply history limit if specified
            FinalTask = case HistoryLength of
                undefined -> Task;
                0 -> Task#task{history = []};
                N when N > 0 ->
                    History = Task#task.history,
                    Len = length(History),
                    if
                        Len =< N -> Task;
                        true -> Task#task{history = lists:nthtail(Len - N, History)}
                    end;
                _ -> Task
            end,

            Response = make_jsonrpc_response(null, a2a_json:encode_task(FinalTask)),
            {200, json_headers(), Response, Req};
        {error, not_found} ->
            {404, json_headers(),
             make_jsonrpc_error(null, ?A2A_TASK_NOT_FOUND, <<"Task not found">>), Req}
    end.

%% GET /tasks
handle_list_tasks(Req, _Opts) ->
    QsParams = cowboy_req:parse_qs(Req),

    Opts = #{
        context_id => proplists:get_value(<<"contextId">>, QsParams),
        status => case proplists:get_value(<<"status">>, QsParams) of
            undefined -> undefined;
            S -> a2a_json:json_to_task_state(S)
        end,
        page_size => case proplists:get_value(<<"pageSize">>, QsParams) of
            undefined -> 50;
            PS -> binary_to_integer(PS)
        end,
        page_token => proplists:get_value(<<"pageToken">>, QsParams),
        history_length => case proplists:get_value(<<"historyLength">>, QsParams) of
            undefined -> undefined;
            HL -> binary_to_integer(HL)
        end,
        include_artifacts => proplists:get_value(<<"includeArtifacts">>, QsParams) =:= <<"true">>
    },

    {ok, Tasks, NextPageToken} = a2a_task_store:list_tasks(Opts),

    Response = make_jsonrpc_response(null, #{
        <<"tasks">> => [a2a_json:encode_task(T) || T <- Tasks],
        <<"nextPageToken">> => NextPageToken,
        <<"pageSize">> => maps:get(page_size, Opts),
        <<"totalSize">> => length(Tasks)
    }),
    {200, json_headers(), Response, Req}.

%% POST /tasks/{id}:cancel
handle_cancel_task(Req, TaskId) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            case a2a_task_statem:cancel_task(Pid) of
                {ok, Task} ->
                    Response = make_jsonrpc_response(null, a2a_json:encode_task(Task)),
                    {200, json_headers(), Response, Req};
                {error, task_terminal} ->
                    {400, json_headers(),
                     make_jsonrpc_error(null, ?A2A_TASK_ALREADY_TERMINAL,
                                        <<"Task already in terminal state">>), Req}
            end;
        {error, not_found} ->
            {404, json_headers(),
             make_jsonrpc_error(null, ?A2A_TASK_NOT_FOUND, <<"Task not found">>), Req}
    end.

%% GET /tasks/{id}:subscribe - Upgrade to SSE
handle_subscribe(Req, TaskId) ->
    %% Check if task exists and is not terminal
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            State = (Task#task.status)#task_status.state,
            case lists:member(State, ?TERMINAL_STATES) of
                true ->
                    {400, json_headers(),
                     make_jsonrpc_error(null, ?A2A_UNSUPPORTED_OPERATION,
                                        <<"Cannot subscribe to terminal task">>), Req};
                false ->
                    %% Return instruction to use SSE handler
                    {200, json_headers(),
                     make_jsonrpc_response(null, #{
                         <<"message">> => <<"Use SSE connection for subscription">>,
                         <<"taskId">> => TaskId
                     }), Req}
            end;
        {error, not_found} ->
            {404, json_headers(),
             make_jsonrpc_error(null, ?A2A_TASK_NOT_FOUND, <<"Task not found">>), Req}
    end.

%% GET /.well-known/agent-card.json
handle_agent_card(Req) ->
    AgentCard = a2a_agent_card:get_card(),
    Body = json:encode(a2a_json:encode_agent_card(AgentCard)),
    {200, json_headers(), Body, Req}.

%% GET /extendedAgentCard
handle_extended_agent_card(Req) ->
    %% Check authentication first
    case check_auth(Req) of
        ok ->
            AgentCard = a2a_agent_card:get_extended_card(),
            Body = json:encode(a2a_json:encode_agent_card(AgentCard)),
            {200, json_headers(), Body, Req};
        {error, unauthorized} ->
            {401, json_headers(),
             make_jsonrpc_error(null, ?A2A_AUTHENTICATION_REQUIRED,
                                <<"Authentication required">>), Req}
    end.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% Create a new task from message
create_new_task(Message, Config) ->
    Opts = case Config of
        undefined -> #{};
        #send_message_configuration{} ->
            #{blocking => Config#send_message_configuration.blocking}
    end,

    case a2a_task_statem:start_link(Message, Opts) of
        {ok, Pid} ->
            %% Get the task state
            a2a_task_statem:get_task(Pid);
        Error ->
            Error
    end.

%% Continue an existing task
continue_task(TaskId, Message) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            a2a_task_statem:send_message(Pid, Message);
        {error, not_found} ->
            {error, task_not_found}
    end.

%% Check authentication
check_auth(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        undefined -> {error, unauthorized};
        _Token ->
            %% In a real implementation, validate the token
            ok
    end.

%% JSON headers
json_headers() ->
    #{
        <<"content-type">> => <<"application/json">>,
        <<"access-control-allow-origin">> => <<"*">>
    }.

%% CORS headers for preflight
cors_headers() ->
    #{
        <<"access-control-allow-origin">> => <<"*">>,
        <<"access-control-allow-methods">> => <<"GET, POST, OPTIONS">>,
        <<"access-control-allow-headers">> => <<"content-type, authorization">>,
        <<"access-control-max-age">> => <<"86400">>
    }.

%% Make JSON-RPC response
make_jsonrpc_response(Id, Result) ->
    json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"result">> => Result,
        <<"id">> => Id
    }).

%% Make JSON-RPC error response
make_jsonrpc_error(Id, Code, Message) ->
    json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => #{
            <<"code">> => Code,
            <<"message">> => Message
        },
        <<"id">> => Id
    }).

%% Simple error response
error_response(Message) ->
    json:encode(#{<<"error">> => Message}).
