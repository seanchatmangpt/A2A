%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-BeamAI Events Bridge
%%%
%%% Bidirectional event bridge between the YAWL event system
%%% (yawl_a2a_events) and BeamAI agent callbacks. This module:
%%%
%%% - Forwards YAWL workflow events to BeamAI agent callbacks
%%% - Forwards BeamAI agent events to YAWL event subscribers
%%% - Supports event filtering and transformation
%%% - Maintains event correlation for distributed tracing
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_yawl_events_bridge).
-behaviour(gen_server).

-include("../include/yawl_types.hrl").

%% API
-export([
    start_link/0,
    subscribe/2,
    publish/2,
    forward_yawl_event/1,
    forward_beamai_event/1,
    correlate/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(SERVER, ?MODULE).
-define(MAX_CORRELATION_ENTRIES, 10000).
-define(CORRELATION_TTL_MS, 600000). %% 10 minutes

-record(subscription, {
    ref :: reference(),
    pid :: pid(),
    filter :: all | [atom()],   %% event types to receive
    direction :: yawl | beamai | both,
    created_at :: integer()
}).

-record(correlation_entry, {
    correlation_id :: binary(),
    yawl_event_id :: binary() | undefined,
    beamai_event_id :: binary() | undefined,
    workflow_id :: binary(),
    event_type :: atom(),
    created_at :: integer(),
    metadata :: map()
}).

-record(state, {
    %% ref => subscription
    subscriptions = #{} :: #{reference() => #subscription{}},
    %% YAWL event system subscription ref
    yawl_sub_ref :: reference() | undefined,
    %% correlation_id => correlation_entry
    correlations = #{} :: #{binary() => #correlation_entry{}},
    %% Event transformation rules: {source_type, target_type} => transform_fun
    transform_rules = #{} :: #{atom() => fun()},
    %% Metrics
    metrics = #{} :: #{atom() => non_neg_integer()}
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the events bridge server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Subscribe to bridge events.
%% Filter can be 'all' or a list of event type atoms.
%% Returns a subscription reference for unsubscribing.
-spec subscribe(pid(), all | [atom()]) -> {ok, reference()}.
subscribe(Pid, Filter) ->
    gen_server:call(?SERVER, {subscribe, Pid, Filter}).

%% @doc Publish an event through the bridge.
%% The event will be forwarded to both YAWL and BeamAI systems
%% and to all matching subscribers.
-spec publish(atom(), map()) -> ok.
publish(EventType, EventData) ->
    gen_server:cast(?SERVER, {publish, EventType, EventData}).

%% @doc Forward a YAWL event to BeamAI agents.
%% Transforms the event and delivers it to relevant agents.
-spec forward_yawl_event(map()) -> ok.
forward_yawl_event(Event) ->
    gen_server:cast(?SERVER, {forward_yawl, Event}).

%% @doc Forward a BeamAI event to the YAWL system.
%% Transforms the event and publishes it via yawl_a2a_events.
-spec forward_beamai_event(map()) -> ok.
forward_beamai_event(Event) ->
    gen_server:cast(?SERVER, {forward_beamai, Event}).

%% @doc Correlate two events from different systems.
%% Creates a correlation entry linking a YAWL event to a BeamAI event.
-spec correlate(binary(), binary()) -> {ok, binary()} | {error, term()}.
correlate(YawlEventId, BeamAIEventId) ->
    gen_server:call(?SERVER, {correlate, YawlEventId, BeamAIEventId}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    %% Subscribe to YAWL events
    YawlSubRef = subscribe_to_yawl_events(),
    %% Initialize default transformation rules
    TransformRules = build_default_transforms(),
    InitMetrics = #{
        yawl_events_forwarded => 0,
        beamai_events_forwarded => 0,
        events_published => 0,
        correlations_created => 0,
        events_dropped => 0
    },
    logger:info("YAWL-BeamAI events bridge started"),
    {ok, #state{
        yawl_sub_ref = YawlSubRef,
        transform_rules = TransformRules,
        metrics = InitMetrics
    }}.

%% @private
handle_call({subscribe, Pid, Filter}, _From, State) ->
    #state{subscriptions = Subs} = State,
    Ref = erlang:monitor(process, Pid),
    Sub = #subscription{
        ref = Ref,
        pid = Pid,
        filter = Filter,
        direction = both,
        created_at = erlang:system_time(millisecond)
    },
    NewSubs = Subs#{Ref => Sub},
    {reply, {ok, Ref}, State#state{subscriptions = NewSubs}};

handle_call({correlate, YawlEventId, BeamAIEventId}, _From, State) ->
    #state{correlations = Correlations, metrics = Metrics} = State,
    CorrelationId = generate_correlation_id(),
    Entry = #correlation_entry{
        correlation_id = CorrelationId,
        yawl_event_id = YawlEventId,
        beamai_event_id = BeamAIEventId,
        workflow_id = <<>>,
        event_type = correlated,
        created_at = erlang:system_time(millisecond),
        metadata = #{}
    },
    NewCorrelations = maybe_trim_correlations(
        Correlations#{CorrelationId => Entry}
    ),
    Count = maps:get(correlations_created, Metrics, 0),
    NewMetrics = Metrics#{correlations_created => Count + 1},
    {reply, {ok, CorrelationId},
     State#state{correlations = NewCorrelations, metrics = NewMetrics}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({publish, EventType, EventData}, State) ->
    #state{metrics = Metrics} = State,
    %% Forward to YAWL
    publish_to_yawl(EventType, EventData),
    %% Forward to BeamAI agents
    deliver_to_beamai_agents(EventType, EventData),
    %% Deliver to local subscribers
    deliver_to_subscribers(EventType, EventData, both, State),
    %% Create correlation entry
    NewState = maybe_create_correlation(EventType, EventData, State),
    Count = maps:get(events_published, Metrics, 0),
    NewMetrics = (NewState#state.metrics)#{events_published => Count + 1},
    {noreply, NewState#state{metrics = NewMetrics}};

handle_cast({forward_yawl, Event}, State) ->
    #state{transform_rules = Rules, metrics = Metrics} = State,
    EventType = maps:get(event_type, Event, maps:get(type, Event, unknown)),
    %% Transform the event for BeamAI consumption
    TransformedEvent = transform_yawl_to_beamai(EventType, Event, Rules),
    %% Deliver to BeamAI agents
    BeamAIEventType = maps:get(beamai_event_type, TransformedEvent, EventType),
    deliver_to_beamai_agents(BeamAIEventType, TransformedEvent),
    %% Deliver to subscribers interested in YAWL events
    deliver_to_subscribers(EventType, TransformedEvent, yawl, State),
    %% Track correlation
    NewState = maybe_create_correlation(EventType, Event, State),
    Count = maps:get(yawl_events_forwarded, Metrics, 0),
    NewMetrics = (NewState#state.metrics)#{yawl_events_forwarded => Count + 1},
    {noreply, NewState#state{metrics = NewMetrics}};

handle_cast({forward_beamai, Event}, State) ->
    #state{transform_rules = Rules, metrics = Metrics} = State,
    EventType = maps:get(event_type, Event, maps:get(type, Event, unknown)),
    %% Transform the event for YAWL consumption
    TransformedEvent = transform_beamai_to_yawl(EventType, Event, Rules),
    %% Publish to YAWL event system
    YawlEventType = maps:get(yawl_event_type, TransformedEvent, EventType),
    publish_to_yawl(YawlEventType, TransformedEvent),
    %% Deliver to subscribers interested in BeamAI events
    deliver_to_subscribers(EventType, TransformedEvent, beamai, State),
    Count = maps:get(beamai_events_forwarded, Metrics, 0),
    NewMetrics = Metrics#{beamai_events_forwarded => Count + 1},
    {noreply, State#state{metrics = NewMetrics}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({yawl_a2a_event, EventType, EventData}, State) ->
    %% Received a YAWL event from the subscription
    forward_yawl_event(#{
        event_type => EventType,
        data => EventData,
        received_at => erlang:system_time(millisecond)
    }),
    {noreply, State};

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    #state{subscriptions = Subs} = State,
    NewSubs = maps:remove(Ref, Subs),
    {noreply, State#state{subscriptions = NewSubs}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{yawl_sub_ref = Ref}) ->
    unsubscribe_from_yawl(Ref),
    ok.

%%%===================================================================
%%% Internal Functions - Event Subscription
%%%===================================================================

%% @private Subscribe to YAWL events.
-spec subscribe_to_yawl_events() -> reference() | undefined.
subscribe_to_yawl_events() ->
    case whereis(yawl_a2a_events) of
        undefined -> undefined;
        _Pid ->
            try
                case yawl_a2a_events:subscribe(self(), all) of
                    {ok, Ref} -> Ref;
                    _ -> undefined
                end
            catch _:_ -> undefined
            end
    end.

%% @private Unsubscribe from YAWL events.
-spec unsubscribe_from_yawl(reference() | undefined) -> ok.
unsubscribe_from_yawl(undefined) -> ok;
unsubscribe_from_yawl(Ref) ->
    try yawl_a2a_events:unsubscribe(Ref)
    catch _:_ -> ok
    end.

%%%===================================================================
%%% Internal Functions - Event Transformation
%%%===================================================================

%% @private Build default transformation rules.
-spec build_default_transforms() -> map().
build_default_transforms() ->
    #{
        %% YAWL -> BeamAI transformations
        workitem_created => fun(Event) ->
            Event#{beamai_event_type => on_turn_start, phase => tool_preparation}
        end,
        workitem_started => fun(Event) ->
            Event#{beamai_event_type => on_turn_start, phase => tool_execution}
        end,
        workitem_completed => fun(Event) ->
            Event#{beamai_event_type => on_turn_end, phase => tool_completed}
        end,
        workitem_failed => fun(Event) ->
            Event#{beamai_event_type => on_turn_error, phase => tool_failed}
        end,
        workflow_started => fun(Event) ->
            Event#{beamai_event_type => on_turn_start, phase => workflow_start}
        end,
        workflow_completed => fun(Event) ->
            Event#{beamai_event_type => on_turn_end, phase => workflow_complete}
        end,
        workflow_failed => fun(Event) ->
            Event#{beamai_event_type => on_turn_error, phase => workflow_failed}
        end,
        %% BeamAI -> YAWL transformations
        on_turn_start => fun(Event) ->
            Event#{yawl_event_type => workflow_started}
        end,
        on_turn_end => fun(Event) ->
            Event#{yawl_event_type => workflow_completed}
        end,
        on_turn_error => fun(Event) ->
            Event#{yawl_event_type => workflow_failed}
        end,
        tool_call_start => fun(Event) ->
            Event#{yawl_event_type => workitem_started}
        end,
        tool_call_end => fun(Event) ->
            Event#{yawl_event_type => workitem_completed}
        end,
        tool_call_error => fun(Event) ->
            Event#{yawl_event_type => workitem_failed}
        end
    }.

%% @private Transform a YAWL event for BeamAI consumption.
-spec transform_yawl_to_beamai(atom(), map(), map()) -> map().
transform_yawl_to_beamai(EventType, Event, Rules) ->
    BaseTransformed = Event#{
        source_system => yawl,
        original_event_type => EventType,
        transformed_at => erlang:system_time(millisecond)
    },
    case maps:find(EventType, Rules) of
        {ok, TransformFun} when is_function(TransformFun, 1) ->
            try TransformFun(BaseTransformed)
            catch _:_ -> BaseTransformed
            end;
        _ ->
            BaseTransformed
    end.

%% @private Transform a BeamAI event for YAWL consumption.
-spec transform_beamai_to_yawl(atom(), map(), map()) -> map().
transform_beamai_to_yawl(EventType, Event, Rules) ->
    BaseTransformed = Event#{
        source_system => beamai,
        original_event_type => EventType,
        transformed_at => erlang:system_time(millisecond)
    },
    case maps:find(EventType, Rules) of
        {ok, TransformFun} when is_function(TransformFun, 1) ->
            try TransformFun(BaseTransformed)
            catch _:_ -> BaseTransformed
            end;
        _ ->
            BaseTransformed
    end.

%%%===================================================================
%%% Internal Functions - Event Delivery
%%%===================================================================

%% @private Publish an event to the YAWL event system.
-spec publish_to_yawl(atom(), map()) -> ok.
publish_to_yawl(EventType, EventData) ->
    case whereis(yawl_a2a_events) of
        undefined -> ok;
        _Pid ->
            try yawl_a2a_events:publish(EventType, EventData)
            catch _:_ -> ok
            end
    end.

%% @private Deliver an event to active BeamAI agents.
-spec deliver_to_beamai_agents(atom(), map()) -> ok.
deliver_to_beamai_agents(EventType, EventData) ->
    WorkflowId = maps:get(workflow_id, EventData, undefined),
    case WorkflowId of
        undefined -> ok;
        _ ->
            case whereis(beamai_yawl_bridge) of
                undefined -> ok;
                _Pid ->
                    try
                        case beamai_yawl_bridge:get_workflow_agent(WorkflowId) of
                            {ok, AgentPid} ->
                                AgentPid ! {beamai_event, EventType, EventData};
                            _ -> ok
                        end
                    catch _:_ -> ok
                    end
            end
    end.

%% @private Deliver an event to matching local subscribers.
-spec deliver_to_subscribers(atom(), map(), atom(), #state{}) -> ok.
deliver_to_subscribers(EventType, EventData, Direction, #state{subscriptions = Subs}) ->
    maps:foreach(fun(_Ref, Sub) ->
        ShouldDeliver = matches_subscription(EventType, Direction, Sub),
        case ShouldDeliver of
            true ->
                case is_process_alive(Sub#subscription.pid) of
                    true ->
                        Sub#subscription.pid ! {beamai_yawl_event, EventType, EventData};
                    false ->
                        ok
                end;
            false ->
                ok
        end
    end, Subs).

%% @private Check if an event matches a subscription's filter.
-spec matches_subscription(atom(), atom(), #subscription{}) -> boolean().
matches_subscription(EventType, Direction, #subscription{filter = Filter, direction = SubDir}) ->
    DirectionMatch = (SubDir =:= both) orelse (SubDir =:= Direction),
    FilterMatch = case Filter of
        all -> true;
        EventTypes when is_list(EventTypes) ->
            lists:member(EventType, EventTypes);
        _ -> true
    end,
    DirectionMatch andalso FilterMatch.

%%%===================================================================
%%% Internal Functions - Correlation
%%%===================================================================

%% @private Create a correlation entry if the event has tracking info.
-spec maybe_create_correlation(atom(), map(), #state{}) -> #state{}.
maybe_create_correlation(EventType, EventData, State) ->
    #state{correlations = Correlations} = State,
    WorkflowId = maps:get(workflow_id, EventData, <<>>),
    case WorkflowId of
        <<>> -> State;
        _ ->
            CorrelationId = generate_correlation_id(),
            EventId = maps:get(event_id, EventData,
                      maps:get(id, EventData, CorrelationId)),
            Entry = #correlation_entry{
                correlation_id = CorrelationId,
                yawl_event_id = case maps:get(source_system, EventData, yawl) of
                    yawl -> EventId;
                    _ -> undefined
                end,
                beamai_event_id = case maps:get(source_system, EventData, yawl) of
                    beamai -> EventId;
                    _ -> undefined
                end,
                workflow_id = WorkflowId,
                event_type = EventType,
                created_at = erlang:system_time(millisecond),
                metadata = #{
                    source => maps:get(source_system, EventData, unknown)
                }
            },
            NewCorrelations = maybe_trim_correlations(
                Correlations#{CorrelationId => Entry}
            ),
            State#state{correlations = NewCorrelations}
    end.

%% @private Trim old correlation entries when the map is too large.
-spec maybe_trim_correlations(map()) -> map().
maybe_trim_correlations(Correlations) when map_size(Correlations) > ?MAX_CORRELATION_ENTRIES ->
    Now = erlang:system_time(millisecond),
    maps:filter(fun(_Id, Entry) ->
        (Now - Entry#correlation_entry.created_at) < ?CORRELATION_TTL_MS
    end, Correlations);
maybe_trim_correlations(Correlations) ->
    Correlations.

%% @private Generate a correlation identifier.
-spec generate_correlation_id() -> binary().
generate_correlation_id() ->
    Rand = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<"corr_", Ts/binary, "_", Rand/binary>>.
