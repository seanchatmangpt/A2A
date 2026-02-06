%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Cowboy HTTP Handler
%%%
%%% Bridges Cowboy HTTP requests to the BeamAI A2A server.  Handles:
%%%
%%% - POST requests containing JSON-RPC payloads (routed to
%%%   beamai_a2a_server)
%%% - GET requests for SSE subscriptions (upgraded to cowboy_loop)
%%% - GET /.well-known/agent-card.json (agent discovery)
%%% - OPTIONS for CORS preflight
%%%
%%% This handler integrates with the existing a2a_http_handler
%%% patterns while adding the BeamAI middleware pipeline (auth,
%%% rate limiting, etc.) on top.
%%%
%%% Cowboy route configuration example:
%%%   {"/a2a", beamai_a2a_cowboy_handler,
%%%    #{server => beamai_a2a_server}}
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_cowboy_handler).
-behaviour(cowboy_handler).

-include("a2a.hrl").

%% Cowboy handler callback
-export([init/2]).

%% SSE loop handler callbacks (used when upgrading to SSE)
-export([
    info/3,
    terminate/3
]).

-record(sse_state, {
    task_id       :: binary(),
    task_pid      :: pid(),
    monitor_ref   :: reference(),
    sub_ref       :: reference() | undefined,
    server        :: atom()
}).

%%====================================================================
%% Cowboy handler
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the Cowboy handler.
%%
%% Routes the request based on HTTP method and path.
%% @end
%%--------------------------------------------------------------------
init(Req0, Opts) ->
    Server = maps:get(server, Opts, beamai_a2a_server),
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),

    case {Method, Path} of
        {<<"POST">>, _} ->
            handle_post(Req0, Server);
        {<<"GET">>, <<"/.well-known/agent-card.json">>} ->
            handle_agent_card(Req0, Server);
        {<<"GET">>, _} ->
            handle_get_sse(Req0, Server);
        {<<"OPTIONS">>, _} ->
            handle_cors_preflight(Req0);
        _ ->
            reply_error(Req0, 404, null, -32601, <<"Not found">>)
    end.

%%====================================================================
%% POST handler - JSON-RPC
%%====================================================================

%% @doc Handle POST requests containing JSON-RPC payloads.
-spec handle_post(cowboy_req:req(), atom()) ->
    {ok, cowboy_req:req(), term()}.
handle_post(Req0, Server) ->
    case cowboy_req:header(<<"content-type">>, Req0) of
        <<"application/json", _/binary>> ->
            handle_jsonrpc_post(Req0, Server);
        undefined ->
            %% Be lenient: assume JSON if no content-type
            handle_jsonrpc_post(Req0, Server);
        _Other ->
            reply_error(Req0, 415, null, -32600,
                        <<"Unsupported content type; use application/json">>)
    end.

%% @doc Read body and delegate to the A2A server.
handle_jsonrpc_post(Req0, Server) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),

    %% Build auth context from request headers
    AuthInfo = extract_auth_info(Req1),

    %% Decode, process through server, get response
    ResponseJson = case AuthInfo of
        #{} when map_size(AuthInfo) =:= 0 ->
            beamai_a2a_server:handle_json(Server, Body);
        _ ->
            %% Decode first, then handle with auth
            case beamai_a2a_jsonrpc:decode(Body) of
                {ok, Request} ->
                    beamai_a2a_server:handle_request_with_auth(
                        Server, Request, AuthInfo);
                {batch, _Items} ->
                    %% For batch, let the server handle it
                    beamai_a2a_server:handle_json(Server, Body);
                {error, ErrorObj} ->
                    beamai_a2a_jsonrpc:encode_error(null,
                        maps:get(<<"code">>, ErrorObj),
                        maps:get(<<"message">>, ErrorObj))
            end
    end,

    %% Check if the response indicates a subscription request
    case maybe_upgrade_to_sse(ResponseJson, Req1, Server) of
        {upgrade, Req2, SseState} ->
            start_sse(Req2, SseState);
        {no_upgrade, _} ->
            Req = cowboy_req:reply(200, json_headers(), ResponseJson, Req1),
            {ok, Req, #{}}
    end.

%%====================================================================
%% GET handler - Agent Card and SSE
%%====================================================================

%% @doc Serve the agent card for discovery.
handle_agent_card(Req0, Server) ->
    AgentCard = beamai_a2a_server:get_agent_card(Server),
    CardMap = a2a_json:encode_agent_card(AgentCard),
    Body = iolist_to_binary(json:encode(CardMap)),
    Req = cowboy_req:reply(200, json_headers(), Body, Req0),
    {ok, Req, #{}}.

%% @doc Handle GET requests for SSE task subscriptions.
%%
%% Expects a query parameter `taskId' or path segment.
handle_get_sse(Req0, Server) ->
    %% Try to extract task ID from query params or path
    TaskId = extract_task_id(Req0),
    case TaskId of
        undefined ->
            reply_error(Req0, 400, null, -32600,
                        <<"Missing taskId for SSE subscription">>);
        _ ->
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    State = (Task#task.status)#task_status.state,
                    case beamai_a2a_types:is_terminal(State) of
                        true ->
                            reply_error(Req0, 400, null, -32003,
                                <<"Cannot subscribe to terminal task">>);
                        false ->
                            setup_sse_subscription(Req0, TaskId, Server)
                    end;
                {error, not_found} ->
                    reply_error(Req0, 404, null, -32001,
                                <<"Task not found">>)
            end
    end.

%%====================================================================
%% CORS
%%====================================================================

handle_cors_preflight(Req0) ->
    Headers = #{
        <<"access-control-allow-origin">>  => <<"*">>,
        <<"access-control-allow-methods">> => <<"GET, POST, OPTIONS">>,
        <<"access-control-allow-headers">> =>
            <<"content-type, authorization, x-a2a-token">>,
        <<"access-control-max-age">>       => <<"86400">>
    },
    Req = cowboy_req:reply(204, Headers, <<>>, Req0),
    {ok, Req, #{}}.

%%====================================================================
%% SSE (Server-Sent Events) support
%%====================================================================

%% @doc Set up an SSE subscription for a task.
-spec setup_sse_subscription(cowboy_req:req(), binary(), atom()) ->
    {cowboy_loop, cowboy_req:req(), #sse_state{}}.
setup_sse_subscription(Req0, TaskId, Server) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            %% Subscribe to task updates
            {ok, SubRef} = a2a_task_statem:subscribe(Pid),
            MonRef = erlang:monitor(process, Pid),

            %% Start SSE stream
            Headers = sse_headers(),
            Req = cowboy_req:stream_reply(200, Headers, Req0),

            %% Send initial task state
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    TaskMap = beamai_a2a_convert:task_to_map(Task),
                    send_sse_event(Req, <<"task">>, TaskMap);
                _ -> ok
            end,

            %% Schedule keepalive
            schedule_keepalive(),

            SseState = #sse_state{
                task_id = TaskId,
                task_pid = Pid,
                monitor_ref = MonRef,
                sub_ref = SubRef,
                server = Server
            },
            {cowboy_loop, Req, SseState};
        {error, not_found} ->
            reply_error(Req0, 404, null, -32001, <<"Task not found">>)
    end.

%% @doc Start SSE after a POST that returned a subscribe result.
-spec start_sse(cowboy_req:req(), #sse_state{}) ->
    {cowboy_loop, cowboy_req:req(), #sse_state{}}.
start_sse(Req0, SseState) ->
    Headers = sse_headers(),
    Req = cowboy_req:stream_reply(200, Headers, Req0),

    %% Send initial task state
    TaskId = SseState#sse_state.task_id,
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            TaskMap = beamai_a2a_convert:task_to_map(Task),
            send_sse_event(Req, <<"task">>, TaskMap);
        _ -> ok
    end,

    schedule_keepalive(),
    {cowboy_loop, Req, SseState}.

%%--------------------------------------------------------------------
%% @doc Handle SSE info messages (cowboy_loop callback).
%% @end
%%--------------------------------------------------------------------
info({a2a_task_event, TaskId, Event}, Req,
     #sse_state{task_id = TaskId} = State) ->
    case Event of
        {state_changed, NewState} ->
            %% Build and send status update
            StatusMap = #{
                <<"taskId">> => TaskId,
                <<"state">>  => atom_to_binary(NewState, utf8),
                <<"timestamp">> => beamai_a2a_utils:now_ms()
            },
            send_sse_event(Req, <<"status_update">>, StatusMap),

            case beamai_a2a_types:is_terminal(NewState) of
                true ->
                    %% Send a final "done" event and close
                    send_sse_event(Req, <<"done">>,
                                   #{<<"taskId">> => TaskId}),
                    {stop, Req, State};
                false ->
                    {ok, Req, State}
            end;

        {artifact_update, ArtEvent} ->
            ArtMap = #{
                <<"taskId">>    => TaskId,
                <<"artifact">>  => beamai_a2a_convert:artifact_to_map(
                    ArtEvent#task_artifact_update_event.artifact),
                <<"append">>    => ArtEvent#task_artifact_update_event.append,
                <<"lastChunk">> => ArtEvent#task_artifact_update_event.last_chunk
            },
            send_sse_event(Req, <<"artifact_update">>, ArtMap),
            {ok, Req, State};

        _ ->
            {ok, Req, State}
    end;

info({'DOWN', Ref, process, _Pid, Reason}, Req,
     #sse_state{monitor_ref = Ref} = State) ->
    logger:warning("Task process died during SSE: ~p", [Reason]),
    send_sse_event(Req, <<"error">>, #{
        <<"error">>  => <<"Task process terminated">>,
        <<"reason">> => beamai_a2a_utils:to_binary(Reason)
    }),
    {stop, Req, State};

info(keepalive, Req, State) ->
    send_sse_comment(Req, <<"keepalive">>),
    schedule_keepalive(),
    {ok, Req, State};

info(_Info, Req, State) ->
    {ok, Req, State}.

%%--------------------------------------------------------------------
%% @doc Terminate the SSE connection (cowboy_loop callback).
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _Req, #sse_state{sub_ref = SubRef,
                                      task_pid = Pid}) ->
    case SubRef of
        undefined -> ok;
        Ref when is_pid(Pid) ->
            try a2a_task_statem:unsubscribe(Pid, Ref)
            catch _:_ -> ok
            end;
        _ -> ok
    end,
    ok;
terminate(_Reason, _Req, _State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Check if a JSON response contains a subscribe directive and
%% upgrade to SSE if so.
-spec maybe_upgrade_to_sse(binary(), cowboy_req:req(), atom()) ->
    {upgrade, cowboy_req:req(), #sse_state{}} | {no_upgrade, binary()}.
maybe_upgrade_to_sse(ResponseJson, Req, Server) ->
    try
        Decoded = json:decode(ResponseJson),
        case maps:get(<<"result">>, Decoded, undefined) of
            #{<<"subscribe">> := true, <<"taskId">> := TaskId} ->
                case a2a_task_store:get_task_pid(TaskId) of
                    {ok, Pid} ->
                        {ok, SubRef} = a2a_task_statem:subscribe(Pid),
                        MonRef = erlang:monitor(process, Pid),
                        SseState = #sse_state{
                            task_id = TaskId,
                            task_pid = Pid,
                            monitor_ref = MonRef,
                            sub_ref = SubRef,
                            server = Server
                        },
                        {upgrade, Req, SseState};
                    _ ->
                        {no_upgrade, ResponseJson}
                end;
            _ ->
                {no_upgrade, ResponseJson}
        end
    catch
        _:_ -> {no_upgrade, ResponseJson}
    end.

%% @doc Extract authentication information from request headers.
-spec extract_auth_info(cowboy_req:req()) -> map().
extract_auth_info(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        undefined -> #{};
        AuthHeader -> #{<<"authorization">> => AuthHeader}
    end.

%% @doc Extract task ID from query params or path.
-spec extract_task_id(cowboy_req:req()) -> binary() | undefined.
extract_task_id(Req) ->
    %% Check query params first
    case cowboy_req:match_qs([{taskId, [], undefined}], Req) of
        #{taskId := TaskId} when TaskId =/= undefined ->
            TaskId;
        _ ->
            %% Check path for /tasks/{id}:subscribe pattern
            Path = cowboy_req:path(Req),
            case Path of
                <<"/tasks/", Rest/binary>> ->
                    case binary:match(Rest, <<":subscribe">>) of
                        {Pos, _} -> binary:part(Rest, 0, Pos);
                        nomatch ->
                            case binary:match(Rest, <<":resubscribe">>) of
                                {Pos2, _} -> binary:part(Rest, 0, Pos2);
                                nomatch -> Rest
                            end
                    end;
                _ -> undefined
            end
    end.

%% @doc Send an SSE event with a named event type and JSON data.
-spec send_sse_event(cowboy_req:req(), binary(), map()) -> ok.
send_sse_event(Req, EventType, Data) ->
    JsonData = iolist_to_binary(json:encode(Data)),
    Chunk = [<<"event: ">>, EventType, <<"\n">>,
             <<"data: ">>, JsonData, <<"\n\n">>],
    cowboy_req:stream_body(iolist_to_binary(Chunk), nofin, Req).

%% @doc Send an SSE comment (for keepalive).
-spec send_sse_comment(cowboy_req:req(), binary()) -> ok.
send_sse_comment(Req, Comment) ->
    Chunk = [<<": ">>, Comment, <<"\n\n">>],
    cowboy_req:stream_body(iolist_to_binary(Chunk), nofin, Req).

%% @doc Schedule a keepalive ping (every 30 seconds).
-spec schedule_keepalive() -> reference().
schedule_keepalive() ->
    erlang:send_after(30000, self(), keepalive).

%% @doc JSON response headers.
-spec json_headers() -> map().
json_headers() ->
    #{
        <<"content-type">>                 => <<"application/json">>,
        <<"access-control-allow-origin">>  => <<"*">>
    }.

%% @doc SSE response headers.
-spec sse_headers() -> map().
sse_headers() ->
    #{
        <<"content-type">>                => <<"text/event-stream">>,
        <<"cache-control">>               => <<"no-cache">>,
        <<"connection">>                  => <<"keep-alive">>,
        <<"access-control-allow-origin">> => <<"*">>
    }.

%% @doc Reply with a JSON-RPC error and stop.
-spec reply_error(cowboy_req:req(), integer(), term(),
                  integer(), binary()) ->
    {ok, cowboy_req:req(), term()}.
reply_error(Req0, HttpStatus, Id, Code, Message) ->
    Body = beamai_a2a_jsonrpc:encode_error(Id, Code, Message),
    Req = cowboy_req:reply(HttpStatus, json_headers(), Body, Req0),
    {ok, Req, #{}}.
