%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Server-Sent Events (SSE) Handler
%%%
%%% This module provides real-time event streaming for workflow events
%%% using Server-Sent Events (SSE). It supports:
%%%
%%% - Event streaming to connected clients
%%% - Event filtering by type and workflow
%%% - Connection heartbeat and keepalive
%%% - Automatic reconnection handling
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_sse).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    init/3,
    rest_init/2,
    allowed_methods/2,
    content_types_provided/2,
    to_text/2,
    terminate/3
]).

%% API exports - Event broadcasting
-export([
    broadcast_event/2,
    broadcast_workflow_event/3,
    subscribe/2,
    unsubscribe/1,
    get_subscriber_count/0
]).

-include("yawl_types.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    workflow_id :: binary() | undefined,
    event_types :: [atom()] | undefined,
    subscriber_id :: binary(),
    heartbeat_ref :: reference() | undefined
}).

-record(subscriber, {
    pid :: pid(),
    workflow_id :: binary() | undefined,
    event_types :: [atom()] | undefined,
    subscribe_time :: integer()
}).

%%====================================================================
%% State
%%====================================================================

-define(SSE_HEARTBEAT_INTERVAL, 30000).
-define(SUBSCRIBER_TABLE, yawl_sse_subscribers).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    init(Req, State, #{}).

%% @private
init(Req, State, Opts) ->
    {cowboy_rest, Req, State, Opts}.

%% @private
rest_init(Req, _Opts) ->
    %% Generate subscriber ID
    SubscriberId = generate_subscriber_id(),

    %% Get query parameters
    #{workflow_id := WorkflowId, event_types := EventTypes} = parse_sse_params(Req),

    %% Set SSE headers
    Req2 = cowboy_req:stream_reply(200, #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"x-accel-buffering">> => <<"no">>
    }, Req),

    %% Send initial connection event
    send_sse_event(Req2, <<"connected">>, #{
        subscriber_id => SubscriberId,
        timestamp => erlang:system_time(millisecond)
    }),

    %% Register subscriber
    register_subscriber(SubscriberId, self(), WorkflowId, EventTypes),

    %% Start heartbeat
    HeartbeatRef = erlang:send_after(?SSE_HEARTBEAT_INTERVAL, self(), heartbeat),

    {ok, Req2, #state{
        workflow_id = WorkflowId,
        event_types = EventTypes,
        subscriber_id = SubscriberId,
        heartbeat_ref = HeartbeatRef
    }}.

%% @private
allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"text">>, <<"event-stream">>, '*'}, to_text}
    ], Req, State}.

%% @private
to_text(Req, State) ->
    %% Stream events to client
    {ok, Req, State}.

%% @private
terminate(_Reason, _Req, #state{subscriber_id = SubscriberId}) ->
    %% Unregister subscriber
    unregister_subscriber(SubscriberId),
    ok.

%%====================================================================
%% API Functions
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
            undefined -> true;  %% Global subscriber
            WfId when WfId =:= WorkflowId -> true;  %% Matching workflow
            _ -> false
        end
    end).

%% @doc Subscribe to events (for internal processes).
-spec subscribe(pid(), map()) -> {ok, binary()}.
subscribe(Pid, Options) ->
    SubscriberId = generate_subscriber_id(),
    WorkflowId = maps:get(workflow_id, Options, undefined),
    EventTypes = maps:get(event_types, Options, undefined),

    register_subscriber(SubscriberId, Pid, WorkflowId, EventTypes),
    {ok, SubscriberId}.

%% @doc Unsubscribe from events.
-spec unsubscribe(binary()) -> ok.
unsubscribe(SubscriberId) ->
    unregister_subscriber(SubscriberId),
    ok.

%% @doc Get current subscriber count.
-spec get_subscriber_count() -> non_neg_integer().
get_subscriber_count() ->
    case ets:info(?SUBSCRIBER_TABLE, size) of
        undefined -> 0;
        Count -> Count
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
parse_sse_params(Req) ->
    %% Parse workflow_id parameter
    WorkflowId = case cowboy_req:qs_val(<<"workflow_id">>, Req) of
        {undefined, _} -> undefined;
        {WfId, _} -> WfId
    end,

    %% Parse event_types parameter (comma-separated)
    EventTypes = case cowboy_req:qs_val(<<"event_types">>, Req) of
        {undefined, _} -> undefined;
        {TypesBin, _} ->
            BinaryList = binary:split(TypesBin, <<",">>),
            [binary_to_existing_atom(B, utf8) || B <- BinaryList]
    end,

    #{
        workflow_id => WorkflowId,
        event_types => EventTypes
    }.

%% @private
register_subscriber(_SubscriberId, Pid, WorkflowId, EventTypes) ->
    %% Ensure ETS table exists
    case ets:whereis(?SUBSCRIBER_TABLE) of
        undefined ->
            ets:new(?SUBSCRIBER_TABLE, [named_table, public, set, {keypos, #subscriber.pid}]);
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
unregister_subscriber(SubscriberId) ->
    case ets:whereis(?SUBSCRIBER_TABLE) of
        undefined -> ok;
        _ -> ets:delete(?SUBSCRIBER_TABLE, SubscriberId)
    end.

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
    Pid ! {sse_event, EventType, EventData};
send_event_to_subscriber(_, _EventType, _EventData) ->
    ok.

%% @private
send_sse_event(Req, EventName, Data) ->
    EventJson = jiffy:encode(Data),
    Event = [
        <<"event: ">>, EventName, <<"\r\n">>,
        <<"data: ">>, EventJson, <<"\r\n\r\n">>
    ],
    cowboy_req:stream_body(Event, Req).

%% @private
generate_subscriber_id() ->
    Timestamp = erlang:monotonic_time(millisecond),
    Random = rand:uniform(1000000),
    <<"sub_", (integer_to_binary(Timestamp))/binary, "_", (integer_to_binary(Random))/binary>>.

%%====================================================================
%% Supervisor Init
%%====================================================================

%% @doc Initialize SSE subsystem (called from application start).
-spec init_sse() -> ok.
init_sse() ->
    case ets:whereis(?SUBSCRIBER_TABLE) of
        undefined ->
            ets:new(?SUBSCRIBER_TABLE, [named_table, public, set, {keypos, #subscriber.pid}]),
            ok;
        _ -> ok
    end.
