%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Event to XES Logging Bridge
%%%
%%% This module provides a bridge between the YAWL-A2A event system
%%% and XES (eXtensible Event Stream) logging. It subscribes to workflow
%%% events and transforms them into XES format for process mining
%%% and analysis.
%%%
%%% ## Features
%%%
%%% - Automatic subscription to yawl_a2a_events
%%% - Event transformation to XES format
%%% - Event filtering and routing
%%% - Configurable output destinations
%%% - Support for workflow and workitem traces
%%%
%%% ## Integration
%%%
%%% To enable the event bridge, add it to your supervision tree:
%%%
%%% ```erlang
%%% %% In a2a_erl_sup.erl ChildSpecs
%%% #{
%%%     id => yawl_event_bridge,
%%%     start => {yawl_event_bridge, start_link, []},
%%%     restart => permanent,
%%%     shutdown => 5000,
%%%     type => worker,
%%%     modules => [yawl_event_bridge]
%%% }
%%% ```
%%%
%%% Or start it manually:
%%%
%%% ```erlang
%%% {ok, Pid} = yawl_event_bridge:start_link().
%%%
%%% %% Configure XES output
%%% ok = yawl_event_bridge:configure_output(#{
%%%     type => file,
%%%     path => "/var/log/yawl/traces.xes"
%%% }).
%%%
%%% %% Subscribe to specific workflow events
%%% ok = yawl_event_bridge:subscribe_to_workflow(<<"wf123">>).
%%'
%%%
%%% ## XES Format
%%%
%%% The bridge generates XES-compliant event traces with:
%%% - Trace: Complete workflow execution
%%% - Event: Individual state changes
%%% - Attributes: Metadata for traces and events
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_event_bridge).
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

%% API - Bridge lifecycle
-export([
    start_link/1,
    stop/0,
    get_status/0
]).

%% API - Configuration
-export([
    configure_output/1,
    configure_filter/1,
    clear_filter/0,
    get_configuration/0
]).

%% API - Event routing
-export([
    subscribe_to_workflow/1,
    unsubscribe_from_workflow/1,
    add_event_handler/2,
    remove_event_handler/1
]).

%% API - XES operations
-export([
    export_trace/1,
    export_all_traces/0,
    get_trace_summary/1,
    get_statistics/0
]).

-include("yawl_types.hrl").
-include("a2a.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type output_config() :: #{
    type => file | stdio | callback | {module, atom()},
    path => binary() | undefined,
    callback => function() | undefined,
    buffer_size => integer(),
    auto_flush => boolean()
}.

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    %% Event subscription reference
    event_ref :: reference() | undefined,
    %% XES output configuration
    output_config :: map(),
    %% Active traces by workflow_id
    traces :: map(),
    %% Event filter function
    event_filter :: function() | undefined,
    %% Event handlers (additional processors)
    event_handlers :: [pid()],
    %% Statistics
    statistics :: map(),
    %% Buffer for batch writing
    event_buffer :: list(),
    buffer_size :: integer()
}).

-record(xes_trace, {
    trace_id :: binary(),
    workflow_id :: binary(),
    workflow_type :: atom(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    events :: list(),
    attributes :: map()
}).

-record(xes_event, {
    event_id :: binary(),
    event_type :: atom(),
    timestamp :: integer(),
    activity :: binary(),
    lifecycle :: binary(),
    resource :: binary() | undefined,
    attributes :: map()
}).

-type state() :: #state{}.
-type xes_trace() :: #xes_trace{}.
-type xes_event() :: #xes_event{}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the event bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the event bridge with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc Stop the event bridge and flush all pending events.
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Get the current bridge status.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?MODULE, get_status).

%% @doc Configure XES output destination.
-spec configure_output(output_config()) -> ok | {error, term()}.
configure_output(Config) when is_map(Config) ->
    gen_server:call(?MODULE, {configure_output, Config}).

%% @doc Configure event filter function.
%% Filter function: fun((EventType, EventData) -> boolean())
-spec configure_filter(function()) -> ok | {error, term()}.
configure_filter(FilterFun) when is_function(FilterFun, 2) ->
    gen_server:call(?MODULE, {configure_filter, FilterFun}).

%% @doc Clear the event filter.
-spec clear_filter() -> ok.
clear_filter() ->
    gen_server:call(?MODULE, clear_filter).

%% @doc Get current configuration.
-spec get_configuration() -> map().
get_configuration() ->
    gen_server:call(?MODULE, get_configuration).

%% @doc Subscribe to events for a specific workflow.
-spec subscribe_to_workflow(binary()) -> ok | {error, term()}.
subscribe_to_workflow(WorkflowId) when is_binary(WorkflowId) ->
    gen_server:call(?MODULE, {subscribe_workflow, WorkflowId}).

%% @doc Unsubscribe from a specific workflow.
-spec unsubscribe_from_workflow(binary()) -> ok.
unsubscribe_from_workflow(WorkflowId) when is_binary(WorkflowId) ->
    gen_server:cast(?MODULE, {unsubscribe_workflow, WorkflowId}).

%% @doc Add an additional event handler.
-spec add_event_handler(atom(), [term()]) -> {ok, pid()} | {error, term()}.
add_event_handler(Module, Args) ->
    gen_server:call(?MODULE, {add_handler, Module, Args}).

%% @doc Remove an event handler.
-spec remove_event_handler(pid()) -> ok.
remove_event_handler(Pid) when is_pid(Pid) ->
    gen_server:cast(?MODULE, {remove_handler, Pid}).

%% @doc Export a specific workflow trace.
-spec export_trace(binary()) -> {ok, binary()} | {error, term()}.
export_trace(WorkflowId) ->
    gen_server:call(?MODULE, {export_trace, WorkflowId}).

%% @doc Export all traces.
-spec export_all_traces() -> {ok, binary()} | {error, term()}.
export_all_traces() ->
    gen_server:call(?MODULE, export_all_traces).

%% @doc Get summary statistics for a trace.
-spec get_trace_summary(binary()) -> {ok, map()} | {error, term()}.
get_trace_summary(WorkflowId) ->
    gen_server:call(?MODULE, {trace_summary, WorkflowId}).

%% @doc Get overall bridge statistics.
-spec get_statistics() -> map().
get_statistics() ->
    gen_server:call(?MODULE, get_statistics).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Config) ->
    %% Subscribe to YAWL-A2A events
    case whereis(yawl_a2a_events) of
        undefined ->
            %% Event manager not available, start without subscription
            State = #state{
                event_ref = undefined,
                output_config = maps:get(output_config, Config, default_output_config()),
                traces = #{},
                event_filter = maps:get(filter, Config, undefined),
                event_handlers = [],
                statistics = init_statistics(),
                event_buffer = [],
                buffer_size = maps:get(buffer_size, Config, 100)
            },
            {ok, State};
        _EventMgrPid ->
            case yawl_a2a_events:subscribe(self()) of
                {ok, Ref} ->
                    State = #state{
                        event_ref = Ref,
                        output_config = maps:get(output_config, Config, default_output_config()),
                        traces = #{},
                        event_filter = maps:get(filter, Config, undefined),
                        event_handlers = [],
                        statistics = init_statistics(),
                        event_buffer = [],
                        buffer_size = maps:get(buffer_size, Config, 100)
                    },
                    {ok, State};
                {error, Reason} ->
                    {stop, {subscription_failed, Reason}}
            end
    end.

%% @private
handle_call(get_status, _From, State) ->
    Status = #{
        subscribed => State#state.event_ref =/= undefined,
        active_traces => maps:size(State#state.traces),
        buffered_events => length(State#state.event_buffer),
        handlers => length(State#state.event_handlers),
        output_type => maps:get(type, State#state.output_config, undefined)
    },
    {reply, Status, State};

handle_call({configure_output, Config}, _From, State) ->
    NewConfig = maps:merge(State#state.output_config, Config),
    {reply, ok, State#state{output_config = NewConfig}};

handle_call({configure_filter, FilterFun}, _From, State) ->
    {reply, ok, State#state{event_filter = FilterFun}};

handle_call(clear_filter, _From, State) ->
    {reply, ok, State#state{event_filter = undefined}};

handle_call(get_configuration, _From, State) ->
    Config = #{
        output_config => State#state.output_config,
        has_filter => State#state.event_filter =/= undefined,
        buffer_size => State#state.buffer_size
    },
    {reply, Config, State};

handle_call({subscribe_workflow, WorkflowId}, _From, State) ->
    %% Ensure a trace exists for this workflow
    NewTraces = case maps:get(WorkflowId, State#state.traces, undefined) of
        undefined ->
            Trace = #xes_trace{
                trace_id = generate_trace_id(WorkflowId),
                workflow_id = WorkflowId,
                workflow_type = unknown,
                start_time = erlang:monotonic_time(millisecond),
                end_time = undefined,
                events = [],
                attributes = #{}
            },
            maps:put(WorkflowId, Trace, State#state.traces);
        _ ->
            State#state.traces
    end,
    {reply, ok, State#state{traces = NewTraces}};

handle_call({add_handler, Module, Args}, _From, State) ->
    case supervisor:start_child(yawl_event_bridge_handler_sup,
        #{id => Module, start => {Module, start_link, Args}, restart => temporary,
          type => worker, modules => [Module]}) of
        {ok, Pid} ->
            {reply, {ok, Pid}, State#state{event_handlers = [Pid | State#state.event_handlers]}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({export_trace, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.traces, undefined) of
        undefined ->
            {reply, {error, trace_not_found}, State};
        Trace ->
            XESXml = trace_to_xes(Trace),
            OutputConfig = State#state.output_config,
            case write_output(XESXml, OutputConfig) of
                ok ->
                    {reply, {ok, XESXml}, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call(export_all_traces, _From, State) ->
    Traces = maps:values(State#state.traces),
    XESXml = traces_to_xes(Traces),
    OutputConfig = State#state.output_config,
    case write_output(XESXml, OutputConfig) of
        ok ->
            {reply, {ok, XESXml}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({trace_summary, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.traces, undefined) of
        undefined ->
            {reply, {error, trace_not_found}, State};
        Trace ->
            Summary = #{
                trace_id => Trace#xes_trace.trace_id,
                workflow_id => Trace#xes_trace.workflow_id,
                workflow_type => Trace#xes_trace.workflow_type,
                start_time => Trace#xes_trace.start_time,
                end_time => Trace#xes_trace.end_time,
                event_count => length(Trace#xes_trace.events),
                duration_ms => case Trace#xes_trace.end_time of
                    undefined -> undefined;
                    EndTime -> EndTime - Trace#xes_trace.start_time
                end
            },
            {reply, {ok, Summary}, State}
    end;

handle_call(get_statistics, _From, State) ->
    Stats = State#state.statistics,
    {reply, Stats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({unsubscribe_workflow, WorkflowId}, State) ->
    %% Close and export the trace if it exists
    NewTraces = case maps:get(WorkflowId, State#state.traces, undefined) of
        undefined ->
            State#state.traces;
        Trace ->
            %% Export before removing
            ClosedTrace = Trace#xes_trace{end_time = erlang:monotonic_time(millisecond)},
            XESXml = trace_to_xes(ClosedTrace),
            OutputConfig = State#state.output_config,
            _ = write_output(XESXml, OutputConfig),
            maps:remove(WorkflowId, State#state.traces)
    end,
    {noreply, State#state{traces = NewTraces}};

handle_cast({remove_handler, Pid}, State) ->
    NewHandlers = lists:filter(fun(H) -> H =/= Pid end, State#state.event_handlers),
    {noreply, State#state{event_handlers = NewHandlers}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({yawl_a2a_event, EventType, EventData}, State) ->
    %% Process incoming event
    NewState = process_event(EventType, EventData, State),
    {noreply, NewState};

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) when Ref =:= State#state.event_ref ->
    %% Event manager died, attempt to resubscribe
    case whereis(yawl_a2a_events) of
        undefined ->
            {noreply, State#state{event_ref = undefined}};
        _EventMgrPid ->
            case yawl_a2a_events:subscribe(self()) of
                {ok, NewRef} ->
                    {noreply, State#state{event_ref = NewRef}};
                {error, _} ->
                    {noreply, State#state{event_ref = undefined}}
            end
    end;

handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    %% Handler died, remove from list
    NewHandlers = lists:filter(fun(H) -> H =/= Pid end, State#state.event_handlers),
    {noreply, State#state{event_handlers = NewHandlers}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    %% Flush all traces before terminating
    flush_all_traces(State),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
process_event(EventType, EventData, State) ->
    %% Apply filter if configured
    case should_process_event(EventType, EventData, State) of
        true ->
            %% Transform to XES event
            XESEvent = convert_to_xes_event(EventType, EventData),

            %% Get or create trace
            WorkflowId = extract_workflow_id(EventData),
            {Traces, Stats} = case WorkflowId of
                undefined ->
                    %% No workflow ID, buffer for now
                    Buffer = [XESEvent | State#state.event_buffer],
                    _FlushedState = maybe_flush_buffer(Buffer, State),
                    UpdatedStats = update_stats(EventType, State#state.statistics),
                    {State#state.traces, UpdatedStats};
                _ ->
                    %% Add to trace
                    CurrentTraces = State#state.traces,
                    NewTraces = update_trace(WorkflowId, EventType, XESEvent, CurrentTraces),
                    UpdatedStats = update_stats(EventType, State#state.statistics),
                    {NewTraces, UpdatedStats}
            end,

            %% Notify handlers
            notify_handlers(XESEvent, State),

            State#state{traces = Traces, statistics = Stats};
        false ->
            State
    end.

%% @private
should_process_event(_EventType, _EventData, #state{event_filter = undefined}) ->
    true;
should_process_event(EventType, EventData, #state{event_filter = FilterFun}) ->
    try FilterFun(EventType, EventData) of
        Result -> Result
    catch
        _:_ -> true
    end.

%% @private
convert_to_xes_event(EventType, EventData) ->
    Timestamp = maps:get(timestamp, EventData, erlang:monotonic_time(millisecond)),
    Activity = event_type_to_activity(EventType),
    Lifecycle = event_type_to_lifecycle(EventType),
    Resource = maps:get(resource_id, EventData, maps_get(resource, EventData, undefined)),

    #xes_event{
        event_id = generate_event_id(),
        event_type = EventType,
        timestamp = Timestamp,
        activity = Activity,
        lifecycle = Lifecycle,
        resource = Resource,
        attributes = extract_attributes(EventData)
    }.

%% @private
event_type_to_activity(workflow_started) -> <<"WorkflowStarted">>;
event_type_to_activity(workflow_completed) -> <<"WorkflowCompleted">>;
event_type_to_activity(workflow_failed) -> <<"WorkflowFailed">>;
event_type_to_activity(workflow_cancelled) -> <<"WorkflowCancelled">>;
event_type_to_activity(workitem_created) -> <<"WorkitemCreated">>;
event_type_to_activity(workitem_allocated) -> <<"WorkitemAllocated">>;
event_type_to_activity(workitem_started) -> <<"WorkitemStarted">>;
event_type_to_activity(workitem_completed) -> <<"WorkitemCompleted">>;
event_type_to_activity(workitem_failed) -> <<"WorkitemFailed">>;
event_type_to_activity(workitem_cancelled) -> <<"WorkitemCancelled">>;
event_type_to_activity(task_created) -> <<"TaskCreated">>;
event_type_to_activity(task_updated) -> <<"TaskUpdated">>;
event_type_to_activity(task_completed) -> <<"TaskCompleted">>;
event_type_to_activity(task_failed) -> <<"TaskFailed">>;
event_type_to_activity(task_cancelled) -> <<"TaskCancelled">>;
event_type_to_activity(state_changed) -> <<"StateChanged">>;
event_type_to_activity(checkpoint_created) -> <<"CheckpointCreated">>;
event_type_to_activity(checkpoint_restored) -> <<"CheckpointRestored">>;
event_type_to_activity(mapping_created) -> <<"MappingCreated">>;
event_type_to_activity(mapping_removed) -> <<"MappingRemoved">>;
event_type_to_activity(sync_completed) -> <<"SyncCompleted">>;
event_type_to_activity(sync_failed) -> <<"SyncFailed">>;
event_type_to_activity(artifact_update) -> <<"ArtifactUpdated">>;
event_type_to_activity(_) -> <<"Unknown">>.

%% @private
event_type_to_lifecycle(EventType) ->
    case EventType of
        workflow_started -> <<"start">>;
        workflow_completed -> <<"complete">>;
        workflow_failed -> <<"complete">>;  % Failed is a terminal state
        workflow_cancelled -> <<"withdraw">>;
        workitem_created -> <<"schedule">>;
        workitem_allocated -> <<"assign">>;
        workitem_started -> <<"start">>;
        workitem_completed -> <<"complete">>;
        workitem_failed -> <<"complete">>;
        workitem_cancelled -> <<"withdraw">>;
        task_created -> <<"schedule">>;
        task_completed -> <<"complete">>;
        task_failed -> <<"complete">>;
        task_cancelled -> <<"withdraw">>;
        _ -> <<"unknown">>
    end.

%% @private
extract_workflow_id(EventData) ->
    maps_get(workflow_id, EventData,
        maps_get(workflow, EventData, undefined)).

%% @private
extract_attributes(EventData) ->
    %% Extract relevant attributes for XES
    Keys = [workitem_id, task_id, context_id, pattern_type, error, result],
    lists:foldl(fun(Key, Acc) ->
        case maps:get(Key, EventData, undefined) of
            undefined -> Acc;
            Value -> maps:put(Key, Value, Acc)
        end
    end, #{}, Keys).

%% @private
update_trace(WorkflowId, EventType, XESEvent, Traces) ->
    case maps:get(WorkflowId, Traces, undefined) of
        undefined ->
            %% Create new trace
            Trace = #xes_trace{
                trace_id = generate_trace_id(WorkflowId),
                workflow_id = WorkflowId,
                workflow_type = EventType,
                start_time = XESEvent#xes_event.timestamp,
                end_time = undefined,
                events = [XESEvent],
                attributes = #{}
            },
            maps:put(WorkflowId, Trace, Traces);
        Trace ->
            %% Update existing trace
            NewEvents = [XESEvent | Trace#xes_trace.events],
            NewEnd = case EventType of
                workflow_completed -> XESEvent#xes_event.timestamp;
                workflow_failed -> XESEvent#xes_event.timestamp;
                workflow_cancelled -> XESEvent#xes_event.timestamp;
                _ -> Trace#xes_trace.end_time
            end,
            UpdatedTrace = Trace#xes_trace{
                events = NewEvents,
                end_time = NewEnd
            },
            maps:put(WorkflowId, UpdatedTrace, Traces)
    end.

%% @private
maybe_flush_buffer(Buffer, State) ->
    case length(Buffer) >= State#state.buffer_size of
        true ->
            %% Flush buffer to file
            XESXml = buffer_to_xes(Buffer),
            OutputConfig = State#state.output_config,
            _ = write_output(XESXml, OutputConfig),
            State#state{event_buffer = []};
        false ->
            State#state{event_buffer = Buffer}
    end.

%% @private
flush_all_traces(State) ->
    Traces = maps:values(State#state.traces),
    XESXml = traces_to_xes(Traces),
    OutputConfig = State#state.output_config,
    _ = write_output(XESXml, OutputConfig),
    ok.

%% @private
update_stats(EventType, Stats) ->
    Total = maps:get(total_events, Stats, 0),
    ByType = maps:get(by_type, Stats, #{}),
    CurrentCount = maps:get(EventType, ByType, 0),
    Stats#{
        total_events => Total + 1,
        by_type => maps:put(EventType, CurrentCount + 1, ByType),
        last_event_time => erlang:monotonic_time(millisecond)
    }.

%% @private
notify_handlers(XESEvent, State) ->
    lists:foreach(fun(Pid) ->
        try
            Pid ! {xes_event, XESEvent}
        catch
            _:_ -> ok
        end
    end, State#state.event_handlers).

%% @private
write_output(Xml, #{type := stdio}) ->
    io:format("~s~n", [Xml]),
    ok;
write_output(Xml, #{type := file, path := Path}) ->
    case file:write_file(Path, Xml, [append]) of
        ok -> ok;
        {error, Reason} -> {error, {write_failed, Reason}}
    end;
write_output(Xml, #{type := callback, callback := Callback}) when is_function(Callback, 1) ->
    try Callback(Xml) of
        ok -> ok;
        Result -> Result
    catch
        _:_ -> {error, callback_failed}
    end;
write_output(Xml, #{type := {Module, Function}}) ->
    try Module:Function(Xml) of
        ok -> ok;
        Result -> Result
    catch
        _:_ -> {error, callback_failed}
    end;
write_output(_Xml, _Config) ->
    ok.

%% @private
trace_to_xes(Trace) ->
    EventsXml = lists:map(fun event_to_xml/1, lists:reverse(Trace#xes_trace.events)),
    <<"
    <trace>
        <string key=\"concept:name\" value=\"", (Trace#xes_trace.workflow_id)/binary, "\"/>
        <string key=\"workflow:id\" value=\"", (Trace#xes_trace.trace_id)/binary, "\"/>
        ",
        (binary:list_to_bin(EventsXml))/binary, "
    </trace>
    ">>.

%% @private
traces_to_xes(Traces) ->
    TracesXml = lists:map(fun trace_to_xml/1, Traces),
    <<"
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xes.features=\"nested-attributes\" openxes.version=\"1.0\">
    <extension name=\"Lifecycle\" prefix=\"lifecycle\" uri=\"http://www.xes-standard.org/lifecycle.xesext\"/>
    <extension name=\"Concept\" prefix=\"concept\" uri=\"http://www.xes-standard.org/concept.xesext\"/>
    <extension name=\"Time\" prefix=\"time\" uri=\"http://www.xes-standard.org/time.xesext\"/>
    <global scope=\"trace\">
        <string key=\"concept:name\" value=\"Workflow\"/>
    </global>
    <global scope=\"event\">
        <string key=\"concept:name\" value=\"Event\"/>
        <string key=\"lifecycle:transition\" value=\"unknown\"/>
    </global>
    ",
    (binary:list_to_bin(TracesXml))/binary, "
</log>
    ">>.

%% @private
trace_to_xml(Trace) ->
    EventsXml = lists:map(fun event_to_xml/1, lists:reverse(Trace#xes_trace.events)),
    <<"
    <trace>
        <string key=\"concept:name\" value=\"", (Trace#xes_trace.workflow_id)/binary, "\"/>
        <string key=\"workflow:id\" value=\"", (Trace#xes_trace.trace_id)/binary, "\"/>
        ",
        (binary:list_to_bin(EventsXml))/binary, "
    </trace>
    ">>.

%% @private
event_to_xml(Event) ->
    TimestampMs = integer_to_binary(Event#xes_event.timestamp),
    TimestampStr = list_to_binary(format_timestamp(Event#xes_event.timestamp)),
    ResourceAttr = case Event#xes_event.resource of
        undefined -> <<>>;
        Resource -> <<" <string key=\"org:resource\" value=\"", Resource/binary, "\"/>">>
    end,
    <<"
        <event>
            <string key=\"concept:name\" value=\"", (Event#xes_event.activity)/binary, "\"/>
            <string key=\"lifecycle:transition\" value=\"", (Event#xes_event.lifecycle)/binary, "\"/>
            <date key=\"time:timestamp\" value=\"", TimestampStr/binary, "\"/>
            <int key=\"time:timestamp_ms\" value=\"", TimestampMs/binary, "\"/>",
            ResourceAttr/binary, "
        </event>
    ">>.

%% @private
buffer_to_xes(Events) ->
    EventsXml = lists:map(fun event_to_xml/1, lists:reverse(Events)),
    <<"
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xes.features=\"nested-attributes\" openxes.version=\"1.0\">
    ",
    (binary:list_to_bin(EventsXml))/binary, "
</log>
    ">>.

%% @private
format_timestamp(Millis) ->
    %% Convert milliseconds to ISO 8601 format
    Seconds = Millis div 1000,
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:system_time_to_universal_time(Seconds, second),
    Ms = Millis rem 1000,
    lists:flatten(io_lib:format("~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0B.~3.10.0BZ",
        [Year, Month, Day, Hour, Minute, Second, Ms])).

%% @private
init_statistics() ->
    #{
        total_events => 0,
        by_type => #{},
        start_time => erlang:monotonic_time(millisecond)
    }.

%% @private
default_output_config() ->
    #{
        type => stdio,
        buffer_size => 100,
        auto_flush => true
    }.

%% @private
generate_trace_id(WorkflowId) ->
    <<"trace_", WorkflowId/binary, "_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>.

%% @private
generate_event_id() ->
    <<"evt_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
