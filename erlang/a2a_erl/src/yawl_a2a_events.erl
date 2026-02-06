%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-A2A Event Notification System
%%%
%%% This module provides a centralized event notification system for
%%% coordinating state changes between YAWL workflows and A2A tasks.
%%%
%%% ## Event Types
%%%
%%% ### YAWL Events
%%% - `workitem_created`: A new workitem has been created
%%% - `workitem_allocated`: A workitem has been allocated to a resource
%%% - `workitem_started`: A workitem has started execution
%%% - `workitem_completed`: A workitem has completed successfully
%%% - `workitem_failed`: A workitem has failed
%%% - `workitem_cancelled`: A workitem has been cancelled
%%% - `workflow_started`: A workflow has started execution
%%% - `workflow_completed`: A workflow has completed
%%% - `workflow_failed`: A workflow has failed
%%%
%%% ### A2A Events
%%% - `task_created`: A new A2A task has been created
%%% - `task_updated`: An A2A task has been updated
%%% - `task_completed`: An A2A task has completed
%%% - `task_failed`: An A2A task has failed
%%% - `task_cancelled`: An A2A task has been cancelled
%%% - `state_changed`: Task state has changed
%%% - `artifact_update`: Task artifact has been updated
%%%
%%% ## Usage
%%%
%%% ```erlang
%%% %% Start the event manager
%%% yawl_a2a_events:start_link().
%%%
%%% %% Subscribe to events
%%% {ok, Ref} = yawl_a2a_events:subscribe(self()).
%%%
%%% %% Publish an event
%%% yawl_a2a_events:publish(workitem_created, #{workitem_id => <<"wi123">>}).
%%%
%%% %% Unsubscribe
%%% yawl_a2a_events:unsubscribe(Ref).
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_a2a_events).
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

%% API - Event management
-export([
    notify/2,
    notify/3,
    publish/2,
    publish/3
]).

%% API - Subscription management
-export([
    subscribe/1,
    subscribe/2,
    unsubscribe/1,
    unsubscribe/2,
    list_subscriptions/0
]).

%% API - Event filtering
-export([
    subscribe_with_filter/2,
    set_filter/2,
    clear_filter/1
]).

%% API - Event history
-export([
    get_event_history/0,
    get_event_history/1,
    get_event_history/2,
    clear_event_history/0
]).

-include("yawl_types.hrl").
-include("a2a.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    subscribers,
    filters,
    event_history,
    max_history_size,
    statistics
}).

-record(subscription, {
    ref,
    pid,
    subscriber_id,
    subscribed_at,
    event_types,
    filter
}).

-record(event_entry, {
    id,
    event_type,
    source,
    data,
    timestamp
}).

-record(event_stats, {
    total_published,
    total_delivered,
    total_failed,
    by_type
}).

-type subscription() :: #subscription{}.
-type event_entry() :: #event_entry{}.
-type event_stats() :: #event_stats{}.
-type event_filter() :: fun((atom(), map()) -> boolean()).
-type event_type() ::
    %% YAWL events
    workitem_created | workitem_allocated | workitem_started |
    workitem_completed | workitem_failed | workitem_cancelled |
    workflow_started | workflow_completed | workflow_failed |
    workflow_cancelled | checkpoint_created | checkpoint_restored |
    %% A2A events
    task_created | task_updated | task_completed | task_failed |
    task_cancelled | state_changed | artifact_update |
    %% Bridge events
    mapping_created | mapping_removed | sync_completed | sync_failed.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the event manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Notify subscribers of an event (from YAWL side).
-spec notify(event_type(), map()) -> ok.
notify(EventType, Data) ->
    notify(?MODULE, EventType, Data).

%% @doc Notify subscribers of an event with explicit source.
-spec notify(binary(), event_type(), map()) -> ok.
notify(Source, EventType, Data) ->
    gen_server:cast(?MODULE, {notify, Source, EventType, Data}).

%% @doc Publish an event to all subscribers.
-spec publish(event_type(), map()) -> ok.
publish(EventType, Data) ->
    publish(?MODULE, EventType, Data).

%% @doc Publish an event with explicit source.
-spec publish(binary(), event_type(), map()) -> ok.
publish(Source, EventType, Data) ->
    gen_server:cast(?MODULE, {publish, Source, EventType, Data}).

%% @doc Subscribe to all events.
-spec subscribe(pid()) -> {ok, reference()}.
subscribe(Subscriber) ->
    subscribe(Subscriber, all).

%% @doc Subscribe to specific event types.
-spec subscribe(pid(), [event_type()] | all) -> {ok, reference()}.
subscribe(Subscriber, EventTypes) ->
    gen_server:call(?MODULE, {subscribe, Subscriber, EventTypes}).

%% @doc Unsubscribe using monitor reference.
-spec unsubscribe(reference()) -> ok.
unsubscribe(Ref) ->
    gen_server:cast(?MODULE, {unsubscribe, Ref}).

%% @doc Unsubscribe a specific process from all events.
-spec unsubscribe(pid(), reference()) -> ok.
unsubscribe(Subscriber, Ref) ->
    gen_server:cast(?MODULE, {unsubscribe_pid, Subscriber, Ref}).

%% @doc List all active subscriptions.
-spec list_subscriptions() -> [{binary(), pid(), [event_type()]}].
list_subscriptions() ->
    gen_server:call(?MODULE, list_subscriptions).

%% @doc Subscribe with a custom filter function.
-spec subscribe_with_filter(pid(), event_filter()) -> {ok, reference()}.
subscribe_with_filter(Subscriber, FilterFun) when is_function(FilterFun, 2) ->
    gen_server:call(?MODULE, {subscribe_with_filter, Subscriber, FilterFun}).

%% @doc Set a filter for an existing subscription.
-spec set_filter(reference(), event_filter()) -> ok | {error, term()}.
set_filter(Ref, FilterFun) when is_function(FilterFun, 2) ->
    gen_server:call(?MODULE, {set_filter, Ref, FilterFun}).

%% @doc Clear a filter from a subscription.
-spec clear_filter(reference()) -> ok.
clear_filter(Ref) ->
    gen_server:call(?MODULE, {clear_filter, Ref}).

%% @doc Get event history (all events).
-spec get_event_history() -> [event_entry()].
get_event_history() ->
    gen_server:call(?MODULE, get_event_history).

%% @doc Get event history filtered by event type.
-spec get_event_history(event_type()) -> [event_entry()].
get_event_history(EventType) ->
    gen_server:call(?MODULE, {get_event_history_by_type, EventType}).

%% @doc Get event history with limit.
-spec get_event_history(event_type() | all, non_neg_integer()) -> [event_entry()].
get_event_history(EventType, Limit) ->
    gen_server:call(?MODULE, {get_event_history_limited, EventType, Limit}).

%% @doc Clear all event history.
-spec clear_event_history() -> ok.
clear_event_history() ->
    gen_server:call(?MODULE, clear_event_history).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        subscribers = #{},
        filters = #{},
        event_history = [],
        max_history_size = 1000,
        statistics = #event_stats{
            total_published = 0,
            total_delivered = 0,
            total_failed = 0,
            by_type = #{}
        }
    },
    {ok, State}.

%% @private
handle_call({subscribe, Subscriber, EventTypes}, {From, _}, State) ->
    Ref = erlang:monitor(process, Subscriber),
    SubscriptionId = generate_subscription_id(),
    Subscription = #subscription{
        ref = Ref,
        pid = Subscriber,
        subscriber_id = SubscriptionId,
        subscribed_at = erlang:monotonic_time(millisecond),
        event_types = EventTypes,
        filter = undefined
    },
    NewSubscribers = maps:put(Ref, Subscription, State#state.subscribers),
    {reply, {ok, Ref}, State#state{subscribers = NewSubscribers}};

handle_call({subscribe_with_filter, Subscriber, FilterFun}, {From, _}, State) ->
    Ref = erlang:monitor(process, Subscriber),
    SubscriptionId = generate_subscription_id(),
    Subscription = #subscription{
        ref = Ref,
        pid = Subscriber,
        subscriber_id = SubscriptionId,
        subscribed_at = erlang:monotonic_time(millisecond),
        event_types = all,
        filter = FilterFun
    },
    NewSubscribers = maps:put(Ref, Subscription, State#state.subscribers),
    NewFilters = maps:put(Ref, FilterFun, State#state.filters),
    {reply, {ok, Ref}, State#state{subscribers = NewSubscribers, filters = NewFilters}};

handle_call({set_filter, Ref, FilterFun}, _From, State) ->
    case maps:get(Ref, State#state.subscribers, undefined) of
        undefined ->
            {reply, {error, subscription_not_found}, State};
        _Subscription ->
            NewFilters = maps:put(Ref, FilterFun, State#state.filters),
            {reply, ok, State#state{filters = NewFilters}}
    end;

handle_call({clear_filter, Ref}, _From, State) ->
    NewFilters = maps:remove(Ref, State#state.filters),
    {reply, ok, State#state{filters = NewFilters}};

handle_call(list_subscriptions, _From, State) ->
    Subs = maps:fold(fun(_Ref, Sub, Acc) ->
        [{Sub#subscription.subscriber_id, Sub#subscription.pid, Sub#subscription.event_types} | Acc]
    end, [], State#state.subscribers),
    {reply, lists:reverse(Subs), State};

handle_call(get_event_history, _From, State) ->
    {reply, State#state.event_history, State};

handle_call({get_event_history_by_type, EventType}, _From, State) ->
    Filtered = lists:filter(fun(E) -> E#event_entry.event_type =:= EventType end,
                            State#state.event_history),
    {reply, Filtered, State};

handle_call({get_event_history_limited, EventType, Limit}, _From, State) ->
    Filtered = case EventType of
        all -> State#state.event_history;
        _ -> lists:filter(fun(E) -> E#event_entry.event_type =:= EventType end,
                          State#state.event_history)
    end,
    Result = lists:sublist(Filtered, Limit),
    {reply, Result, State};

handle_call(clear_event_history, _From, State) ->
    {reply, ok, State#state{event_history = []}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({notify, Source, EventType, Data}, State) ->
    NewState = do_notify(Source, EventType, Data, State),
    {noreply, NewState};

handle_cast({publish, Source, EventType, Data}, State) ->
    NewState = do_notify(Source, EventType, Data, State),
    {noreply, NewState};

handle_cast({unsubscribe, Ref}, State) ->
    NewSubscribers = maps:remove(Ref, State#state.subscribers),
    NewFilters = maps:remove(Ref, State#state.filters),
    {noreply, State#state{subscribers = NewSubscribers, filters = NewFilters}};

handle_cast({unsubscribe_pid, Subscriber, Ref}, State) ->
    NewSubscribers = maps:filter(fun(_R, Sub) -> Sub#subscription.pid =/= Subscriber orelse
                                                Sub#subscription.ref =/= Ref end,
                                 State#state.subscribers),
    NewFilters = maps:filter(fun(R, _F) -> R =/= Ref end, State#state.filters),
    {noreply, State#state{subscribers = NewSubscribers, filters = NewFilters}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    %% Remove subscriber when process dies
    NewSubscribers = maps:remove(Ref, State#state.subscribers),
    NewFilters = maps:remove(Ref, State#state.filters),
    {noreply, State#state{subscribers = NewSubscribers, filters = NewFilters}};

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
do_notify(Source, EventType, Data, State) ->
    %% Create event entry
    EventId = generate_event_id(),
    Event = #event_entry{
        id = EventId,
        event_type = EventType,
        source = Source,
        data = Data,
        timestamp = erlang:monotonic_time(millisecond)
    },

    %% Add to history
    NewHistory = add_to_history(Event, State#state.event_history, State#state.max_history_size),

    %% Update statistics
    NewStats = update_statistics(EventType, State#state.statistics),

    %% Deliver to subscribers
    {Delivered, Failed} = deliver_to_subscribers(Event, State),

    %% Update stats with delivery counts
    FinalStats = NewStats#event_stats{
        total_published = NewStats#event_stats.total_published + 1,
        total_delivered = NewStats#event_stats.total_delivered + Delivered,
        total_failed = NewStats#event_stats.total_failed + Failed
    },

    State#state{
        event_history = NewHistory,
        statistics = FinalStats
    }.

%% @private
add_to_history(Event, History, MaxSize) ->
    NewHistory = [Event | History],
    case length(NewHistory) > MaxSize of
        true -> lists:sublist(NewHistory, MaxSize);
        false -> NewHistory
    end.

%% @private
update_statistics(EventType, Stats) ->
    ByType = Stats#event_stats.by_type,
    CurrentCount = maps:get(EventType, ByType, 0),
    Stats#event_stats{by_type = maps:put(EventType, CurrentCount + 1, ByType)}.

%% @private
deliver_to_subscribers(Event, State) ->
    EventType = Event#event_entry.event_type,
    EventData = Event#event_entry.data,

    Subscriptions = maps:values(State#state.subscribers),
    Filters = State#state.filters,

    lists:foldl(fun(Subscription, {DeliveredAcc, FailedAcc}) ->
        %% Check if subscriber wants this event type
        WantsEvent = case Subscription#subscription.event_types of
            all -> true;
            Types -> lists:member(EventType, Types)
        end,

        if WantsEvent ->
            %% Check filter if present
            PassesFilter = case maps:get(Subscription#subscription.ref, Filters, undefined) of
                undefined -> true;
                FilterFun ->
                    try FilterFun(EventType, EventData) of
                        true -> true;
                        _ -> false
                    catch
                        _:_ -> true
                    end
            end,

            if PassesFilter ->
                %% Send event to subscriber
                Pid = Subscription#subscription.pid,
                Message = {yawl_a2a_event, EventType, EventData},
                case Pid ! Message of
                    Message -> {DeliveredAcc + 1, FailedAcc};
                    _ -> {DeliveredAcc, FailedAcc + 1}
                end;
            true ->
                {DeliveredAcc, FailedAcc}
            end;
        true ->
            {DeliveredAcc, FailedAcc}
        end
    end, {0, 0}, Subscriptions).

%% @private
generate_subscription_id() ->
    Timestamp = erlang:unique_integer([positive]),
    <<"sub_", (integer_to_binary(Timestamp))/binary>>.

%% @private
generate_event_id() ->
    Timestamp = erlang:unique_integer([positive]),
    <<"evt_", (integer_to_binary(Timestamp))/binary>>.
