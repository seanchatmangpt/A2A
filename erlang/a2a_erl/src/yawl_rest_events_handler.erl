%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST Workflow Events Handler (SSE)
%%%
%%% This module provides Server-Sent Events (SSE) endpoint for streaming
%%% workflow events in real-time to clients.
%%%
%%% ## Endpoints
%%%
%%% - `GET /workflows/{id}/events` - Stream events for a specific workflow
%%% - `GET /workflows/events` - Stream events for all workflows
%%% - `GET /events` - Global events stream
%%%
%%% ## Query Parameters
%%%
%%% - `event_types` - Comma-separated list of event types to filter
%%% - `since` - Timestamp to start streaming from (milliseconds)
%%% - `heartbeat` - Heartbeat interval in seconds (default: 30)
%%%
%%% ## Usage Example
%%%
%%% ```bash
%%% # Stream events for a specific workflow
%%% curl -N http://localhost:8081/workflows/wf_123/events
%%%
%%% # Stream specific event types
%%% curl -N "http://localhost:8081/workflows/wf_123/events?event_types=task_complete,workflow_start"
%%%
%%% # Stream with JavaScript EventSource
%%% const es = new EventSource('/workflows/wf_123/events');
%%% es.addEventListener('task_complete', (e) => {
%%%     const data = JSON.parse(e.data);
%%%     console.log('Task completed:', data);
%%% });
%%% ```
%%%
%%% ## Event Types
%%%
%%% - `workflow_start` - Workflow execution started
%%% - `workflow_complete` - Workflow execution completed
%%% - `workflow_cancel` - Workflow execution cancelled
%%% - `workflow_error` - Workflow execution error
%%% - `task_start` - Task execution started
%%% - `task_complete` - Task execution completed
%%% - `task_fail` - Task execution failed
%%% - `marking_change` - Workflow marking changed
%%% - `resource_allocated` - Resource allocated to task
%%% - `resource_deallocated` - Resource deallocated
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_events_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    init/3,
    rest_init/2,
    info/3,
    terminate/3
]).

%% Include files
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    workflow_id :: binary() | undefined,
    subscriber_id :: binary(),
    event_types :: [atom()] | undefined,
    since :: integer() | undefined,
    heartbeat_interval :: non_neg_integer(),
    heartbeat_ref :: reference() | undefined,
    last_event_id :: binary() | undefined
}).

%% Subscriber record for SSE event tracking
-record(subscriber, {
    pid :: pid(),
    workflow_id :: binary() | undefined,
    event_types :: [atom()] | undefined,
    subscribe_time :: integer()
}).

%%====================================================================
%% Constants
%%====================================================================

-define(DEFAULT_HEARTBEAT, 30).
-define(SUBSCRIBER_TABLE, yawl_sse_subscribers).
-define(EVENT_BUFFER_SIZE, 100).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    init(Req, State, #{}).

%% @private
init(Req, _State, _Opts) ->
    %% For GET requests, we'll use REST semantics but switch to streaming
    {cowboy_rest, Req, #{}}.

%% @private
rest_init(Req, _Opts) ->
    %% Extract bindings and parameters
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    {EventTypesBin, _} = cowboy_req:qs_val(<<"event_types">>, Req, <<>>),
    {SinceBin, _} = cowboy_req:qs_val(<<"since">>, Req, <<>>),
    {HeartbeatBin, _} = cowboy_req:qs_val(<<"heartbeat">>, Req, <<"30">>),

    %% Parse event types
    EventTypes = case EventTypesBin of
        <<>> -> undefined;
        _ -> [binary_to_existing_atom(B, utf8) || B <- binary:split(EventTypesBin, <<",">>, [global])]
    end,

    %% Parse since timestamp
    Since = case SinceBin of
        <<>> -> undefined;
        _ -> binary_to_integer(SinceBin)
    end,

    %% Parse heartbeat interval
    HeartbeatInterval = case HeartbeatBin of
        <<>> -> ?DEFAULT_HEARTBEAT;
        _ -> max(5, binary_to_integer(HeartbeatBin))
    end,

    %% Generate subscriber ID
    SubscriberId = generate_subscriber_id(),

    %% Set SSE headers
    Req2 = set_sse_headers(Req),

    %% Start streaming response
    Req3 = cowboy_req:stream_reply(200, Req2),

    %% Send initial connection event
    send_sse_event(Req3, <<"connected">>, #{
        subscriber_id => SubscriberId,
        workflow_id => WorkflowId,
        timestamp => erlang:system_time(millisecond),
        heartbeat_interval => HeartbeatInterval
    }),

    %% Register subscriber for events
    register_subscriber(self(), WorkflowId, EventTypes),

    %% Start heartbeat timer
    HeartbeatRef = erlang:send_after(HeartbeatInterval * 1000, self(), heartbeat),

    %% Send buffered events if since timestamp provided
    case Since of
        undefined -> ok;
        _ -> send_buffered_events(Req3, WorkflowId, Since, EventTypes)
    end,

    {ok, Req3, #state{
        workflow_id => WorkflowId,
        subscriber_id => SubscriberId,
        event_types => EventTypes,
        since => Since,
        heartbeat_interval => HeartbeatInterval,
        heartbeat_ref => HeartbeatRef
    }}.

%% @private
info({sse_event, EventType, EventData}, Req, State) ->
    %% Filter by event types if specified
    case should_send_event(EventType, State) of
        true ->
            send_sse_event(Req, EventType, EventData);
        false ->
            ok
    end,
    {ok, Req, State};

info(heartbeat, Req, #state{heartbeat_interval = Interval} = State) ->
    %% Send heartbeat comment to keep connection alive
    cowboy_req:stream_body(<<":heartbeat\r\n\r\n">>, Req),
    %% Schedule next heartbeat
    HeartbeatRef = erlang:send_after(Interval * 1000, self(), heartbeat),
    {ok, Req, State#state{heartbeat_ref = HeartbeatRef}};

info({workflow_event, WorkflowId, EventType, EventData}, Req, State) ->
    %% Handle workflow event
    case should_send_workflow_event(WorkflowId, EventType, State) of
        true ->
            send_sse_event(Req, EventType, EventData);
        false ->
            ok
    end,
    {ok, Req, State};

info(_Info, Req, State) ->
    {ok, Req, State}.

%% @private
terminate(_Reason, _Req, #state{subscriber_id = SubscriberId}) ->
    unregister_subscriber(SubscriberId),
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
set_sse_headers(Req) ->
    Req2 = cowboy_req:set_resp_header(<<"content-type">>, <<"text/event-stream">>, Req),
    Req3 = cowboy_req:set_resp_header(<<"cache-control">>, <<"no-cache">>, Req2),
    Req4 = cowboy_req:set_resp_header(<<"connection">>, <<"keep-alive">>, Req3),
    Req5 = cowboy_req:set_resp_header(<<"x-accel-buffering">>, <<"no">>, Req4),

    %% Add CORS headers for SSE
    AllowedOrigin = case cowboy_req:header(<<"origin">>, Req) of
        undefined -> <<"*">>;
        Origin -> Origin
    end,
    cowboy_req:set_resp_header(<<"access-control-allow-origin">>, AllowedOrigin, Req5).

%% @private
send_sse_event(Req, EventName, Data) ->
    EventJson = jiffy:encode(Data),
    EventId = base64:encode(crypto:strong_rand_bytes(16)),

    Event = [
        <<"id: ">>, EventId, <<"\r\n">>,
        <<"event: ">>, format_event_name(EventName), <<"\r\n">>,
        <<"data: ">>, EventJson, <<"\r\n\r\n">>
    ],

    cowboy_req:stream_body(Event, fin, Req).

%% @private
format_event_name(EventName) when is_atom(EventName) ->
    atom_to_binary(EventName, utf8);
format_event_name(EventName) when is_binary(EventName) ->
    EventName.

%% @private
should_send_event(_EventType, #state{event_types = undefined}) ->
    true;
should_send_event(EventType, #state{event_types = EventTypes}) ->
    lists:member(EventType, EventTypes).

%% @private
should_send_workflow_event(_WorkflowId, EventType, State) ->
    %% First check if event type matches
    case should_send_event(EventType, State) of
        false -> false;
        true ->
            %% Then check if workflow matches
            case State#state.workflow_id of
                undefined -> true;
                WorkflowId when WorkflowId =:= _WorkflowId -> true;
                _ -> false
            end
    end.

%% @private
send_buffered_events(Req, WorkflowId, Since, EventTypes) ->
    case yawl_persistence:get_events_since(WorkflowId, Since, EventTypes) of
        {ok, Events} ->
            lists:foreach(fun(Event) ->
                #yawl_execution_history{
                    event_type = EventType,
                    event_data = EventData,
                    timestamp = Timestamp
                } = Event,

                case EventTypes of
                    undefined ->
                        send_sse_event(Req, EventType, EventData#{
                            timestamp => Timestamp,
                            buffered => true
                        });
                    Types ->
                        case lists:member(EventType, Types) of
                            true ->
                                send_sse_event(Req, EventType, EventData#{
                                    timestamp => Timestamp,
                                    buffered => true
                                });
                            false ->
                                ok
                        end
                end
            end, Events);
        {error, _} ->
            ok
    end.

%% @private
register_subscriber(Pid, WorkflowId, EventTypes) ->
    %% Ensure ETS table exists
    case ets:whereis(?SUBSCRIBER_TABLE) of
        undefined ->
            ets:new(?SUBSCRIBER_TABLE, [named_table, public, bag, {keypos, #subscriber.pid}]);
        _ -> ok
    end,

    Subscriber = #subscriber{
        pid = Pid,
        workflow_id = WorkflowId,
        event_types = EventTypes,
        subscribe_time = erlang:monotonic_time(millisecond)
    },

    ets:insert(?SUBSCRIBER_TABLE, Subscriber).

%% @private
unregister_subscriber(_SubscriberId) ->
    case ets:whereis(?SUBSCRIBER_TABLE) of
        undefined -> ok;
        _ ->
            ets:match_delete(?SUBSCRIBER_TABLE, #subscriber{pid = self(), _ = '_'})
    end.

%% @private
generate_subscriber_id() ->
    Timestamp = erlang:monotonic_time(millisecond),
    Random = rand:uniform(1000000),
    <<"sub_", (integer_to_binary(Timestamp))/binary, "_", (integer_to_binary(Random))/binary>>.

%%====================================================================
%% Public API (for broadcasting events)
%%====================================================================

%% @doc Broadcast an event to all subscribers.
-spec broadcast_event(atom(), map()) -> ok.
broadcast_event(EventType, EventData) ->
    broadcast_event_filtered(EventType, EventData, fun(_) -> true end).

%% @doc Broadcast a workflow event to relevant subscribers.
-spec broadcast_workflow_event(binary(), atom(), map()) -> ok.
broadcast_workflow_event(WorkflowId, EventType, EventData) ->
    broadcast_event_filtered(EventType, EventData, fun(Subscriber) ->
        case Subscriber#subscriber.workflow_id of
            undefined -> true;
            WfId when WfId =:= WorkflowId -> true;
            _ -> false
        end
    end).

%% @private
broadcast_event_filtered(EventType, EventData, FilterFn) ->
    case ets:whereis(?SUBSCRIBER_TABLE) of
        undefined -> ok;
        _ ->
            Subscribers = ets:tab2list(?SUBSCRIBER_TABLE),
            lists:foreach(fun(Subscriber) ->
                case FilterFn(Subscriber) of
                    true ->
                        %% Check event type filter
                        case Subscriber#subscriber.event_types of
                            undefined ->
                                send_event_to_subscriber(Subscriber, EventType, EventData);
                            Types ->
                                case lists:member(EventType, Types) of
                                    true -> send_event_to_subscriber(Subscriber, EventType, EventData);
                                    false -> ok
                                end
                        end;
                    false -> ok
                end
            end, Subscribers)
    end.

%% @private
send_event_to_subscriber(#subscriber{pid = Pid}, EventType, EventData) when is_pid(Pid) ->
    try
        Pid ! {sse_event, EventType, EventData}
    catch
        _:_ -> ok
    end;
send_event_to_subscriber(_, _EventType, _EventData) ->
    ok.
