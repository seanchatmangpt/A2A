%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Event Adapter
%%%
%%% Translates between A2A events (used by yawl_a2a_events) and
%%% BeamAI's event system. This adapter provides bidirectional event
%%% forwarding with correlation support for distributed tracing.
%%%
%%% A2A event types (from yawl_a2a_events):
%%%   workitem_created, workitem_completed, workitem_failed,
%%%   workflow_started, workflow_completed, workflow_failed,
%%%   task_created, task_updated, task_completed, task_failed,
%%%   state_changed, artifact_update, etc.
%%%
%%% BeamAI event types (introduced by this adapter):
%%%   beamai_process_started, beamai_process_completed,
%%%   beamai_process_failed, beamai_graph_executed,
%%%   beamai_tool_invoked, beamai_state_changed, etc.
%%%
%%% Responsibilities:
%%% - Subscribe to A2A task events and forward to BeamAI subsystems
%%% - Subscribe to BeamAI process events and forward to A2A
%%% - Maintain event correlation for distributed tracing
%%% - Provide event history and statistics
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_event_adapter).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    subscribe/2,
    unsubscribe/1,
    publish/2,
    translate_event/1,
    correlate/2,
    get_correlation/1,
    get_statistics/0
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

%%%===================================================================
%%% Records
%%%===================================================================

-record(beamai_event, {
    id            :: binary(),
    type          :: atom(),
    source        :: a2a | beamai | bridge,
    original_type :: atom() | undefined,
    data          :: map(),
    correlation_id :: binary() | undefined,
    timestamp     :: integer()
}).

-record(subscriber_entry, {
    ref           :: reference(),
    pid           :: pid(),
    event_types   :: [atom()] | all,
    source_filter :: a2a | beamai | all,
    registered_at :: integer()
}).

-record(correlation_entry, {
    correlation_id :: binary(),
    a2a_event_id   :: binary() | undefined,
    beamai_event_id :: binary() | undefined,
    created_at     :: integer(),
    metadata       :: map()
}).

-record(state, {
    subscribers     :: #{reference() => #subscriber_entry{}},
    correlations    :: #{binary() => #correlation_entry{}},
    a2a_sub_ref     :: reference() | undefined,
    event_history   :: [#beamai_event{}],
    max_history     :: non_neg_integer(),
    max_correlations :: non_neg_integer(),
    config          :: map(),
    statistics      :: map()
}).

-define(SERVER, ?MODULE).

-define(DEFAULT_CONFIG, #{
    max_history => 500,
    max_correlations => 5000,
    auto_subscribe_a2a => true,
    forward_to_a2a => true
}).

%% Event type mappings: A2A -> BeamAI
-define(A2A_TO_BEAMAI_MAP, #{
    task_created     => beamai_process_started,
    task_updated     => beamai_state_changed,
    task_completed   => beamai_process_completed,
    task_failed      => beamai_process_failed,
    task_cancelled   => beamai_process_cancelled,
    state_changed    => beamai_state_changed,
    artifact_update  => beamai_output_produced,
    workitem_created => beamai_step_created,
    workitem_started => beamai_step_started,
    workitem_completed => beamai_step_completed,
    workitem_failed  => beamai_step_failed,
    workitem_cancelled => beamai_step_cancelled,
    workflow_started => beamai_graph_started,
    workflow_completed => beamai_graph_completed,
    workflow_failed  => beamai_graph_failed,
    mapping_created  => beamai_binding_created,
    mapping_removed  => beamai_binding_removed,
    sync_completed   => beamai_sync_completed,
    sync_failed      => beamai_sync_failed
}).

%% Event type mappings: BeamAI -> A2A
-define(BEAMAI_TO_A2A_MAP, #{
    beamai_process_started   => task_created,
    beamai_process_completed => task_completed,
    beamai_process_failed    => task_failed,
    beamai_process_cancelled => task_cancelled,
    beamai_state_changed     => state_changed,
    beamai_output_produced   => artifact_update,
    beamai_step_created      => workitem_created,
    beamai_step_started      => workitem_started,
    beamai_step_completed    => workitem_completed,
    beamai_step_failed       => workitem_failed,
    beamai_graph_started     => workflow_started,
    beamai_graph_completed   => workflow_completed,
    beamai_graph_failed      => workflow_failed,
    beamai_tool_invoked      => task_updated
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the event adapter with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the event adapter with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Subscribe to BeamAI events.
%% EventSpec is either the atom `all` or a list of BeamAI event types.
-spec subscribe(pid(), [atom()] | all) -> {ok, reference()}.
subscribe(Pid, EventSpec) ->
    gen_server:call(?SERVER, {subscribe, Pid, EventSpec}).

%% @doc Unsubscribe from events using the subscription reference.
-spec unsubscribe(reference()) -> ok.
unsubscribe(Ref) ->
    gen_server:cast(?SERVER, {unsubscribe, Ref}).

%% @doc Publish a BeamAI event. The event is translated and optionally
%% forwarded to the A2A event system.
-spec publish(atom(), map()) -> ok.
publish(EventType, EventData) ->
    gen_server:cast(?SERVER, {publish_beamai, EventType, EventData}).

%% @doc Translate a single event between A2A and BeamAI formats.
%% Returns a map representing the translated event.
-spec translate_event({atom(), atom(), map()}) -> {ok, map()} | {error, unmappable}.
translate_event({a2a, EventType, Data}) ->
    case maps:get(EventType, ?A2A_TO_BEAMAI_MAP, undefined) of
        undefined ->
            {error, unmappable};
        BeamaiType ->
            {ok, #{
                type => BeamaiType,
                original_type => EventType,
                source => a2a,
                data => Data,
                timestamp => erlang:system_time(millisecond)
            }}
    end;
translate_event({beamai, EventType, Data}) ->
    case maps:get(EventType, ?BEAMAI_TO_A2A_MAP, undefined) of
        undefined ->
            {error, unmappable};
        A2AType ->
            {ok, #{
                type => A2AType,
                original_type => EventType,
                source => beamai,
                data => Data,
                timestamp => erlang:system_time(millisecond)
            }}
    end;
translate_event(_) ->
    {error, unmappable}.

%% @doc Create a correlation between an A2A event ID and a BeamAI event ID.
%% This enables distributed tracing across the two systems.
-spec correlate(binary(), binary()) -> {ok, binary()}.
correlate(A2AEventId, BeamaiEventId) ->
    gen_server:call(?SERVER, {correlate, A2AEventId, BeamaiEventId}).

%% @doc Look up a correlation entry by correlation ID.
-spec get_correlation(binary()) -> {ok, map()} | {error, not_found}.
get_correlation(CorrelationId) ->
    gen_server:call(?SERVER, {get_correlation, CorrelationId}).

%% @doc Get event adapter statistics.
-spec get_statistics() -> map().
get_statistics() ->
    gen_server:call(?SERVER, get_statistics).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init(UserConfig) ->
    process_flag(trap_exit, true),
    Config = maps:merge(?DEFAULT_CONFIG, UserConfig),

    %% Auto-subscribe to A2A events if configured and available
    A2ARef = case maps:get(auto_subscribe_a2a, Config, true) of
        true -> try_subscribe_to_a2a_events();
        false -> undefined
    end,

    State = #state{
        subscribers = #{},
        correlations = #{},
        a2a_sub_ref = A2ARef,
        event_history = [],
        max_history = maps:get(max_history, Config, 500),
        max_correlations = maps:get(max_correlations, Config, 5000),
        config = Config,
        statistics = #{
            a2a_events_received => 0,
            beamai_events_published => 0,
            events_forwarded_to_a2a => 0,
            events_forwarded_to_beamai => 0,
            translations_performed => 0,
            correlations_created => 0,
            delivery_failures => 0
        }
    },

    logger:info("BeamAI event adapter initialized"),
    {ok, State}.

%% @private
handle_call({subscribe, Pid, EventSpec}, _From, State) ->
    Ref = erlang:monitor(process, Pid),
    Now = erlang:system_time(millisecond),
    Entry = #subscriber_entry{
        ref = Ref,
        pid = Pid,
        event_types = EventSpec,
        source_filter = all,
        registered_at = Now
    },
    NewSubs = maps:put(Ref, Entry, State#state.subscribers),
    {reply, {ok, Ref}, State#state{subscribers = NewSubs}};

handle_call({correlate, A2AEventId, BeamaiEventId}, _From, State) ->
    CorrelationId = generate_correlation_id(),
    Now = erlang:system_time(millisecond),
    Entry = #correlation_entry{
        correlation_id = CorrelationId,
        a2a_event_id = A2AEventId,
        beamai_event_id = BeamaiEventId,
        created_at = Now,
        metadata = #{}
    },
    Correlations = State#state.correlations,
    NewCorrelations = maybe_trim_correlations(
        maps:put(CorrelationId, Entry, Correlations),
        State#state.max_correlations
    ),
    Stats = State#state.statistics,
    CorrCount = maps:get(correlations_created, Stats, 0),
    NewStats = Stats#{correlations_created => CorrCount + 1},
    {reply, {ok, CorrelationId},
     State#state{correlations = NewCorrelations, statistics = NewStats}};

handle_call({get_correlation, CorrelationId}, _From, State) ->
    case maps:get(CorrelationId, State#state.correlations, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        #correlation_entry{} = Entry ->
            Map = #{
                correlation_id => Entry#correlation_entry.correlation_id,
                a2a_event_id => Entry#correlation_entry.a2a_event_id,
                beamai_event_id => Entry#correlation_entry.beamai_event_id,
                created_at => Entry#correlation_entry.created_at,
                metadata => Entry#correlation_entry.metadata
            },
            {reply, {ok, Map}, State}
    end;

handle_call(get_statistics, _From, State) ->
    ExtraStats = #{
        subscriber_count => map_size(State#state.subscribers),
        correlation_count => map_size(State#state.correlations),
        history_size => length(State#state.event_history),
        a2a_connected => State#state.a2a_sub_ref =/= undefined
    },
    FullStats = maps:merge(State#state.statistics, ExtraStats),
    {reply, FullStats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({unsubscribe, Ref}, State) ->
    erlang:demonitor(Ref, [flush]),
    NewSubs = maps:remove(Ref, State#state.subscribers),
    {noreply, State#state{subscribers = NewSubs}};

handle_cast({publish_beamai, EventType, EventData}, State) ->
    Now = erlang:system_time(millisecond),
    Event = #beamai_event{
        id = generate_event_id(),
        type = EventType,
        source = beamai,
        original_type = EventType,
        data = EventData,
        correlation_id = maps:get(correlation_id, EventData, undefined),
        timestamp = Now
    },

    %% Deliver to local subscribers
    NewState1 = deliver_to_subscribers(Event, State),

    %% Forward to A2A event system if configured
    NewState2 = maybe_forward_to_a2a(Event, NewState1),

    %% Record in history
    NewState3 = record_event(Event, NewState2),

    %% Update statistics
    Stats = NewState3#state.statistics,
    PubCount = maps:get(beamai_events_published, Stats, 0),
    NewStats = Stats#{beamai_events_published => PubCount + 1},

    {noreply, NewState3#state{statistics = NewStats}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({yawl_a2a_event, EventType, EventData}, State) ->
    %% Received an event from the A2A event system
    Now = erlang:system_time(millisecond),
    BeamaiType = maps:get(EventType, ?A2A_TO_BEAMAI_MAP, EventType),

    Event = #beamai_event{
        id = generate_event_id(),
        type = BeamaiType,
        source = a2a,
        original_type = EventType,
        data = EventData,
        correlation_id = maps:get(correlation_id, EventData, undefined),
        timestamp = Now
    },

    %% Deliver translated event to BeamAI subscribers
    NewState1 = deliver_to_subscribers(Event, State),

    %% Record in history
    NewState2 = record_event(Event, NewState1),

    %% Update statistics
    Stats = NewState2#state.statistics,
    RecvCount = maps:get(a2a_events_received, Stats, 0),
    TransCount = maps:get(translations_performed, Stats, 0),
    FwdCount = maps:get(events_forwarded_to_beamai, Stats, 0),
    NewStats = Stats#{
        a2a_events_received => RecvCount + 1,
        translations_performed => TransCount + 1,
        events_forwarded_to_beamai => FwdCount + 1
    },

    {noreply, NewState2#state{statistics = NewStats}};

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    NewSubs = maps:remove(Ref, State#state.subscribers),
    {noreply, State#state{subscribers = NewSubs}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{a2a_sub_ref = Ref}) ->
    case Ref of
        undefined -> ok;
        _ ->
            try yawl_a2a_events:unsubscribe(Ref)
            catch _:_ -> ok
            end
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Attempt to subscribe to A2A events via yawl_a2a_events.
-spec try_subscribe_to_a2a_events() -> reference() | undefined.
try_subscribe_to_a2a_events() ->
    try
        case whereis(yawl_a2a_events) of
            undefined -> undefined;
            _Pid ->
                {ok, Ref} = yawl_a2a_events:subscribe(self(), all),
                Ref
        end
    catch
        _:_ -> undefined
    end.

%% @private Deliver an event to all matching local subscribers.
-spec deliver_to_subscribers(#beamai_event{}, #state{}) -> #state{}.
deliver_to_subscribers(Event, State) ->
    #beamai_event{type = EventType, source = Source} = Event,
    EventMap = event_to_map(Event),

    {Delivered, Failed} = maps:fold(fun(_Ref, Sub, {DAcc, FAcc}) ->
        #subscriber_entry{pid = Pid, event_types = Types, source_filter = SrcFilter} = Sub,
        WantsType = case Types of
            all -> true;
            TypeList -> lists:member(EventType, TypeList)
        end,
        WantsSource = case SrcFilter of
            all -> true;
            Source -> true;
            _ -> false
        end,
        case WantsType andalso WantsSource of
            true ->
                try
                    Pid ! {beamai_event, EventType, EventMap},
                    {DAcc + 1, FAcc}
                catch
                    _:_ -> {DAcc, FAcc + 1}
                end;
            false ->
                {DAcc, FAcc}
        end
    end, {0, 0}, State#state.subscribers),

    Stats = State#state.statistics,
    FailCount = maps:get(delivery_failures, Stats, 0),
    NewStats = Stats#{delivery_failures => FailCount + Failed},
    State#state{statistics = NewStats}.

%% @private Optionally forward a BeamAI event to the A2A event system.
-spec maybe_forward_to_a2a(#beamai_event{}, #state{}) -> #state{}.
maybe_forward_to_a2a(Event, State) ->
    Config = State#state.config,
    case maps:get(forward_to_a2a, Config, true) of
        true ->
            #beamai_event{type = BeamaiType, data = Data} = Event,
            A2AType = maps:get(BeamaiType, ?BEAMAI_TO_A2A_MAP, undefined),
            case A2AType of
                undefined ->
                    State;
                _ ->
                    try
                        yawl_a2a_events:publish(A2AType, Data#{
                            beamai_source => true,
                            original_beamai_type => BeamaiType
                        }),
                        Stats = State#state.statistics,
                        FwdCount = maps:get(events_forwarded_to_a2a, Stats, 0),
                        NewStats = Stats#{events_forwarded_to_a2a => FwdCount + 1},
                        State#state{statistics = NewStats}
                    catch
                        _:_ -> State
                    end
            end;
        false ->
            State
    end.

%% @private Record an event in the history buffer.
-spec record_event(#beamai_event{}, #state{}) -> #state{}.
record_event(Event, #state{event_history = History, max_history = MaxHistory} = State) ->
    NewHistory = [Event | History],
    TrimmedHistory = case length(NewHistory) > MaxHistory of
        true -> lists:sublist(NewHistory, MaxHistory);
        false -> NewHistory
    end,
    State#state{event_history = TrimmedHistory}.

%% @private Convert a beamai_event record to a map for delivery.
-spec event_to_map(#beamai_event{}) -> map().
event_to_map(#beamai_event{} = E) ->
    #{
        id => E#beamai_event.id,
        type => E#beamai_event.type,
        source => E#beamai_event.source,
        original_type => E#beamai_event.original_type,
        data => E#beamai_event.data,
        correlation_id => E#beamai_event.correlation_id,
        timestamp => E#beamai_event.timestamp
    }.

%% @private Trim correlations map if it exceeds the maximum size.
-spec maybe_trim_correlations(map(), non_neg_integer()) -> map().
maybe_trim_correlations(Correlations, MaxSize) when map_size(Correlations) =< MaxSize ->
    Correlations;
maybe_trim_correlations(Correlations, MaxSize) ->
    %% Remove oldest entries to bring size under limit
    Sorted = lists:sort(fun(
        #correlation_entry{created_at = A},
        #correlation_entry{created_at = B}) ->
        A =< B
    end, maps:values(Correlations)),
    ToKeep = lists:nthtail(map_size(Correlations) - MaxSize, Sorted),
    lists:foldl(fun(#correlation_entry{correlation_id = CId} = E, Acc) ->
        maps:put(CId, E, Acc)
    end, #{}, ToKeep).

%% @private Generate a unique event identifier.
-spec generate_event_id() -> binary().
generate_event_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"bevt-", Hex/binary>>.

%% @private Generate a unique correlation identifier.
-spec generate_correlation_id() -> binary().
generate_correlation_id() ->
    Bytes = crypto:strong_rand_bytes(10),
    Hex = binary:encode_hex(Bytes),
    <<"bcorr-", Hex/binary>>.
