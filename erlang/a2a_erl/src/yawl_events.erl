%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Event Manager
%%%
%%% This module implements the Observer pattern for YAWL workflow events.
%%% It provides:
%%%
%%% - Event subscription and notification
%%% - Event history tracking
%%% - Event filtering by type and workflow
%%% - Support for both synchronous and asynchronous event handling
%%%
%%% ## Event Types
%%%
%%% The following events are emitted:
%%% - `workflow_created`: A new workflow was created
%%% - `workflow_started`: Workflow execution has begun
%%% - `workflow_completed`: Workflow finished successfully
%%% - `workflow_failed`: Workflow failed with an error
%%% - `workflow_cancelled`: Workflow was cancelled
%%% - `workflow_suspended`: Workflow was suspended
%%% - `workflow_resumed`: Workflow was resumed
%%% - `task_started`: A task within a workflow started
%%% - `task_completed`: A task completed successfully
%%% - `task_failed`: A task failed
%%% - `checkpoint_created`: A checkpoint was created
%%% - `resource_allocated`: A resource was allocated
%%% - `resource_released`: A resource was released
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_events).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Subscription management
-export([
    subscribe/1,
    subscribe/2,
    subscribe/3,
    unsubscribe/1,
    unsubscribe/2
]).

%% API exports - Event emission
-export([
    emit/2,
    emit/3,
    emit_sync/2,
    emit_sync/3,
    emit_async/2,
    emit_async/3
]).

%% API exports - Event history
-export([
    get_history/0,
    get_history/1,
    get_history/2,
    get_history/3,
    clear_history/0,
    clear_history/1
]).

%% API exports - Event filtering
-export([
    get_events_by_type/1,
    get_events_by_workflow/1,
    get_events_by_time_range/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

%% Internal event record (not persisted to Mnesia)
-record(yawl_event, {
    event_id :: binary(),
    event_type :: event_type(),
    workflow_id :: binary() | undefined,
    data :: map(),
    timestamp :: integer(),
    metadata :: map()
}).

-record(state, {
    subscribers :: #{pid() => [event_type()]},
    workflows :: #{binary() => [pid()]},
    history :: [#yawl_event{}],
    max_history_size :: non_neg_integer(),
    history_by_workflow :: #{binary() => [#yawl_event{}]},
    event_counts :: #{event_type() => non_neg_integer()}
}).

%%====================================================================
%% Type Definitions
%%====================================================================

-type event_type() :: workflow_created | workflow_started | workflow_completed |
                       workflow_failed | workflow_cancelled | workflow_suspended |
                       workflow_resumed | task_started | task_completed | task_failed |
                       checkpoint_created | resource_allocated | resource_released |
                       error_occurred | custom_event.
-type subscription_filter() :: all | [event_type()] | fun((event_type()) -> boolean()).
-type event_handler() :: fun((#yawl_event{}) -> any()).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the event manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Subscribe to all events.
-spec subscribe(pid()) -> ok.
subscribe(Subscriber) ->
    subscribe(Subscriber, all).

%% @doc Subscribe to specific event types.
-spec subscribe(pid(), subscription_filter()) -> ok.
subscribe(Subscriber, Filter) ->
    subscribe(Subscriber, Filter, undefined).

%% @doc Subscribe to events for a specific workflow.
-spec subscribe(pid(), subscription_filter(), binary() | undefined) -> ok.
subscribe(Subscriber, Filter, WorkflowId) ->
    gen_server:call(?MODULE, {subscribe, Subscriber, Filter, WorkflowId}).

%% @doc Unsubscribe from all events.
-spec unsubscribe(pid()) -> ok.
unsubscribe(Subscriber) ->
    gen_server:call(?MODULE, {unsubscribe, Subscriber, undefined}).

%% @doc Unsubscribe from events for a specific workflow.
-spec unsubscribe(pid(), binary() | undefined) -> ok.
unsubscribe(Subscriber, WorkflowId) ->
    gen_server:call(?MODULE, {unsubscribe, Subscriber, WorkflowId}).

%% @doc Emit an event (alias for emit_async).
-spec emit(event_type(), map()) -> ok.
emit(EventType, Data) ->
    emit_async(EventType, Data).

%% @doc Emit an event for a specific workflow.
-spec emit(event_type(), binary(), map()) -> ok.
emit(EventType, WorkflowId, Data) ->
    emit_async(EventType, WorkflowId, Data).

%% @doc Emit an event synchronously (wait for all subscribers to handle).
-spec emit_sync(event_type(), map()) -> ok | {error, term()}.
emit_sync(EventType, Data) ->
    emit_sync(EventType, undefined, Data).

%% @doc Emit an event for a specific workflow synchronously.
-spec emit_sync(event_type(), binary() | undefined, map()) -> ok | {error, term()}.
emit_sync(EventType, WorkflowId, Data) ->
    Event = #yawl_event{
        event_id = generate_event_id(),
        event_type = EventType,
        workflow_id = WorkflowId,
        data = Data,
        timestamp = erlang:monotonic_time(millisecond),
        metadata = #{}
    },
    gen_server:call(?MODULE, {emit_sync, Event}).

%% @doc Emit an event asynchronously (fire and forget).
-spec emit_async(event_type(), map()) -> ok.
emit_async(EventType, Data) ->
    emit_async(EventType, undefined, Data).

%% @doc Emit an event for a specific workflow asynchronously.
-spec emit_async(event_type(), binary() | undefined, map()) -> ok.
emit_async(EventType, WorkflowId, Data) ->
    Event = #yawl_event{
        event_id = generate_event_id(),
        event_type = EventType,
        workflow_id = WorkflowId,
        data = Data,
        timestamp = erlang:monotonic_time(millisecond),
        metadata = #{}
    },
    gen_server:cast(?MODULE, {emit_async, Event}).

%% @doc Get all event history.
-spec get_history() -> {ok, [#yawl_event{}]}.
get_history() ->
    gen_server:call(?MODULE, get_history).

%% @doc Get event history for a specific workflow.
-spec get_history(binary()) -> {ok, [#yawl_event{}]}.
get_history(WorkflowId) ->
    gen_server:call(?MODULE, {get_history, WorkflowId}).

%% @doc Get event history with a limit.
-spec get_history(binary(), non_neg_integer()) -> {ok, [#yawl_event{}]}.
get_history(WorkflowId, Limit) ->
    gen_server:call(?MODULE, {get_history, WorkflowId, Limit}).

%% @doc Get event history with limit and offset.
-spec get_history(binary(), non_neg_integer(), non_neg_integer()) -> {ok, [#yawl_event{}]}.
get_history(WorkflowId, Limit, Offset) ->
    gen_server:call(?MODULE, {get_history, WorkflowId, Limit, Offset}).

%% @doc Clear all event history.
-spec clear_history() -> ok.
clear_history() ->
    gen_server:call(?MODULE, clear_history).

%% @doc Clear event history for a specific workflow.
-spec clear_history(binary()) -> ok.
clear_history(WorkflowId) ->
    gen_server:call(?MODULE, {clear_history, WorkflowId}).

%% @doc Get events by type.
-spec get_events_by_type(event_type()) -> {ok, [#yawl_event{}]}.
get_events_by_type(EventType) ->
    gen_server:call(?MODULE, {get_events_by_type, EventType}).

%% @doc Get events for a specific workflow.
-spec get_events_by_workflow(binary()) -> {ok, [#yawl_event{}]}.
get_events_by_workflow(WorkflowId) ->
    gen_server:call(?MODULE, {get_events_by_workflow, WorkflowId}).

%% @doc Get events within a time range.
-spec get_events_by_time_range(integer(), integer()) -> {ok, [#yawl_event{}]}.
get_events_by_time_range(StartTime, EndTime) ->
    gen_server:call(?MODULE, {get_events_by_time_range, StartTime, EndTime}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        subscribers = #{},
        workflows = #{},
        history = [],
        max_history_size = 10000,
        history_by_workflow = #{},
        event_counts = #{}
    },
    {ok, State}.

%% @private
handle_call({subscribe, Subscriber, Filter, WorkflowId}, _From, State) ->
    case validate_subscriber(Subscriber) of
        ok ->
            NewState = add_subscription(Subscriber, Filter, WorkflowId, State),
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({unsubscribe, Subscriber, WorkflowId}, _From, State) ->
    NewState = remove_subscription(Subscriber, WorkflowId, State),
    {reply, ok, NewState};

handle_call({emit_sync, Event}, _From, State) ->
    NewState = process_event(Event, State),
    {reply, ok, NewState};

handle_call(get_history, _From, State) ->
    {reply, {ok, State#state.history}, State};

handle_call({get_history, WorkflowId}, _From, State) ->
    Events = maps:get(WorkflowId, State#state.history_by_workflow, []),
    {reply, {ok, Events}, State};

handle_call({get_history, WorkflowId, Limit}, _From, State) ->
    Events = maps:get(WorkflowId, State#state.history_by_workflow, []),
    LimitedEvents = lists:sublist(Events, Limit),
    {reply, {ok, LimitedEvents}, State};

handle_call({get_history, WorkflowId, Limit, Offset}, _From, State) ->
    Events = maps:get(WorkflowId, State#state.history_by_workflow, []),
    FilteredEvents = case Offset + 1 > length(Events) of
        true -> [];
        false -> lists:nthtail(Offset, Events)
    end,
    LimitedEvents = lists:sublist(FilteredEvents, Limit),
    {reply, {ok, LimitedEvents}, State};

handle_call(clear_history, _From, State) ->
    NewState = State#state{
        history = [],
        history_by_workflow = #{},
        event_counts = #{}
    },
    {reply, ok, NewState};

handle_call({clear_history, WorkflowId}, _From, State) ->
    NewHistoryByWorkflow = maps:remove(WorkflowId, State#state.history_by_workflow),
    NewHistory = lists:filter(fun(E) -> E#yawl_event.workflow_id =/= WorkflowId end, State#state.history),
    NewState = State#state{
        history = NewHistory,
        history_by_workflow = NewHistoryByWorkflow
    },
    {reply, ok, NewState};

handle_call({get_events_by_type, EventType}, _From, State) ->
    Events = lists:filter(fun(E) -> E#yawl_event.event_type =:= EventType end, State#state.history),
    {reply, {ok, Events}, State};

handle_call({get_events_by_workflow, WorkflowId}, _From, State) ->
    Events = maps:get(WorkflowId, State#state.history_by_workflow, []),
    {reply, {ok, Events}, State};

handle_call({get_events_by_time_range, StartTime, EndTime}, _From, State) ->
    Events = lists:filter(fun(E) ->
        E#yawl_event.timestamp >= StartTime andalso E#yawl_event.timestamp =< EndTime
    end, State#state.history),
    {reply, {ok, Events}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({emit_async, Event}, State) ->
    NewState = process_event(Event, State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({'DOWN', _MonitorRef, process, Pid, _Info}, State) ->
    %% Remove subscriber when process dies
    NewState = remove_dead_subscriber(Pid, State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
generate_event_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    Timestamp = erlang:monotonic_time(millisecond),
    <<"event_", (integer_to_binary(Timestamp))/binary, "_",
      (integer_to_binary(UniqueId))/binary>>.

%% @private
validate_subscriber(Subscriber) when is_pid(Subscriber) ->
    case erlang:is_process_alive(Subscriber) of
        true -> ok;
        false -> {error, dead_subscriber}
    end;
validate_subscriber(_Subscriber) ->
    {error, invalid_subscriber}.

%% @private
add_subscription(Subscriber, Filter, WorkflowId, State) ->
    %% Monitor the subscriber process
    MonitorRef = erlang:monitor(process, Subscriber),

    %% Add to global subscribers
    CurrentFilters = maps:get(Subscriber, State#state.subscribers, []),
    NewFilters = case lists:member(Filter, CurrentFilters) of
        true -> CurrentFilters;
        false -> [Filter | CurrentFilters]
    end,
    NewSubscribers = maps:put(Subscriber, NewFilters, State#state.subscribers),

    %% Add to workflow-specific subscribers if WorkflowId is provided
    NewWorkflows = case WorkflowId of
        undefined ->
            State#state.workflows;
        _ ->
            CurrentWorkflowSubs = maps:get(WorkflowId, State#state.workflows, []),
            UpdatedWorkflowSubs = case lists:member(Subscriber, CurrentWorkflowSubs) of
                true -> CurrentWorkflowSubs;
                false -> [Subscriber | CurrentWorkflowSubs]
            end,
            maps:put(WorkflowId, UpdatedWorkflowSubs, State#state.workflows)
    end,

    %% Store monitor ref in process dictionary for cleanup
    put({monitor, Subscriber}, MonitorRef),

    State#state{
        subscribers = NewSubscribers,
        workflows = NewWorkflows
    }.

%% @private
remove_subscription(Subscriber, WorkflowId, State) ->
    %% Remove from global subscribers
    NewSubscribers = case WorkflowId of
        undefined ->
            maps:remove(Subscriber, State#state.subscribers);
        _ ->
            %% Keep the subscriber but update filters for workflow
            State#state.subscribers
    end,

    %% Remove from workflow-specific subscribers
    NewWorkflows = case WorkflowId of
        undefined ->
            %% Remove from all workflows
            maps:map(fun(_K, Subs) -> lists:delete(Subscriber, Subs) end, State#state.workflows);
        _ ->
            %% Remove from specific workflow
            CurrentWorkflowSubs = maps:get(WorkflowId, State#state.workflows, []),
            UpdatedWorkflowSubs = lists:delete(Subscriber, CurrentWorkflowSubs),
            maps:put(WorkflowId, UpdatedWorkflowSubs, State#state.workflows)
    end,

    %% Demonitor if exists
    case get({monitor, Subscriber}) of
        undefined -> ok;
        MonitorRef -> erlang:demonitor(MonitorRef), erase({monitor, Subscriber})
    end,

    State#state{
        subscribers = NewSubscribers,
        workflows = NewWorkflows
    }.

%% @private
remove_dead_subscriber(Pid, State) ->
    NewSubscribers = maps:remove(Pid, State#state.subscribers),
    NewWorkflows = maps:map(fun(_K, Subs) -> lists:delete(Pid, Subs) end, State#state.workflows),
    erase({monitor, Pid}),
    State#state{
        subscribers = NewSubscribers,
        workflows = NewWorkflows
    }.

%% @private
process_event(Event, State) ->
    %% Add to history
    NewHistory = add_to_history(Event, State#state.history, State#state.max_history_size),
    NewHistoryByWorkflow = add_to_workflow_history(Event, State#state.history_by_workflow),
    NewEventCounts = increment_event_count(Event#yawl_event.event_type, State#state.event_counts),

    %% Notify subscribers
    notify_subscribers(Event, State),

    %% Persist event if persistence is available
    persist_event(Event),

    State#state{
        history = NewHistory,
        history_by_workflow = NewHistoryByWorkflow,
        event_counts = NewEventCounts
    }.

%% @private
add_to_history(Event, History, MaxSize) ->
    NewHistory = [Event | History],
    case length(NewHistory) > MaxSize of
        true -> lists:sublist(NewHistory, MaxSize);
        false -> NewHistory
    end.

%% @private
add_to_workflow_history(Event, HistoryByWorkflow) ->
    case Event#yawl_event.workflow_id of
        undefined -> HistoryByWorkflow;
        WorkflowId ->
            CurrentHistory = maps:get(WorkflowId, HistoryByWorkflow, []),
            NewHistory = [Event | CurrentHistory],
            maps:put(WorkflowId, NewHistory, HistoryByWorkflow)
    end.

%% @private
increment_event_count(EventType, EventCounts) ->
    CurrentCount = maps:get(EventType, EventCounts, 0),
    maps:put(EventType, CurrentCount + 1, EventCounts).

%% @private
notify_subscribers(Event, State) ->
    EventType = Event#yawl_event.event_type,
    WorkflowId = Event#yawl_event.workflow_id,

    %% Get all relevant subscribers
    AllSubscribers = maps:keys(State#state.subscribers),

    %% Filter subscribers based on their subscription filters
    lists:foreach(fun(Subscriber) ->
        case should_notify(Subscriber, EventType, WorkflowId, State) of
            true ->
                catch Subscriber ! {yawl_event, Event};
            false ->
                ok
        end
    end, AllSubscribers).

%% @private
should_notify(Subscriber, EventType, WorkflowId, State) ->
    case maps:get(Subscriber, State#state.subscribers, []) of
        [] -> false;
        Filters ->
            %% Check if any filter matches
            lists:any(fun(Filter) ->
                matches_filter(Filter, EventType, WorkflowId, State)
            end, Filters)
    end.

%% @private
matches_filter(all, _EventType, _WorkflowId, _State) -> true;
matches_filter(FilterList, EventType, _WorkflowId, _State) when is_list(FilterList) ->
    lists:member(EventType, FilterList);
matches_filter(FilterFun, EventType, _WorkflowId, _State) when is_function(FilterFun, 1) ->
    try FilterFun(EventType) of
        true -> true;
        false -> false
    catch
        _:_ -> false
    end.

%% @private
persist_event(Event) ->
    case whereis(yawl_persistence) of
        undefined -> ok;
        _Pid ->
            HistoryId = Event#yawl_event.event_id,
            History = #yawl_execution_history{
                history_id = HistoryId,
                workflow_id = case Event#yawl_event.workflow_id of
                    undefined -> <<>>;
                    WfId -> WfId
                end,
                workitem_id = undefined,
                event_type = Event#yawl_event.event_type,
                event_data = Event#yawl_event.data,
                timestamp = Event#yawl_event.timestamp,
                source = yawl_events
            },
            spawn(fun() ->
                case yawl_persistence:save_history(History) of
                    ok -> ok;
                    {error, Reason} ->
                        logger:error("Failed to persist event: ~p", [Reason])
                end
            end)
    end.
